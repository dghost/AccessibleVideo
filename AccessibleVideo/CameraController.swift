//
//  Camera.swift
//  AccessibleVideo
//
//  Created by Luke Groeninger on 10/4/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//

import Foundation
import AVFoundation
import CoreVideo


protocol CameraCaptureDelegate {
    func setResolution(#width: Int, height: Int)
    func captureBuffer(sampleBuffer:CMSampleBuffer!)
}


func str4 (n: Int) -> String
{
    var s: String = String (UnicodeScalar((n >> 24) & 255))
    s.append(UnicodeScalar((n >> 16) & 255))
    s.append(UnicodeScalar((n >> 8) & 255))
    s.append(UnicodeScalar(n & 255))
    return (s)
}

class CameraController:NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var delegate:CameraCaptureDelegate? = nil {
        didSet {
            if let format = _currentFormat {
                let resolution = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                delegate?.setResolution(width: Int(resolution.width), height: Int(resolution.height))
            }
        }
    }
    var supportsFrontCamera:Bool {
        get {
            return _supportsFrontCamera
        }
    }
    
    var supportsTorch:Bool {
        get {
            return _captureDevice?.torchAvailable ?? false
        }
    }
    
    var torchMode:Bool {
        get {
            if let device = _captureDevice {
                return device.torchMode == .On ? true : false
            }
            return false
        }
        set {
            if _captureDevice?.torchAvailable ?? false {
                _captureDevice?.lockForConfiguration(nil)
                _captureDevice?.torchMode = newValue ? .On : .Off
                _captureDevice?.unlockForConfiguration()
            }
        }
    }
    
    var useFrontCamera:Bool {
        get {
            return _preferredDevicePosition == .Front
        }
        set {
            if newValue == true {
                _preferredDevicePosition = .Front
            } else {
                _preferredDevicePosition = .Back
            }
        }
    }
    
    var running:Bool = false {
        willSet {
            if _captureSession.running != newValue {
                if newValue == true {
                    _captureSession.startRunning()
                } else {
                    _captureSession.stopRunning()
                }
            }
        }
    }
    
    private var _supportsFrontCamera:Bool = false
    private var _currentFormat:AVCaptureDeviceFormat? = nil
    private var _supportedFormats:[AVCaptureDeviceFormat]? = nil
    private var _captureInput:AVCaptureInput? = nil
    private var _captureOutput:AVCaptureVideoDataOutput? = nil
    private var _captureConnection:AVCaptureConnection? = nil
    private let _captureSession = AVCaptureSession()
    private var _captureDevice : AVCaptureDevice? = nil
    private var _captureDevices = [AVCaptureDevicePosition : AVCaptureDevice]()
    lazy private var _cameraQueue: dispatch_queue_t = dispatch_queue_create("com.doomsdaytech.cameraqueue", DISPATCH_QUEUE_SERIAL)
    
    private var _preferredFormat:String = "420v"
    private var _preferredFrameRate:Int32 = 60
    private var _preferredResolution:CGSize = CGSizeMake(1280, 720)
    
    private var _preferredDevicePosition:AVCaptureDevicePosition = .Back {
        didSet {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)) {
                if self.setDevice(self._preferredDevicePosition) {
                    println("Successfully set device position")
                } else {
                    println("Error setting device position")
                }
            }
        }
    }
    
    override init() {
        super.init()
        setupCamera()
        self.setDevice(self._preferredDevicePosition)
    }
    
    func setDevice(devicePosition:AVCaptureDevicePosition) -> Bool {
        if _captureDevice?.position != devicePosition {
            // Loop through all the capture devices on this phone
            if let device = _captureDevices[devicePosition] {
                _captureDevice = device
                _supportedFormats = [AVCaptureDeviceFormat]()
                
                var bestFormat: AVCaptureDeviceFormat! = nil
                
                for format:AVCaptureDeviceFormat in _captureDevice!.formats as! [AVCaptureDeviceFormat] {
                    let resolution = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                    let formatCode = str4(Int(CMFormatDescriptionGetMediaSubType(format.formatDescription)))
                    if formatCode != _preferredFormat {
                        continue
                    }
                    
                    for range:AVFrameRateRange in format.videoSupportedFrameRateRanges as! [AVFrameRateRange] {
                        if (range.maxFrameRate >= Float64(_preferredFrameRate))
                        {
                            _supportedFormats?.append(format)
                            if (_preferredResolution.width > 0 && _preferredResolution.height > 0) {
                                if Int32(_preferredResolution.width) != resolution.width || Int32(_preferredResolution.height) != resolution.height {
                                    continue
                                }
                            }
                            bestFormat = format
                            // force 60fps cap - this keeps it in sync with the screen
                        }
                    }
                }
                
                if bestFormat != nil {
                    _currentFormat = bestFormat
                    _captureDevice?.lockForConfiguration(nil)
                    _captureDevice?.activeFormat = bestFormat
                    // cap the framerate to the max set above
                    _captureDevice?.activeVideoMaxFrameDuration = CMTimeMake(1, _preferredFrameRate)
                    _captureDevice?.activeVideoMinFrameDuration = CMTimeMake(1, _preferredFrameRate)
                    //            _captureDevice?.activeVideoMaxFrameDuration = bestFrameRate.minFrameDuration
                    //            _captureDevice?.activeVideoMinFrameDuration = bestFrameRate.minFrameDuration
                    _captureDevice?.unlockForConfiguration()
                }
                
                if let device:AVCaptureDevice! = _captureDevice {
                    if self.running {
                        _captureSession.stopRunning()
                    }

                    _captureSession.beginConfiguration()

                    if let connection:AVCaptureConnection! = _captureConnection {
                        _captureSession.removeConnection(connection)
                    }
                    if let input:AVCaptureInput! = _captureInput {
                        _captureSession.removeInput(input)
                    }
                    
                    var error: NSError?
                    _captureInput = AVCaptureDeviceInput(device: device, error: &error)
                    if (error != nil) {
                        println("Failed to create AVCaptureDeviceInput, error \(error)")
                    }
                    _captureConnection = AVCaptureConnection(inputPorts: _captureInput!.ports, output: _captureOutput! as AVCaptureOutput)
                    
                    println("Supports video orientation: \(_captureConnection!.supportsVideoOrientation)")


                    
                    if devicePosition == .Front {
                        _captureConnection!.videoOrientation = .LandscapeRight
                        _captureConnection!.automaticallyAdjustsVideoMirroring = false
                        _captureConnection!.videoMirrored = true
                    }
                    
                    var temp = ""
                    
                    switch (_captureConnection!.videoOrientation) {
                    case .Portrait:
                        temp = "Portrait"
                        break;
                    case .PortraitUpsideDown:
                        temp = "PortraitUpsideDown"
                        break;
                    case .LandscapeLeft:
                        temp = "LandscapeLeft"
                        break;
                    case .LandscapeRight:
                        temp = "LandscapeRight"
                        break;
                    }
                    
                    println(temp)
                    
                    println("Video mirrored: \(_captureConnection!.videoMirrored)")

                    
                    _captureSession.addInputWithNoConnections(_captureInput)
                    _captureSession.addConnection(_captureConnection)
                    _captureSession.commitConfiguration()

                    if let format = _currentFormat {
                        dispatch_async(_cameraQueue) {
                            let resolution = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                            self.delegate?.setResolution(width: Int(resolution.width), height: Int(resolution.height))
                        }
                    }
                    
                    if self.running {
                        _captureSession.startRunning()
                    }
                    
                    return true
                }
            }
        }
        return false
    }
    
    func setupCamera() {
        // initialize AVCaptureSession

        for device in (AVCaptureDevice.devices() as! [AVCaptureDevice]) {
            if (device.hasMediaType(AVMediaTypeVideo)) {
                
                var position:String = "Unknown"
                
                if device.position == .Front {
                    position = "Front Camera"
                } else if device.position == .Back {
                    position = "Rear Camera"
                }
                
                println("Device found: \(position)")
                println("...supports torch: \(device.torchAvailable)")

                for format:AVCaptureDeviceFormat in device.formats as! [AVCaptureDeviceFormat] {
                    let resolution = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                    
                    let formatCode = str4(Int(CMFormatDescriptionGetMediaSubType(format.formatDescription)))
                    if formatCode != _preferredFormat {
                        continue
                    }
                    
                    for range:AVFrameRateRange in format.videoSupportedFrameRateRanges as! [AVFrameRateRange] {
                        if (range.maxFrameRate >= Float64(_preferredFrameRate))
                        {
                            _captureDevices[device.position] = device
                            if device.position == .Front {
                                _supportsFrontCamera = true
                            }
                            
                            println("Found format \(formatCode) with resolution \(resolution.width)x\(resolution.height)")
                            println("...supports up to \(range.maxFrameRate)fps video")
                            println("...supports HDR: \(format.videoHDRSupported)")
                            println("...supports auto stabilization: \(format.isVideoStabilizationModeSupported(.Auto))")
                            println("...supports cinematic stabilization: \(format.isVideoStabilizationModeSupported(.Cinematic))")
                        }
                    }
                    
                }

            }
        }

        
        
        _captureOutput = AVCaptureVideoDataOutput()
        _captureOutput?.alwaysDiscardsLateVideoFrames = true
        
        let vidSettings = [kCVPixelBufferPixelFormatTypeKey as NSString:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        _captureOutput?.videoSettings = vidSettings
        
        _captureOutput?.setSampleBufferDelegate(self, queue: _cameraQueue)
    
        _captureSession.beginConfiguration()
        _captureSession.addOutputWithNoConnections(_captureOutput)
        _captureSession.sessionPreset = AVCaptureSessionPresetInputPriority
        _captureSession.commitConfiguration()

    }

    func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        delegate?.captureBuffer(sampleBuffer)
    }
    
    var supportedResolutions:[CGSize?] {
        get {
            var result = [CGSize?]()
            for format:AVCaptureDeviceFormat in _captureDevice!.formats as! [AVCaptureDeviceFormat] {
                let resolution = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let formatCode = str4(Int(CMFormatDescriptionGetMediaSubType(format.formatDescription)))
                if formatCode != "420v" {
                    continue
                }
                
                println("Found format \(formatCode) with resolution \(resolution.width)x\(resolution.height)")
                for range:AVFrameRateRange in format.videoSupportedFrameRateRanges as! [AVFrameRateRange] {
                    println("...supports up to \(range.maxFrameRate)fps video")
                    if (range.maxFrameRate >= 60.0)
                    {
                        result.append(CGSizeMake(CGFloat(resolution.width), CGFloat(resolution.height)))
                    }
                }
                println("...supports HDR: \(format.videoHDRSupported)")
                println("...supports auto stabilization: \(format.isVideoStabilizationModeSupported(.Auto))")
                println("...supports cinematic stabilization: \(format.isVideoStabilizationModeSupported(.Cinematic))")
                
            }
            return result
        }
    }
}