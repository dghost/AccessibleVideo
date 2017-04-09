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
            primaryColor = nil
            secondaryColor = nil
            
            assert(arguments.bufferDataSize == MemoryLayout<FilterParameters>.size)
            _params = _filterBufferData.assumingMemoryBound(to: FilterParameters.self)
            
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
                    break;
                case "highThreshold":
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
