//
//  FilterBuffer.swift
//  AccessibleVideo
//
//  Created by Luke Groeninger on 12/21/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//

class FilterBuffer:MetalBuffer {
    private var _lowThreshold:UnsafeMutablePointer<Float32> = nil
    private var _highThreshold:UnsafeMutablePointer<Float32> = nil
    
    override func setContents(arguments: MTLArgument) {
        if arguments.name == "filterParameters" {
            primaryColor = nil
            secondaryColor = nil
            _lowThreshold = nil
            _highThreshold = nil
            
            let parameters = arguments.bufferStructType?.members as [MTLStructMember]
            for parameter in parameters {
                println("Found parameter \(parameter.name) at offset \(parameter.offset)")
                
                switch(parameter.name) {
                case "primaryColor":
                    let pointer = UnsafeMutablePointer<UInt8>(_filterBufferData + parameter.offset)
                    primaryColor = Color(buffer: pointer)
                    break;
                case "secondaryColor":
                    let pointer = UnsafeMutablePointer<UInt8>(_filterBufferData + parameter.offset)
                    secondaryColor = Color(buffer: pointer)
                    break;
                case "lowThreshold":
                    let pointer = UnsafeMutablePointer<Float32>(_filterBufferData + parameter.offset)
                    _lowThreshold = pointer
                    break;
                case "highThreshold":
                    let pointer = UnsafeMutablePointer<Float32>(_filterBufferData + parameter.offset)
                    _highThreshold = pointer
                    break;
                default:
                    println("Error: unknown parameter")
                    break;
                }
            }
        }
    }

    
    var primaryColor:Color? = nil
    var secondaryColor:Color? = nil
    
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