//
//  ColorBuffer.swift
//  AccessibleVideo
//
//  Created by Luke Groeninger on 12/27/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//


class ColorBuffer:MetalBuffer {
    fileprivate var _params:UnsafeMutablePointer<ColorParameters>! = nil
    
    override func setContents(_ arguments: MTLArgument) {
        if arguments.name == "colorParameters" {
            assert(arguments.bufferDataSize == MemoryLayout<ColorParameters>.size)
            _params = _filterBufferData.assumingMemoryBound(to: ColorParameters.self)
        }
    }
    
    func setConvolution(_ newConvolution:[Float32]) {
        
        if newConvolution.count == 9 {
            _params[0].yuvToRGB =
                (
                    (newConvolution[0], newConvolution[3], newConvolution[6], 0),
                    (newConvolution[1], newConvolution[4], newConvolution[7], 0),
                    (newConvolution[2], newConvolution[5], newConvolution[8], 0)
                )
         } else {
            _params[0].yuvToRGB =
                (
                    (1, 0, 0, 0),
                    (0, 1, 0, 0),
                    (0, 0, 1, 0)
            )
        }
    }
}
