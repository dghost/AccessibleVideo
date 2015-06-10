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
    func setResolution(width width: Int, height: Int)
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
            return (_captureDevice?.torchMode ?? .Off) == .On ? true : false
        }
        set {
            if _captureDevice?.torchAvailable ?? false {
                do {
                    try _captureDevice?.lockForConfiguration()
                } catch _ {
                }
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
            _preferredDevicePosition = newValue ? .Front : .Back
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
                    print("Successfully set device position")
                } else {
                    print("Error setting device position")
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
        // Loop through all the capture devices on this phone
        if let device = _captureDevices[devicePosition] where _captureDevice?.position != devicePosition  {
            _captureDevice = device
            
            let formats = (device.formats as! [AVCaptureDeviceFormat]).filter {
                let formatCode = str4(Int(CMFormatDescriptionGetMediaSubType($0.formatDescription)))
                let resolution = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                let ranges = ($0.videoSupportedFrameRateRanges as! [AVFrameRateRange]).filter {
                    $0.maxFrameRate >= Float64(self._preferredFrameRate)
                }
                return (formatCode == self._preferredFormat
                    && Int32(self._preferredResolution.width) <= resolution.width
                    && Int32(self._preferredResolution.height) <= resolution.height
                    && ranges.count > 0)
            }
            
            _supportedFormats = formats
            
           for format in formats {
                _currentFormat = format
                do {
                    try _captureDevice?.lockForConfiguration()
                } catch _ {
                }
                _captureDevice?.activeFormat = format
                // cap the framerate to the max set above
                _captureDevice?.activeVideoMaxFrameDuration = CMTimeMake(1, _preferredFrameRate)
                _captureDevice?.activeVideoMinFrameDuration = CMTimeMake(1, _preferredFrameRate)
                //            _captureDevice?.activeVideoMaxFrameDuration = bestFrameRate.minFrameDuration
                //            _captureDevice?.activeVideoMinFrameDuration = bestFrameRate.minFrameDuration
                _captureDevice?.unlockForConfiguration()
                
                if self.running {
                    _captureSession.stopRunning()
                }
                
                _captureSession.beginConfiguration()
                
                if let connection = _captureConnection {
                    _captureSession.removeConnection(connection)
                }
                if let input = _captureInput {
                    _captureSession.removeInput(input)
                }
                
                do {
                    _captureInput = try AVCaptureDeviceInput(device: device)
                } catch let error as NSError {
                    _captureInput = nil
                    print("Failed to create AVCaptureDeviceInput, error \(error)")
                }

                _captureConnection = AVCaptureConnection(inputPorts: _captureInput!.ports, output: _captureOutput! as AVCaptureOutput)
                
                print("Supports video orientation: \(_captureConnection!.supportsVideoOrientation)")
                
                if devicePosition == .Front {
                    _captureConnection!.videoOrientation = .LandscapeRight
                    _captureConnection!.automaticallyAdjustsVideoMirroring = false
                    _captureConnection!.videoMirrored = true
                }
                
                print("Video mirrored: \(_captureConnection!.videoMirrored)")
                
                _captureSession.addInputWithNoConnections(_captureInput)
                _captureSession.addConnection(_captureConnection)
                _captureSession.commitConfiguration()
                
                dispatch_async(_cameraQueue) {
                    let resolution = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                    self.delegate?.setResolution(width: Int(resolution.width), height: Int(resolution.height))
                }
                
                
                if self.running {
                    _captureSession.startRunning()
                }
                
                return true
            }
        }
        return false
    }
    
    
    func setupCamera() {
        // initialize AVCaptureSession
        
        let devices = (AVCaptureDevice.devices() as! [AVCaptureDevice]).filter {
            ($0.position == .Front || $0.position == .Back) && $0.hasMediaType(AVMediaTypeVideo)
        }
        
        for device in devices {
            var position:String = "Unknown"
            
            if device.position == .Front {
                position = "Front Camera"
            } else if device.position == .Back {
                position = "Rear Camera"
            }
            
            print("Device found: \(position)")
            print("...supports torch: \(device.torchAvailable)")
            
            let formats = (device.formats as! [AVCaptureDeviceFormat]).filter {
                let formatCode = str4(Int(CMFormatDescriptionGetMediaSubType($0.formatDescription)))
                return (formatCode == self._preferredFormat)
            }
            
            for format in formats {
                let resolution = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                
                let ranges = (format.videoSupportedFrameRateRanges as! [AVFrameRateRange]).filter {
                    $0.maxFrameRate >= Float64(self._preferredFrameRate)
                }
                if ranges.count > 0 {
                    _captureDevices[device.position] = device
                    if device.position == .Front {
                        _supportsFrontCamera = true
                    }
                }
                
                for range:AVFrameRateRange in ranges {
                    print("Found format with resolution \(resolution.width)x\(resolution.height)")
                    print("...supports up to \(range.maxFrameRate)fps video")
                    print("...supports HDR: \(format.videoHDRSupported)")
                    print("...supports auto stabilization: \(format.isVideoStabilizationModeSupported(.Auto))")
                    print("...supports cinematic stabilization: \(format.isVideoStabilizationModeSupported(.Cinematic))")
                }
            }
            
        }

        
        
        _captureOutput = AVCaptureVideoDataOutput()
        _captureOutput?.alwaysDiscardsLateVideoFrames = true
        
        let vidSettings = [kCVPixelBufferPixelFormatTypeKey as NSObject:NSNumber(unsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) ]
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
            let formatsAndResolutions = (_captureDevice!.formats as! [AVCaptureDeviceFormat]).map {
                return ($0, CMVideoFormatDescriptionGetDimensions($0.formatDescription))
            }
            
            let filtered = formatsAndResolutions.filter {
                let format = $0.0
                let resolution = $0.1
                let formatCode = str4(Int(CMFormatDescriptionGetMediaSubType(format.formatDescription)))
                let ranges = (format.videoSupportedFrameRateRanges as! [AVFrameRateRange]).filter {
                    $0.maxFrameRate >= Float64(self._preferredFrameRate)
                }
                return (formatCode == self._preferredFormat
                    && Int32(self._preferredResolution.width) <= resolution.width
                    && Int32(self._preferredResolution.height) <= resolution.height
                    && ranges.count > 0)
            }
            
            return filtered.map {
                return CGSizeMake(CGFloat($0.1.width), CGFloat($0.1.height))
            }
        }
    }
}