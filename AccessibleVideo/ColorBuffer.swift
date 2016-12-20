//
//  ColorBuffer.swift
//  AccessibleVideo
//
//  Created by Luke Groeninger on 12/27/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//


class ColorBuffer:MetalBuffer {
    var yuvToRGB:Matrix3x3! = nil
    
    override func setContents(_ arguments: MTLArgument) {
        if arguments.name == "colorParameters" {
            yuvToRGB = nil
            
            let parameters = arguments.bufferStructType.members as [MTLStructMember]
            for parameter in parameters {
                print("Found parameter \(parameter.name) at offset \(parameter.offset)")
                let pointer = _filterBufferData.advanced(by: parameter.offset)
                
                switch(parameter.name) {
                case "yuvToRGB":
                    yuvToRGB = Matrix3x3(buffer: pointer.assumingMemoryBound(to: Float32.self))
                    break;
                default:
                    print("Error: unknown parameter")
                    break;
                }
            }
        }
    }
    
    func setConvolution(_ newConvolution:[Float32]) {
        if newConvolution.count == 9 {
            yuvToRGB.set(
                (
                    (newConvolution[0], newConvolution[1], newConvolution[2]),
                    (newConvolution[3], newConvolution[4], newConvolution[5]),
                    (newConvolution[6], newConvolution[7], newConvolution[8])
                )
            )
        } else {
            yuvToRGB.clearIdentity()
        }
    }
}
