//
//  VideoAnalgesic.swift
//  VideoAnalgesicTest
//
//  Created by Eric Larson on 2015.
//  Copyright (c) 2015 Eric Larson. All rights reserved.
//

import Foundation
import GLKit
import AVFoundation
import CoreImage


typealias ProcessBlock = ( imageInput : CIImage ) -> (CIImage)

class VideoAnalgesic: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    private var captureSessionQueue: dispatch_queue_t
    private var devicePosition: AVCaptureDevicePosition
    private var window:UIWindow??
    private var videoPreviewView:GLKView
    private var _eaglContext:EAGLContext!
    private var ciContext:CIContext!
    private var videoPreviewViewBounds:CGRect
    private var processBlock:ProcessBlock? = nil
    private var videoDevice: AVCaptureDevice? = nil
    private var captureSession:AVCaptureSession? = nil
    private var preset:String? = AVCaptureSessionPresetMedium
    private var captureOrient:AVCaptureVideoOrientation? = nil
    private var _isRunning:Bool = false

    var isRunning:Bool {
        get {
            return self._isRunning
        }
    }
    
    // singleton method 
    class var sharedInstance: VideoAnalgesic {
        
        struct Static {
            static let instance: VideoAnalgesic = VideoAnalgesic()
        }
        return Static.instance
    }
    
    // for setting the filters pipeline (r whatever processing you are doing)
    func setProcessingBlock(newProcessBlock:ProcessBlock)
    {
        self.processBlock = newProcessBlock // to find out: does Swift do a deep copy??
    }
    
    // for setting the camera we should use
    func setCameraPosition(position: AVCaptureDevicePosition){
        // AVCaptureDevicePosition.Back
        // AVCaptureDevicePosition.Front
        if(position != self.devicePosition){
            self.devicePosition = position;
            if(self.isRunning){
                self.stop()
                self.start()
            }
        }
    }
    
    // for setting the camera we should use
    func toggleCameraPosition(){
        // AVCaptureDevicePosition.Back
        // AVCaptureDevicePosition.Front
        switch self.devicePosition{
        case AVCaptureDevicePosition.Back:
            self.devicePosition = AVCaptureDevicePosition.Front
        case AVCaptureDevicePosition.Front:
            self.devicePosition = AVCaptureDevicePosition.Back
        default:
            self.devicePosition = AVCaptureDevicePosition.Front
        }
        
        if(self.isRunning){
            self.stop()
            self.start()
        }
    }
    
    // for setting the image quality
    func setPreset(preset: String){
        // AVCaptureSessionPresetPhoto
        // AVCaptureSessionPresetHigh
        // AVCaptureSessionPresetMedium <- default
        // AVCaptureSessionPresetLow
        // AVCaptureSessionPreset320x240
        // AVCaptureSessionPreset352x288
        // AVCaptureSessionPreset640x480
        // AVCaptureSessionPreset960x540
        // AVCaptureSessionPreset1280x720
        // AVCaptureSessionPresetiFrame960x540
        // AVCaptureSessionPresetiFrame1280x720
        if(preset != self.preset){
            self.preset = preset;
            if(self.isRunning){
                self.stop()
                self.start()
            }
        }
    }
    
    func getCIContext()->(CIContext?){
        if let context = self.ciContext{
            return context;
        }
        return nil;
    }
    
    func getImageOrientationFromUIOrientation(interfaceOrientation:UIInterfaceOrientation)->(Int){
        var ciOrientation = 1;
        
        switch interfaceOrientation{
        case UIInterfaceOrientation.Portrait:
            ciOrientation = 5
        case UIInterfaceOrientation.PortraitUpsideDown:
            ciOrientation = 7
        case UIInterfaceOrientation.LandscapeLeft:
            ciOrientation = 1
        case UIInterfaceOrientation.LandscapeRight:
            ciOrientation = 3
        default:
            ciOrientation = 1
        }
        
        return ciOrientation
    }
    
    func shutdown(){
        EAGLContext.setCurrentContext(self._eaglContext)
        self.processBlock = nil
        self.stop()
    }
    
    override init() {
        
        captureSessionQueue = dispatch_queue_create("capture_session_queue", nil)
        devicePosition = AVCaptureDevicePosition.Back
    
        self.window = UIApplication.sharedApplication().delegate?.window
        
        _eaglContext = EAGLContext(API: EAGLRenderingAPI.OpenGLES2)
        //        if _eaglContext==nil{
        //            NSLog("Attempting to fall back on OpenGL 2.0")
        //            _eaglContext = EAGLContext(API: EAGLRenderingAPI.OpenGLES2)
        //        }
        
        if _eaglContext != nil{
            videoPreviewView = GLKView(frame: window!!.bounds, context: _eaglContext)
            videoPreviewView.enableSetNeedsDisplay = false
            
            // because the native video image from the back camera is in UIDeviceOrientationLandscapeLeft (i.e. the home button is on the right), we need to apply a clockwise 90 degree transform so that we can draw the video preview as if we were in a landscape-oriented view; if you're using the front camera and you want to have a mirrored preview (so that the user is seeing themselves in the mirror), you need to apply an additional horizontal flip (by concatenating CGAffineTransformMakeScale(-1.0, 1.0) to the rotation transform)
            
            var transform = CGAffineTransformMakeRotation(CGFloat(M_PI_2))
            if devicePosition == AVCaptureDevicePosition.Front{
                transform = CGAffineTransformConcat(transform, CGAffineTransformMakeScale(-1.0, 1.0))
            }
            videoPreviewView.transform = transform
            videoPreviewView.frame = window!!.bounds
            
            // we make our video preview view a subview of the window, and send it to the back; this makes FHViewController's view (and its UI elements) on top of the video preview, and also makes video preview unaffected by device rotation
            window!!.addSubview(videoPreviewView)
            window!!.sendSubviewToBack(videoPreviewView)
            
            // create the CIContext instance, note that this must be done after _videoPreviewView is properly set up
            ciContext = CIContext(EAGLContext: _eaglContext)
            
            // bind the frame buffer to get the frame buffer width and height;
            // the bounds used by CIContext when drawing to a GLKView are in pixels (not points),
            // hence the need to read from the frame buffer's width and height;
            // in addition, since we will be accessing the bounds in another queue (_captureSessionQueue),
            // we want to obtain this piece of information so that we won't be
            // accessing _videoPreviewView's properties from another thread/queue
            videoPreviewView.bindDrawable()
            videoPreviewViewBounds = CGRectZero
        }
        else{
            NSLog("Could not fall back on OpenGL 2.0, exiting")
            videoPreviewView = GLKView()
            videoPreviewViewBounds = CGRectZero
        }
        
        super.init()
        

    }
    
    private func start_internal()->(){
        
        if (captureSession != nil){
            return; // we are already running, just return
        }
        
        NSNotificationCenter.defaultCenter().addObserver(self,
            selector:#selector(VideoAnalgesic.updateOrientation),
            name:"UIApplicationDidChangeStatusBarOrientationNotification",
            object:nil)
        
        dispatch_async(captureSessionQueue){
            let error:NSError? = nil;
            
            // get the input device and also validate the settings
            let videoDevices = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo)
            
            let position = self.devicePosition;
            
            self.videoDevice = nil;
            for device in videoDevices {
                if (device.position == position) {
                    self.videoDevice = device as? AVCaptureDevice
                    break;
                }
            }
            
            // obtain device input
            let videoDeviceInput: AVCaptureDeviceInput = (try! AVCaptureDeviceInput(device: self.videoDevice))
            
            if (error != nil)
            {
                NSLog("Unable to obtain video device input, error: \(error)");
                return;
            }
            
            
            if (self.videoDevice?.supportsAVCaptureSessionPreset(self.preset!)==false)
            {
                NSLog("Capture session preset not supported by video device: \(self.preset)");
                return;
            }
            
            // CoreImage wants BGRA pixel format
            //var outputSettings = [kCVPixelBufferPixelFormatTypeKey:NSNumber.numberWithInteger(kCVPixelFormatType_32BGRA)]
            
            // create the capture session
            self.captureSession = AVCaptureSession()
            self.captureSession!.sessionPreset = self.preset;
            
            // create and configure video data output
            let videoDataOutput = AVCaptureVideoDataOutput()
            //videoDataOutput.videoSettings = outputSettings;
            videoDataOutput.alwaysDiscardsLateVideoFrames = true;
            videoDataOutput.setSampleBufferDelegate(self, queue:self.captureSessionQueue)
            
            // begin configure capture session
            if let capture = self.captureSession{
                capture.beginConfiguration()
                
                if (!capture.canAddOutput(videoDataOutput))
                {
                    return;
                }
                
                // connect the video device input and video data and still image outputs
                capture.addInput(videoDeviceInput as AVCaptureInput)
                capture.addOutput(videoDataOutput)
                
                capture.commitConfiguration()
                
                // then start everything
                capture.startRunning()
            }
        
            self.updateOrientation()
        }
    }
    
    func updateOrientation(){
        if !self._isRunning{
            return
        }
        
        dispatch_async(dispatch_get_main_queue()){
            
            var transform : CGAffineTransform
            switch (UIDevice.currentDevice().orientation, self.videoDevice!.position){
            case (UIDeviceOrientation.LandscapeRight, AVCaptureDevicePosition.Back):
                transform = CGAffineTransformMakeRotation(CGFloat(M_PI))
            case (UIDeviceOrientation.LandscapeLeft, AVCaptureDevicePosition.Back):
                transform = CGAffineTransformIdentity
            case (UIDeviceOrientation.LandscapeLeft, AVCaptureDevicePosition.Front):
                transform = CGAffineTransformMakeRotation(CGFloat(M_PI))
                transform = CGAffineTransformConcat(transform, CGAffineTransformMakeScale(-1.0, 1.0))
            case (UIDeviceOrientation.LandscapeRight, AVCaptureDevicePosition.Front):
                transform = CGAffineTransformIdentity
                transform = CGAffineTransformConcat(transform, CGAffineTransformMakeScale(-1.0, 1.0))
            case (UIDeviceOrientation.PortraitUpsideDown, AVCaptureDevicePosition.Back):
                transform = CGAffineTransformMakeRotation(CGFloat(3*M_PI_2))
            case (UIDeviceOrientation.PortraitUpsideDown, AVCaptureDevicePosition.Front):
                transform = CGAffineTransformMakeRotation(CGFloat(3*M_PI_2))
                transform = CGAffineTransformConcat(transform, CGAffineTransformMakeScale(-1.0, 1.0))
            case (UIDeviceOrientation.Portrait, AVCaptureDevicePosition.Back):
                transform = CGAffineTransformMakeRotation(CGFloat(M_PI_2))
            case (UIDeviceOrientation.Portrait, AVCaptureDevicePosition.Front):
                transform = CGAffineTransformMakeRotation(CGFloat(M_PI_2))
                transform = CGAffineTransformConcat(transform, CGAffineTransformMakeScale(-1.0, 1.0))
            default:
                transform = CGAffineTransformMakeRotation(CGFloat(M_PI_2))
            }
            
            self.videoPreviewView.transform = transform
            self.videoPreviewView.frame = self.window!!.bounds
            
        }
    }
    
    func start(){
        
        self.videoPreviewViewBounds.size.width = CGFloat(self.videoPreviewView.drawableWidth)
        self.videoPreviewViewBounds.size.height = CGFloat(self.videoPreviewView.drawableHeight)
        
        
        // see if we have any video device
        if (AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo).count > 0)
        {
            self.start_internal()
            self._isRunning = true
        }
        else{
            NSLog("Could not start Analgesic video manager");
            NSLog("Be sure that you are running from an iOS device, not the simulator")
            self._isRunning = false;
        }
        
    }
    
    func stop(){
        if (self.captureSession==nil || self.captureSession!.running==false){
            return
        }
        
        self.captureSession!.stopRunning()
        
        NSNotificationCenter.defaultCenter().removeObserver(self,
            name: "UIApplicationDidChangeStatusBarOrientationNotification", object: nil)
        
        dispatch_sync(self.captureSessionQueue){
                NSLog("waiting for capture session to end")
        }
        NSLog("Done!")
        
        self.captureSession = nil
        self.videoDevice = nil
        self._isRunning = false
        
    }
    
    // video buffer delegate
    func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let sourceImage = CIImage(CVPixelBuffer: imageBuffer! as CVPixelBufferRef, options:nil)
        
        // run through a filter
        var filteredImage:CIImage! = nil;
        
        if(self.processBlock != nil){
            filteredImage=self.processBlock!(imageInput: sourceImage)
        }
        
        let sourceExtent:CGRect = sourceImage.extent
        
        let sourceAspect = sourceExtent.size.width / sourceExtent.size.height;
        let previewAspect = self.videoPreviewViewBounds.size.width  / self.videoPreviewViewBounds.size.height;
        
        // we want to maintain the aspect ratio of the screen size, so we clip the video image
        var drawRect = sourceExtent
        if (sourceAspect > previewAspect)
        {
            // use full height of the video image, and center crop the width
            drawRect.origin.x += (drawRect.size.width - drawRect.size.height * previewAspect) / 2.0;
            drawRect.size.width = drawRect.size.height * previewAspect;
        }
        else
        {
            // use full width of the video image, and center crop the height
            drawRect.origin.y += (drawRect.size.height - drawRect.size.width / previewAspect) / 2.0;
            drawRect.size.height = drawRect.size.width / previewAspect;
        }
        
        if (filteredImage != nil)
        {
            dispatch_async(dispatch_get_main_queue()){
                
                self.videoPreviewView.bindDrawable()
                
                if (self._eaglContext != EAGLContext.currentContext()){
                    EAGLContext.setCurrentContext(self._eaglContext)
                }
                
                // clear eagl view to grey
                glClearColor(0.5, 0.5, 0.5, 1.0);
                glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
                
                // set the blend mode to "source over" so that CI will use that
                glEnable(GLenum(GL_BLEND))
                glBlendFunc(GLenum(GL_ONE), GLenum(GL_ONE_MINUS_SRC_ALPHA))
                
                
                if (filteredImage != nil){
                    self.ciContext.drawImage(filteredImage, inRect:self.videoPreviewViewBounds, fromRect:drawRect)
                }
            
                self.videoPreviewView.display()
            }
        }

    }
    
    func toggleFlash()->(Bool){
        var isOn = false
        if let device = self.videoDevice{
            if (device.hasTorch && self.devicePosition == AVCaptureDevicePosition.Back) {
                do {
                    try device.lockForConfiguration()
                } catch _ {
                }
                if (device.torchMode == AVCaptureTorchMode.On) {
                    device.torchMode = AVCaptureTorchMode.Off
                } else {
                    do {
                        try device.setTorchModeOnWithLevel(1.0)
                        isOn = true
                    } catch _ {
                        isOn = false
                    }
                }
                device.unlockForConfiguration()
            }
        }
        return isOn
    }
    
    
    func turnOnFlashwithLevel(level:Float) -> (Bool){
        var isOverHeating = false
        if let device = self.videoDevice{
            if (device.hasTorch && self.devicePosition == AVCaptureDevicePosition.Back && level>0 && level<=1) {
                do {
                    try device.lockForConfiguration()
                } catch _ {
                }
                do {
                    try device.setTorchModeOnWithLevel(level)
                    isOverHeating = true
                } catch _ {
                    isOverHeating = false
                }
                device.unlockForConfiguration()
            }
        }
        return isOverHeating
    }
    
    
    func turnOffFlash(){
        if let device = self.videoDevice{
            if (device.hasTorch && device.torchMode == AVCaptureTorchMode.On) {
                do {
                    try device.lockForConfiguration()
                } catch _ {
                }
                device.torchMode = AVCaptureTorchMode.Off
                device.unlockForConfiguration()
            }
        }
    }
    
    
}