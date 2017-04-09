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


func str4 (_ n: Int) -> String
{
    var s: String = String (describing: UnicodeScalar((n >> 24) & 255)!)
    s.append(String(describing: UnicodeScalar((n >> 16) & 255)!))
    s.append(String(describing: UnicodeScalar((n >> 8) & 255)!))
    s.append(String(describing: UnicodeScalar(n & 255)!))
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
            return _captureDevice?.isTorchAvailable ?? false
        }
    }
    
    var torchMode:Bool {
        get {
            return (_captureDevice?.torchMode ?? .off) == .on ? true : false
        }
        set {
            if _captureDevice?.isTorchAvailable ?? false {
                if let _ = try? _captureDevice?.lockForConfiguration() {
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
    fileprivate var _currentFormat:AVCaptureDeviceFormat? = nil
    fileprivate var _supportedFormats:[AVCaptureDeviceFormat]? = nil
    fileprivate var _captureInput:AVCaptureInput? = nil
    fileprivate var _captureOutput:AVCaptureVideoDataOutput? = nil
    fileprivate var _captureConnection:AVCaptureConnection? = nil
    fileprivate let _captureSession = AVCaptureSession()
    fileprivate var _captureDevice : AVCaptureDevice? = nil
    fileprivate var _captureDevices = [AVCaptureDevicePosition : AVCaptureDevice]()
    lazy fileprivate var _cameraQueue: DispatchQueue = DispatchQueue(label: "com.doomsdaytech.cameraqueue", attributes: [])
    
    fileprivate var _preferredFormat:String = "420v"
    fileprivate var _preferredMinFrameRate:Int32 = 60
    
    fileprivate var _preferredResolution:CGSize = CGSize(width: 1280, height: 720)
    
    fileprivate var _preferredDevicePosition:AVCaptureDevicePosition = .back {
        didSet {
            DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.high).async {
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
    
    func setDevice(_ devicePosition:AVCaptureDevicePosition) -> Bool {
        // Loop through all the capture devices on this phone
        guard let device = _captureDevices[devicePosition], _captureDevice?.position != devicePosition else {
            return false
            
        }
        _captureDevice = device
        
        let formats = (device.formats as! [AVCaptureDeviceFormat]).filter {
            let formatCode = str4(Int(CMFormatDescriptionGetMediaSubType($0.formatDescription)))
            let resolution = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            let ranges = ($0.videoSupportedFrameRateRanges as! [AVFrameRateRange]).filter {
                $0.maxFrameRate >= Float64(self._preferredMinFrameRate)
            }
            return (formatCode == self._preferredFormat
                && Int32(self._preferredResolution.width) <= resolution.width
                && Int32(self._preferredResolution.height) <= resolution.height
                && ranges.count > 0)
        }
        
        _supportedFormats = formats
        
        for format in formats {
            _currentFormat = format
            guard let _ = try? _captureDevice?.lockForConfiguration() else {
                return false;
            }

            _captureDevice?.activeFormat = format
            // cap the framerate to the max set above
            _captureDevice?.activeVideoMaxFrameDuration = CMTimeMake(1, _preferredMinFrameRate)
            _captureDevice?.activeVideoMinFrameDuration = CMTimeMake(1, _preferredMinFrameRate)
            //            _captureDevice?.activeVideoMaxFrameDuration = bestFrameRate.minFrameDuration
            //            _captureDevice?.activeVideoMinFrameDuration = bestFrameRate.minFrameDuration
            _captureDevice?.unlockForConfiguration()
            
            if self.running {
                _captureSession.stopRunning()
            }
            
            _captureSession.beginConfiguration()
            
            if let connection = _captureConnection {
                _captureSession.remove(connection)
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
            
            _captureSession.addInputWithNoConnections(_captureInput)
            _captureSession.add(_captureConnection)
            _captureSession.commitConfiguration()
            
            _cameraQueue.async {
                let resolution = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                self.delegate?.setResolution(width: Int(resolution.width), height: Int(resolution.height))
            }
            
            
            if self.running {
                _captureSession.startRunning()
            }
            
            return true
        }
        return false
    }
    
    
    func setupCamera() {
        // initialize AVCaptureSession
        
        let devices = (AVCaptureDevice.devices() as! [AVCaptureDevice]).filter {
            ($0.position == .front || $0.position == .back) && $0.hasMediaType(AVMediaTypeVideo)
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
            
            let formats = (device.formats as! [AVCaptureDeviceFormat]).filter {
                let format = str4(Int(CMFormatDescriptionGetMediaSubType($0.formatDescription)))
                return self._preferredFormat == format
            }
            
            for format in formats {
                let resolution = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                
                let ranges = (format.videoSupportedFrameRateRanges as! [AVFrameRateRange]).filter {
                    $0.maxFrameRate >= Float64(self._preferredMinFrameRate)
                }
                if ranges.count > 0 {
                    _captureDevices[device.position] = device
                    if device.position == .front {
                        _supportsFrontCamera = true
                    }
                }
                
                for range:AVFrameRateRange in ranges {
                    print("Found format with resolution \(resolution.width)x\(resolution.height)")
                    print("...supports up to \(range.maxFrameRate)fps video")
                    print("...supports HDR: \(format.isVideoHDRSupported)")
                    print("...supports auto stabilization: \(format.isVideoStabilizationModeSupported(.auto))")
                    print("...supports cinematic stabilization: \(format.isVideoStabilizationModeSupported(.cinematic))")
                }
            }
            
        }

        
        
        _captureOutput = AVCaptureVideoDataOutput()
        _captureOutput?.alwaysDiscardsLateVideoFrames = true
        
        let vidSettings = [kCVPixelBufferPixelFormatTypeKey as NSObject:NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange as UInt32) ]
        _captureOutput?.videoSettings = vidSettings
        
        _captureOutput?.setSampleBufferDelegate(self, queue: _cameraQueue)
    
        _captureSession.beginConfiguration()
        _captureSession.addOutputWithNoConnections(_captureOutput)
        _captureSession.sessionPreset = AVCaptureSessionPresetInputPriority
        _captureSession.commitConfiguration()

    }

    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        delegate?.captureBuffer(sampleBuffer)
    }
    
    var supportedResolutions:[CGSize?] {
        get {
            let formatsAndResolutions = (_captureDevice!.formats as! [AVCaptureDeviceFormat]).lazy.map {
                return ($0, CMVideoFormatDescriptionGetDimensions($0.formatDescription))
            }
            
            let filtered = formatsAndResolutions.lazy.filter {
                let format = $0.0
                let resolution = $0.1
                let formatCode = str4(Int(CMFormatDescriptionGetMediaSubType(format.formatDescription)))
                let ranges = (format.videoSupportedFrameRateRanges as! [AVFrameRateRange]).filter {
                    $0.maxFrameRate >= Float64(self._preferredMinFrameRate)
                }
                return (formatCode == self._preferredFormat
                    && Int32(self._preferredResolution.width) <= resolution.width
                    && Int32(self._preferredResolution.height) <= resolution.height
                    && ranges.count > 0)
            }
            
            return filtered.map {
                return CGSize(width: CGFloat($0.1.width), height: CGFloat($0.1.height))
            }
        }
    }
}
