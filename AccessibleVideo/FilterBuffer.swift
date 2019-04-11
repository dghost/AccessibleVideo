//
//  FilterBuffer.swift
//  AccessibleVideo
//
//  Created by Luke Groeninger on 12/21/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//

class FilterBuffer:MetalBuffer {
    fileprivate var _params:UnsafeMutablePointer<FilterParameters>! = nil

    override func setContents(_ arguments: MTLArgument) {
        if arguments.name == "filterParameters" {
            assert(arguments.bufferDataSize == MemoryLayout<FilterParameters>.size)
            _params = _filterBufferData.assumingMemoryBound(to: FilterParameters.self)
        }
    }
    
    
    var primaryColor:float4 {
        get {
            return _params[0].primaryColor
        }
        set {
            _params[0].primaryColor = newValue
        }
    }
    
    var secondaryColor:float4 {
        get {
            return _params[0].secondaryColor
        }
        set {
            _params[0].secondaryColor = newValue
        }
    }
    
    var lowThreshold:Float32 {
        get {            
            return _params[0].lowThreshold
        }
        set {
            _params[0].lowThreshold = newValue
        }
    }
    
    var highThreshold:Float32 {
        get {
            return _params[0].highThreshold
        }
        set {
            _params[0].highThreshold = newValue
        }
    }
}
