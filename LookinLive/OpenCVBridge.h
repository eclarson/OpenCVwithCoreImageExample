//
//  OpenCVBridge.h
//  LookinLive
//
//  Created by Eric Larson on 8/27/15.
//  Copyright (c) 2015 Eric Larson. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>

@interface OpenCVBridge : NSObject

+ (void)OpenCVTransferFaces:(CIFaceFeature *)faceFeature usingImage:(CIImage*)ciFrameImage andContext:(CIContext*)context;

+ (CIImage*)OpenCVTransferFaceAndReturnNewImage:(CIFaceFeature *)faceFeature usingImage:(CIImage*)ciFrameImage andContext:(CIContext*)context;

+(void)testFaceFeature:(CIFaceFeature *)faceFeature;

+(void)testImage:(CIImage*)ciFrameImage;

+(void)testContext:(CIContext*)context;



@end
