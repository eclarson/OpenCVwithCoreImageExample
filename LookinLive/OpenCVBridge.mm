//
//  OpenCVBridge.m
//  LookinLive
//
//  Created by Eric Larson on 8/27/15.
//  Copyright (c) 2015 Eric Larson. All rights reserved.
//

#import "OpenCVBridge.h"

#import "AVFoundation/AVFoundation.h"
#import <opencv2/opencv.hpp>
#import <opencv2/highgui/cap_ios.h>

using namespace cv;

@implementation OpenCVBridge


// code manipulated from
// http://stackoverflow.com/questions/30867351/best-way-to-create-a-mat-from-a-ciimage
// http://stackoverflow.com/questions/10254141/how-to-convert-from-cvmat-to-uiimage-in-objective-c

// give the detected face bounds and the image to OpenCV, and do what you want with it
+ (void)OpenCVTransferFaces:(CIFaceFeature *)faceFeature usingImage:(CIImage*)ciFrameImage andContext:(CIContext*)context
{
    //get face bounds and copy over smaller face image as CIIMage
    CGRect faceRect = faceFeature.bounds;
    CIImage *faceImage = [ciFrameImage imageByCroppingToRect:faceRect];
    CGImageRef faceImageCG = [context createCGImage:faceImage fromRect:faceRect];
    
    // setup the OPenCV mat fro copying into
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(faceImageCG);
    CGFloat cols = faceRect.size.width;
    CGFloat rows = faceRect.size.height;
    cv::Mat cvMat(rows, cols, CV_8UC4); // 8 bits per component, 4 channels
    
    // setup the copy buffer (to copy from the GPU)
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                 // Pointer to backing data
                                                    cols,                      // Width of bitmap
                                                    rows,                     // Height of bitmap
                                                    8,                          // Bits per component
                                                    cvMat.step[0],              // Bytes per row
                                                    colorSpace,                 // Colorspace
                                                    kCGImageAlphaNoneSkipLast |
                                                    kCGBitmapByteOrderDefault); // Bitmap info flags
    // do the copy
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), faceImageCG);
    
    // release intermediary buffer objects
    CGContextRelease(contextRef);
    CGImageRelease(faceImageCG);
    
    //do all processing here===================
    cv::Mat cvMatToShowOnScreen =[OpenCVBridge processImage:cvMat];
    
    //cv::Mat cvMatToShowOnScreen // unused in this function
    //end processing==========================

}

+ (CIImage*)OpenCVTransferFaceAndReturnNewImage:(CIFaceFeature *)faceFeature usingImage:(CIImage*)ciFrameImage andContext:(CIContext*)context{
    
    //get face bounds and copy over smaller face image as CIIMage
    CGRect faceRect = faceFeature.bounds;
    CIImage *faceImage = [ciFrameImage imageByCroppingToRect:faceRect];
    CGImageRef faceImageCG = [context createCGImage:faceImage fromRect:faceRect];
    
    // setup the OPenCV mat fro copying into
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(faceImageCG);
    CGFloat cols = faceRect.size.width;
    CGFloat rows = faceRect.size.height;
    cv::Mat cvMat(rows, cols, CV_8UC4); // 8 bits per component, 4 channels
    
    // setup the copy buffer (to copy from the GPU)
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                 // Pointer to backing data
                                                    cols,                      // Width of bitmap
                                                    rows,                     // Height of bitmap
                                                    8,                          // Bits per component
                                                    cvMat.step[0],              // Bytes per row
                                                    colorSpace,                 // Colorspace
                                                    kCGImageAlphaNoneSkipLast |
                                                    kCGBitmapByteOrderDefault); // Bitmap info flags
    // do the copy
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), faceImageCG);
    
    // release intermediary buffer objects
    CGContextRelease(contextRef);
    CGImageRelease(faceImageCG);
    
    // processing here===================
    
    //returned image will display out to Video Analgesic
    cv::Mat cvMatToShowOnScreen =[OpenCVBridge processImage:cvMat];
    
    //end processing==========================

    
    // convert back
    // setup NS byte buffer using the data from the cvMat to show
    NSData *data = [NSData dataWithBytes:cvMatToShowOnScreen.data length:cvMatToShowOnScreen.elemSize() * cvMatToShowOnScreen.total()];
    
    
    if (cvMatToShowOnScreen.elemSize() == 1) {
        colorSpace = CGColorSpaceCreateDeviceGray();
    } else {
        colorSpace = CGColorSpaceCreateDeviceRGB();
    }
    
    // setup buffering object
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    
    // setup the copy to go from CPU to GPU
    CGImageRef imageRef = CGImageCreate(cvMatToShowOnScreen.cols,                                     // Width
                                        cvMatToShowOnScreen.rows,                                     // Height
                                        8,                                              // Bits per component
                                        8 * cvMatToShowOnScreen.elemSize(),                           // Bits per pixel
                                        cvMatToShowOnScreen.step[0],                                  // Bytes per row
                                        colorSpace,                                     // Colorspace
                                        kCGImageAlphaNone | kCGBitmapByteOrderDefault,  // Bitmap info flags
                                        provider,                                       // CGDataProviderRef
                                        NULL,                                           // Decode
                                        false,                                          // Should interpolate
                                        kCGRenderingIntentDefault);                     // Intent
    // do the copy inside of the object instantiation for retImage
    CIImage* retImage = [[CIImage alloc]initWithCGImage:imageRef];
    
    
    // clean up
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
    return retImage;
    
}

// testing of the passing of params to swift
+(void)testFaceFeature:(CIFaceFeature *)faceFeature{
    
}

+(void)testImage:(CIImage*)ciFrameImage{
    
}

+(void)testContext:(CIContext*)context{
    
}

+(cv::Mat)processImage:(cv::Mat)input{
    // the overhead of using OpenCV here is dramatically reduced because it is on a smaller image of only the face
    cv::Mat frame_gray;
    cvtColor( input, frame_gray, CV_BGR2GRAY );
    bitwise_not(frame_gray, frame_gray);
    return frame_gray;
}

@end
