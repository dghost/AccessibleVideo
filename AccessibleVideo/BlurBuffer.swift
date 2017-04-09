//
//  BlurBuffer.swift
//  AccessibleVideo
//
//  Created by Luke Groeninger on 12/27/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//

class BlurBuffer:MetalBuffer {
    fileprivate var _params:UnsafeMutablePointer<BlurParameters>! = nil
    
    override func setContents(_ arguments: MTLArgument) {
        if arguments.name == "blurParameters" {
            assert(arguments.bufferDataSize == MemoryLayout<BlurParameters>.size)
            _params = _filterBufferData.assumingMemoryBound(to: BlurParameters.self)
        }
    }
    
    var xOffsets:(Offset, Offset, Offset) {
        get {
            return _params[0].xOffsets
        }
        set {
            _params[0].xOffsets = newValue
        }
    }
    
    var yOffsets:(Offset,Offset,Offset) {
        get {
            return _params[0].yOffsets
        }
        set {
            _params[0].yOffsets = newValue
        }
    }
}
