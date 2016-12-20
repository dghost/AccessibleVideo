//
//  FilterBuffer.swift
//  AccessibleVideo
//
//  Created by Luke Groeninger on 12/21/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//

class FilterBuffer:MetalBuffer {
    fileprivate var _lowThreshold:UnsafeMutablePointer<Float32>! = nil
    fileprivate var _highThreshold:UnsafeMutablePointer<Float32>! = nil
    
    override func setContents(_ arguments: MTLArgument) {
        if arguments.name == "filterParameters" {
            primaryColor = nil
            secondaryColor = nil
            _lowThreshold = nil
            _highThreshold = nil
            
            let parameters = arguments.bufferStructType.members as [MTLStructMember]
            for parameter in parameters {
                print("Found parameter \(parameter.name) at offset \(parameter.offset)")
                let pointer = _filterBufferData.advanced(by: parameter.offset)
                
                switch(parameter.name) {
                case "primaryColor":
                    primaryColor = Color(buffer: pointer.assumingMemoryBound(to: UInt8.self))
                    break;
                case "secondaryColor":
                    secondaryColor = Color(buffer: pointer.assumingMemoryBound(to: UInt8.self))
                    break;
                case "lowThreshold":
                    _lowThreshold = pointer.assumingMemoryBound(to: Float32.self)
                    break;
                case "highThreshold":
                    _highThreshold = pointer.assumingMemoryBound(to: Float32.self)
                    break;
                default:
                    print("Error: unknown parameter")
                    break;
                }
            }
        }
    }

    
    var primaryColor:Color! = nil
    var secondaryColor:Color! = nil
    
    var lowThreshold:Float32 {
        get {
            return _lowThreshold[0]
        }
        set {
            _lowThreshold[0] = newValue
        }
    }
    
    var highThreshold:Float32 {
        get {
            return _highThreshold[0]
        }
        set {
            _highThreshold[0] = newValue
        }
    }
}
