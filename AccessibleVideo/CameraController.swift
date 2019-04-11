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
    func setResolution(width: Int, height: Int)
    func captureBuffer(_ sampleBuffer:CMSampleBuffer!)
}


func str4 (_ n: UInt32) -> String
{
    var s: String = String (describing: UnicodeScalar((n >> 24) & 0xFF)!)
    s.append(String(describing: UnicodeScalar((n >> 16) & 0xFF)!))
    s.append(String(describing: UnicodeScalar((n >> 8) & 0xFF)!))
    s.append(String(describing: UnicodeScalar(n & 0xFF)!))
    return (s)
}

//func stringBytes<Size:Int>(_string: String)
//{
//    let x = (Int, Int)
//    let mirror = Mirror(reflecting: x)
//    mirror
//}

func str4cc (_ string: String) -> UInt32
{
    let scalars:[UInt32] = string.utf8.prefix(4).map {
        return UInt32($0);
    }
    
    let result1:UInt32 = ((scalars[0] & 0xFF) << 24);
    let result2:UInt32 = ((scalars[1] & 0xFF) << 16);
    let result3:UInt32 = ((scalars[2] & 0xFF) << 8);
    let result4:UInt32 = ((scalars[3] & 0xFF));

    return UInt32(result1 | result2 | result3 | result4)
}

class CameraController:NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var delegate:CameraCaptureDelegate? = nil {
        didSet {
            if let format = _currentFormat {
                let resolution = CMVideoFormatDescriptionGetPresentationDimensions(format.formatDescription, usePixelAspectRatio: true, useCleanAperture: false)
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
            return _captureDevice?.isTorchAvailable ?? false
        }
    }
    
    var torchMode:Bool {
        get {
            return (_captureDevice?.torchMode ?? .off) == .on ? true : false
        }
        set {
            if _captureDevice?.isTorchAvailable ?? false {
                if let _ = ((try? _captureDevice?.lockForConfiguration()) as ()??) {
                    _captureDevice?.torchMode = newValue ? .on : .off
                    _captureDevice?.unlockForConfiguration()
                }
            }
        }
    }
    
    var useFrontCamera:Bool {
        get {
            return _preferredDevicePosition == .front
        }
        set {
            _preferredDevicePosition = newValue ? .front : .back
        }
    }
    
    var running:Bool = false {
        willSet {
            if _captureSession.isRunning != newValue {
                if newValue == true {
                    _captureSession.startRunning()
                } else {
                    _captureSession.stopRunning()
                }
            }
        }
    }
    
    fileprivate var _supportsFrontCamera:Bool = false
    fileprivate var _currentFormat:AVCaptureDevice.Format? = nil
    fileprivate var _supportedFormats:[AVCaptureDevice.Format]? = nil
    fileprivate var _captureInput:AVCaptureInput? = nil
    fileprivate var _captureOutput:AVCaptureVideoDataOutput? = nil
    fileprivate var _captureConnection:AVCaptureConnection? = nil
    fileprivate let _captureSession = AVCaptureSession()
    fileprivate var _captureDevice : AVCaptureDevice? = nil
    fileprivate var _captureDevices = [AVCaptureDevice.Position : AVCaptureDevice]()
    lazy fileprivate var _cameraQueue: DispatchQueue = DispatchQueue(label: "com.doomsdaytech.cameraqueue", attributes: [])
    
    fileprivate var _preferredFormat:String = "420f"
    fileprivate var _preferredMinFrameRate:Int32 = 60
    
    fileprivate var _preferredResolution:CGSize = CGSize(width: 1920, height: 1080)
    fileprivate var _minimumResolution:CGSize = CGSize(width: 1280, height: 720)
    
    
    fileprivate var _preferredDevicePosition:AVCaptureDevice.Position = .back {
        didSet {
            //            DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.high).async {
            if self.setDevice(self._preferredDevicePosition) {
                print("Successfully set device position")
            } else {
                print("Error setting device position")
            }
            //            }
        }
    }
    
    override init() {
        super.init()
        setupCamera()
        self.setDevice(self._preferredDevicePosition)
    }
    
    func setDevice(_ devicePosition:AVCaptureDevice.Position) -> Bool {
        // Loop through all the capture devices on this phone
        guard let device = _captureDevices[devicePosition], _captureDevice?.position != devicePosition else {
            return false
            
        }
        _captureDevice = device
        
        let formats = (device.formats ).filter {
            let formatCode = str4(CMFormatDescriptionGetMediaSubType($0.formatDescription))
            let resolution = CMVideoFormatDescriptionGetPresentationDimensions($0.formatDescription, usePixelAspectRatio: true, useCleanAperture: false)
            let ranges = ($0.videoSupportedFrameRateRanges ).filter {
                $0.maxFrameRate >= Float64(self._preferredMinFrameRate)
            }
            return (formatCode == self._preferredFormat
                && self._minimumResolution.width <= resolution.width
                && self._minimumResolution.height <= resolution.height
                && ranges.count > 0)
        }
        
        let preferredFormats = formats.filter {
            let resolution = CMVideoFormatDescriptionGetPresentationDimensions($0.formatDescription, usePixelAspectRatio: true, useCleanAperture: false)
            return (self._preferredResolution.width == resolution.width
                && self._preferredResolution.height == resolution.height)
        }
        
        if preferredFormats.count > 0 {
            _supportedFormats = preferredFormats
        } else {
            _supportedFormats = formats
        }
        
        for format in _supportedFormats! {
            _currentFormat = format
            guard let _ = ((try? _captureDevice?.lockForConfiguration()) as ()??) else {
                return false;
            }
            
            _captureDevice?.activeFormat = format
            // cap the framerate to the max set above
            _captureDevice?.activeVideoMaxFrameDuration = CMTime.init(value: 1, timescale: _preferredMinFrameRate)
            _captureDevice?.activeVideoMinFrameDuration = CMTime.init(value: 1, timescale: _preferredMinFrameRate)
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
                return false
            }
            
            _captureConnection = AVCaptureConnection(inputPorts: _captureInput!.ports, output: _captureOutput! as AVCaptureOutput)
            
            print("Supports video orientation: \(_captureConnection!.isVideoOrientationSupported)")
            
            if devicePosition == .front {
                _captureConnection!.videoOrientation = .landscapeRight
                _captureConnection!.automaticallyAdjustsVideoMirroring = false
                _captureConnection!.isVideoMirrored = true
            }
            
            print("Video mirrored: \(_captureConnection!.isVideoMirrored)")
            
            _captureSession.addInputWithNoConnections(_captureInput!)
            _captureSession.addConnection(_captureConnection!)
            _captureSession.commitConfiguration()
            
            let resolution = CMVideoFormatDescriptionGetPresentationDimensions(format.formatDescription, usePixelAspectRatio: true, useCleanAperture: false)
            self.delegate?.setResolution(width: Int(resolution.width), height: Int(resolution.height))
            
            if self.running {
                _captureSession.startRunning()
            }
            
            return true
        }
        return false
    }
    
    
    func setupCamera() {
        // initialize AVCaptureSession
        
        let devices = (AVCaptureDevice.devices() ).filter {
            ($0.position == .front || $0.position == .back) && $0.hasMediaType(AVMediaType(rawValue: convertFromAVMediaType(AVMediaType.video)))
        }
        
        for device in devices {
            var position:String = "Unknown"
            
            if device.position == .front {
                position = "Front Camera"
            } else if device.position == .back {
                position = "Rear Camera"
            }
            
            print("Device found: \(position)")
            print("...supports torch: \(device.isTorchAvailable)")
            
            var formatSet:Set<String> = []
            
            
            let formats = (device.formats ).filter {
                let formatCode = str4(CMFormatDescriptionGetMediaSubType($0.formatDescription))
                formatSet.insert(formatCode)
                return self._preferredFormat == formatCode
            }
            
            for format in formatSet {
                print("Found format \(format)")
            }
            
            for format in formats {
                let resolution = CMVideoFormatDescriptionGetPresentationDimensions(format.formatDescription, usePixelAspectRatio: true, useCleanAperture: false)

                let ranges = (format.videoSupportedFrameRateRanges ).filter {
                    $0.maxFrameRate >= Float64(self._preferredMinFrameRate)
                }
                if ranges.count > 0 {
                    _captureDevices[device.position] = device
                    if device.position == .front {
                        _supportsFrontCamera = true
                    }
                }
                
                if ranges.count > 0 {
                    print("Found format with resolution \(resolution.width)x\(resolution.height)")
                    print("...supports HDR: \(format.isVideoHDRSupported)")
                    print("...supports auto stabilization: \(format.isVideoStabilizationModeSupported(.auto))")
                    print("...supports cinematic stabilization: \(format.isVideoStabilizationModeSupported(.cinematic))")
                    
                    for range:AVFrameRateRange in ranges {
                        print("...supports \(range.maxFrameRate)fps video")
                    }
                }
            }
            
        }
        
        
        
        _captureOutput = AVCaptureVideoDataOutput()
        _captureOutput?.alwaysDiscardsLateVideoFrames = true
        
        let vidSettings = [kCVPixelBufferPixelFormatTypeKey as NSObject:NSNumber(value: str4cc(_preferredFormat)) ]
        
        _captureOutput?.videoSettings = (vidSettings as! [String : Any])
        
        _captureOutput?.setSampleBufferDelegate(self, queue: _cameraQueue)
        
        _captureSession.beginConfiguration()
        _captureSession.addOutputWithNoConnections(_captureOutput!)
        _captureSession.sessionPreset = AVCaptureSession.Preset(rawValue: convertFromAVCaptureSessionPreset(AVCaptureSession.Preset.inputPriority))
        _captureSession.commitConfiguration()
        
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        delegate?.captureBuffer(sampleBuffer)
    }
    
    var supportedResolutions:[CGSize?] {
        get {
            let formatsAndResolutions = (_captureDevice!.formats).map {
                return ($0, CMVideoFormatDescriptionGetPresentationDimensions($0.formatDescription, usePixelAspectRatio: true, useCleanAperture: false))
            }
            
            let filtered = formatsAndResolutions.lazy.filter {
                let format = $0.0
                let resolution = $0.1
                let formatCode = str4(CMFormatDescriptionGetMediaSubType(format.formatDescription))
                let ranges = (format.videoSupportedFrameRateRanges ).filter {
                    $0.maxFrameRate >= Float64(self._preferredMinFrameRate)
                }
                return (formatCode == self._preferredFormat
                    && self._preferredResolution.width <= resolution.width
                    && self._preferredResolution.height <= resolution.height
                    && ranges.count > 0)
            }
            
            return filtered.map {
                return CGSize(width: CGFloat($0.1.width), height: CGFloat($0.1.height))
            }
        }
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromAVMediaType(_ input: AVMediaType) -> String {
    return input.rawValue
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromAVCaptureSessionPreset(_ input: AVCaptureSession.Preset) -> String {
    return input.rawValue
}
