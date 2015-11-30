//
//  BufferTypes.swift
//  AccessibleVideo
//
//  Created by Luke Groeninger on 12/27/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//



class MetalBuffer {
    let buffer:MTLBuffer?
    internal let _filterBufferData:UnsafePointer<Void>
    internal let _filterBufferSize:Int
    
    init!(arguments:MTLArgument) {
        let size = arguments.bufferDataSize
        let dev = MTLCreateSystemDefaultDevice()
        
        var options:MTLResourceOptions!
        
        if #available(iOS 9.0, *) {
            options = MTLResourceOptions.StorageModeShared.union(MTLResourceOptions.CPUCacheModeDefaultCache)
        } else {
            // Fallback on earlier versions
            options = MTLResourceOptions.CPUCacheModeDefaultCache
        }

        buffer = dev!.newBufferWithLength(size, options: options)
        _filterBufferData = UnsafePointer<Void>(buffer!.contents())
        _filterBufferSize = size
        setContents(arguments)
    }
    
    required init!(base:UnsafePointer<Void>, size:Int, arguments:MTLArgument) {
        if base != nil {
            buffer = nil
            _filterBufferData = base
            _filterBufferSize = size
            setContents(arguments)
        } else {
            buffer = nil
            _filterBufferData = nil
            _filterBufferSize = 0
            return nil
        }
    }
    
    func setContents(arguments: MTLArgument) {
        assert(false, "This should not be getting called!")
    }
}

class MetalBufferArray<T:MetalBuffer> {
    let buffer:MTLBuffer?
    internal let _filterBufferData:UnsafePointer<Void>
    internal let _filterBufferSize:Int
    lazy internal var _members = [T]()
    
    init!(arguments:MTLArgument, count:Int){
        let size = arguments.bufferDataSize
        let dev = MTLCreateSystemDefaultDevice()
        
        var options:MTLResourceOptions!
        
        if #available(iOS 9.0, *) {
            options = MTLResourceOptions.StorageModeShared.union(MTLResourceOptions.CPUCacheModeDefaultCache)
        } else {
            // Fallback on earlier versions
            options = MTLResourceOptions.CPUCacheModeDefaultCache
        }
        
        buffer = dev!.newBufferWithLength(size * count, options: options)
        _filterBufferData = UnsafePointer<Void>(buffer!.contents())
        _filterBufferSize = size
        _members = (0..<count).map {
            (T.self as T.Type).init(base: self._filterBufferData + size * $0, size: size, arguments: arguments)!
        }
        
    }
    
    subscript (element:Int) -> T {
        get {
            assert(element >= 0 && element < _members.count , "Index out of range")
            return _members[element]
        }
    }

    func bufferAndOffsetForElement(element:Int) -> (MTLBuffer, Int){
        assert(element >= 0 && element < _members.count , "Index out of range")
        return (buffer!,_filterBufferSize * element)
    }
    
    func offsetForElement(element:Int) -> Int {
        assert(element >= 0 && element < _members.count , "Index out of range")
        return _filterBufferSize * element
    }
    
    var count:Int {
        return _members.count
    }
}

// type takes in a UIColor or CGFloats and writes them out as an
// 8-bit per channel RGBA vector
struct Color {
    private let _base:UnsafeMutablePointer<UInt8>
    init(buffer:UnsafeMutablePointer<UInt8>) {
        _base = buffer
    }
    
    var color:UIColor {
        get {
            return UIColor(red: r, green: g, blue: b, alpha: a)
        }
        set {
            newValue.getRed(&r, green: &g, blue: &b, alpha: &a)
        }
    }
    
    var inverseColor:UIColor {
        get {
            return UIColor(red: 1.0 - r, green: 1.0 - g, blue: 1.0 - b, alpha: a)
        }
        set {
            var rt:CGFloat = 0.0, gt:CGFloat = 0.0, bt:CGFloat = 0.0
            newValue.getRed(&rt, green: &gt, blue: &bt, alpha: &self.a)
            self.r = 1.0 - rt
            self.g = 1.0 - gt
            self.b = 1.0 - bt
        }
    }
    
    var r:CGFloat {
        get {
            return CGFloat(Float(_base[0]) / 255.0)
        }
        set {
            let clamped = newValue < 0.0 ? 0.0 : (newValue > 1.0 ? 1.0 : newValue)
            _base[0] = UInt8(clamped * 255.0)
        }
    }
    var g:CGFloat {
        get {
            return CGFloat(Float(_base[1]) / 255.0)
        }
        set {
            let clamped = newValue < 0.0 ? 0.0 : (newValue > 1.0 ? 1.0 : newValue)
            _base[1] = UInt8(clamped * 255.0)
        }
    }
    var b:CGFloat {
        get {
            return CGFloat(Float(_base[2]) / 255.0)
        }
        set {
            let clamped = newValue < 0.0 ? 0.0 : (newValue > 1.0 ? 1.0 : newValue)
            _base[2] = UInt8(clamped * 255.0)
        }
    }
    var a:CGFloat {
        get {
            return CGFloat(Float(_base[3]) / 255.0)
        }
        set {
            let clamped = newValue < 0.0 ? 0.0 : (newValue > 1.0 ? 1.0 : newValue)
            _base[3] = UInt8(clamped * 255.0)
        }
    }
}


// type takes in a row-major matrix and writes it so that
// it is a column-major matrix where each column is aligned on
// 4 byte boundaries
struct Matrix3x3 {
    private let _base:UnsafeMutablePointer<Float32>
    init(buffer:UnsafeMutablePointer<Float32>) {
        _base = buffer
    }
    
    private func indexIsValidForRow(row: Int, column: Int) -> Bool {
        return row >= 0 && row < 3 && column >= 0 && column < 3
    }
    
    subscript(row:Int, column:Int) -> Float32 {
        get {
            assert(indexIsValidForRow(row, column: column), "Index out of range")
            // convert to column-major order
            return _base[(column * 4) + row]
        }
        set {
            assert(indexIsValidForRow(row, column: column), "Index out of range")
            // convert to column-major order
            _base[(column * 4) + row] = newValue
        }
    }
    
    subscript(row:Int) -> (Float32, Float32, Float32) {
        get {
            assert(row >= 0 && row < 3, "Index out of range")
            // convert to column-major order
            return (_base[row], _base[row + 4], _base[row + 8])
        }
        set {
            assert(row >= 0 && row < 3 , "Index out of range")
            // convert to column-major order
            _base[row] = newValue.0
            _base[row + 4] = newValue.1
            _base[row + 8] = newValue.2
        }
    }
    
    func set(matrix:((Float32, Float32, Float32), (Float32, Float32, Float32), (Float32, Float32, Float32))) {
        // converts to column-major order
        // aligns each column to 4-byte boundaries
        _base[0] = matrix.0.0
        _base[4] = matrix.0.1
        _base[8] = matrix.0.2
        _base[1] = matrix.1.0
        _base[5] = matrix.1.1
        _base[9] = matrix.1.2
        _base[2] = matrix.2.0
        _base[6] = matrix.2.1
        _base[10] = matrix.2.2
    }
    
    func clear() {
        for index in 0...15 {
            _base[index] = 0.0
        }
    }
    
    func clearIdentity() {
        for index in 0...15 {
            _base[index] = (index % 4 == 0) ? 1.0 : 0.0
        }
    }
}