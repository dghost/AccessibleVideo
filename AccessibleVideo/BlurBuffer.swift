//
//  BlurBuffer.swift
//  AccessibleVideo
//
//  Created by Luke Groeninger on 12/27/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//


class BlurBuffer:MetalBuffer {

    private var _x:UnsafeMutablePointer<Float32> = nil
    private var _y:UnsafeMutablePointer<Float32> = nil
    
    override func setContents(arguments: MTLArgument) {
        if arguments.name == "blurParameters" {
            _x = nil
            _y = nil
            
            let parameters = arguments.bufferStructType?.members as! [MTLStructMember]
            for parameter in parameters {
                println("Found parameter \(parameter.name) at offset \(parameter.offset)")
                
                switch(parameter.name) {
                case "xOffsets":
                    let pointer = UnsafeMutablePointer<Float32>(_filterBufferData + parameter.offset)
                    _x = pointer
                    break;
                case "yOffsets":
                    let pointer = UnsafeMutablePointer<Float32>(_filterBufferData + parameter.offset)
                    _y = pointer
                    break;
                default:
                    println("Error: unknown parameter")
                    break;
                }
            }
        }
    }
    
    var xOffsets:((Float32,Float32),(Float32,Float32),(Float32,Float32)) {
        get {
            return ((_x[0],_x[1]),(_x[2],_x[3]),(_x[4],_x[5]))
        }
        set {
            _x[0] = newValue.0.0
            _x[1] = newValue.0.1
            _x[2] = newValue.1.0
            _x[3] = newValue.1.1
            _x[4] = newValue.2.0
            _x[5] = newValue.2.1
        }
    }
    
    var yOffsets:((Float32,Float32),(Float32,Float32),(Float32,Float32)) {
        get {
            return ((_y[0],_y[1]),(_y[2],_y[3]),(_y[4],_y[5]))
        }
        set {
            _y[0] = newValue.0.0
            _y[1] = newValue.0.1
            _y[2] = newValue.1.0
            _y[3] = newValue.1.1
            _y[4] = newValue.2.0
            _y[5] = newValue.2.1
        }
    }
}