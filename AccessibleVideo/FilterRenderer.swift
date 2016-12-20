//
//  FilterRenderer.swift
//  AccessibleVideo
//
//  Created by Luke Groeninger on 10/4/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//

import Foundation
import CoreVideo
import Metal
import AVFoundation
import UIKit

protocol RendererControlDelegate {
    var primaryColor:UIColor { get set }
    var secondaryColor:UIColor { get set }
    var invertScreen:Bool { get set }
    var applyBlur:Bool { get set }
    var highQuality:Bool { get }
}

class FilterRenderer: MetalViewDelegate, CameraCaptureDelegate, RendererControlDelegate {
    
    var device:MTLDevice! {
        return _device
    }
    
    
    var applyBlur:Bool = false
    
    var highQuality:Bool = false
    
    fileprivate var _controller:UIViewController! = nil
    
    lazy fileprivate var _device = MTLCreateSystemDefaultDevice()
    lazy fileprivate var _vertexStart = [UIInterfaceOrientation : Int]()

    fileprivate var _vertexBuffer:MTLBuffer! = nil
    fileprivate var _filterArgs:MetalBufferArray<FilterBuffer>! = nil
    fileprivate var _colorArgs:MetalBufferArray<ColorBuffer>! = nil
    fileprivate var _blurArgs:MetalBufferArray<BlurBuffer>! = nil
    
    fileprivate var _currentFilterBuffer:Int = 0 {
        didSet {
            _currentFilterBuffer = _currentFilterBuffer % _numberShaderBuffers
        }
    }
    
    fileprivate var _currentColorBuffer:Int = 0 {
        didSet {
            _currentColorBuffer = _currentColorBuffer % _numberShaderBuffers
        }
    }
    
    fileprivate var _currentBlurBuffer:Int = 0 {
        didSet {
            _currentBlurBuffer = _currentBlurBuffer % _numberShaderBuffers
        }
    }
    
    fileprivate var _blurPipelineStates = [MTLRenderPipelineState]()
    fileprivate var _screenBlitState:MTLRenderPipelineState! = nil
    fileprivate var _screenInvertState:MTLRenderPipelineState! = nil
    
    fileprivate var _commandQueue: MTLCommandQueue! = nil
    
    fileprivate var _intermediateTextures = [MTLTexture]()
    fileprivate var _intermediateRenderPassDescriptor = [MTLRenderPassDescriptor]()

    
    fileprivate var _rgbTexture:MTLTexture! = nil
    fileprivate var _rgbDescriptor:MTLRenderPassDescriptor! = nil
    fileprivate var _blurTexture:MTLTexture! = nil
    fileprivate var _blurDescriptor:MTLRenderPassDescriptor! = nil
    
    
    // ping/pong index variable
    fileprivate var _currentSourceTexture:Int = 0 {
        didSet {
            _currentSourceTexture = _currentSourceTexture % 2
        }
    }
    
    fileprivate var _currentDestTexture:Int {
        return (_currentSourceTexture + 1) % 2
    }
    
    fileprivate var _numberBufferedFrames:Int = 3
    fileprivate var _numberShaderBuffers:Int {
        return _numberBufferedFrames + 1
    }
    
    fileprivate var _renderSemaphore: DispatchSemaphore! = nil
    
    fileprivate var _textureCache: CVMetalTextureCache? = nil
    
    fileprivate var _vertexDesc: MTLVertexDescriptor! = nil
    
    fileprivate var _shaderLibrary: MTLLibrary! = nil
    fileprivate var _shaderDictionary: NSDictionary! = nil
    fileprivate var _shaderPipelineStates = [String : MTLRenderPipelineState]()

    fileprivate var _shaderArguments = [String : MTLRenderPipelineReflection]()
    
    fileprivate var _samplerStates = [MTLSamplerState]()
    
    fileprivate var _currentVideoFilterUsesBlur = true
    fileprivate var _currentVideoFilter = [MTLRenderPipelineState]()
    fileprivate var _currentColorFilter:MTLRenderPipelineState! = nil

    lazy fileprivate var _isiPad:Bool = (UIDevice.current.userInterfaceIdiom == .pad)
    
    fileprivate var _viewport:MTLViewport = MTLViewport()
    
    init(viewController:UIViewController!) {
        _controller = viewController
        setupRenderer()
    }
    
    func setupRenderer()
    {
        // load the shader dictionary
        let path = Bundle.main.path(forResource: "Shaders", ofType: "plist")
        _shaderDictionary = NSDictionary(contentsOfFile: path!)
        
        // create the render buffering semaphore
        _renderSemaphore = DispatchSemaphore(value: _numberBufferedFrames)
        
        // create texture caches for CoreVideo
        
        CVMetalTextureCacheCreate(nil, nil, _device!, nil, &_textureCache)
        
        // set up the full screen quads
        let data:[Float] =
        [   // landscape right & passthrough
            -1.0,  -1.0,  0.0, 1.0,
            1.0,  -1.0,  1.0, 1.0,
            -1.0,   1.0,  0.0, 0.0,
            1.0,  -1.0,  1.0, 1.0,
            -1.0,   1.0,  0.0, 0.0,
            1.0,   1.0,  1.0, 0.0,
            // landscape left
            -1.0,  -1.0,  1.0, 0.0,
            1.0,  -1.0,  0.0, 0.0,
            -1.0,   1.0,  1.0, 1.0,
            1.0,  -1.0,  0.0, 0.0,
            -1.0,   1.0,  1.0, 1.0,
            1.0,   1.0,  0.0, 1.0,
            // portrait
            -1.0,  -1.0,  1.0, 1.0,
            1.0,  -1.0,  1.0, 0.0,
            -1.0,   1.0,  0.0, 1.0,
            1.0,  -1.0,  1.0, 0.0,
            -1.0,   1.0,  0.0, 1.0,
            1.0,   1.0,  0.0, 0.0,
            // portrait upside down
            -1.0,  -1.0,  0.0, 0.0,
            1.0,  -1.0,  0.0, 1.0,
            -1.0,   1.0,  1.0, 0.0,
            1.0,  -1.0,  0.0, 1.0,
            -1.0,   1.0,  1.0, 0.0,
            1.0,   1.0,  1.0, 1.0]
        
        // set up vertex buffer
        let dataSize = data.count * MemoryLayout.size(ofValue: data[0]) // 1
        
        var options:MTLResourceOptions!
        
        if #available(iOS 9.0, *) {
            options = MTLResourceOptions().union(MTLResourceOptions())
        } else {
            // Fallback on earlier versions
            options = MTLResourceOptions()
        }
        
        _vertexBuffer = _device!.makeBuffer(bytes: data, length: dataSize, options: options)

        // set vertex indicies start for each rotation
        _vertexStart[.landscapeRight] = 0
        _vertexStart[.landscapeLeft] = 6
        _vertexStart[.portrait] = 12
        _vertexStart[.portraitUpsideDown] = 18
        
        // create default shader library
        _shaderLibrary = _device!.newDefaultLibrary()!
        print("Loading shader library...")
        for str in _shaderLibrary.functionNames {
            print("Found shader: \(str)")
        }
        
        // create the full screen quad vertex attribute descriptor
        let vert = MTLVertexAttributeDescriptor()
        vert.format = .float2
        vert.bufferIndex = 0
        vert.offset = 0
        
        let tex = MTLVertexAttributeDescriptor()
        tex.format = .float2
        tex.bufferIndex = 0
        tex.offset = 2 * MemoryLayout<Float>.size
        
        let layout = MTLVertexBufferLayoutDescriptor()
        layout.stride = 4 * MemoryLayout<Float>.size
        layout.stepFunction = MTLVertexStepFunction.perVertex
        
        
        _vertexDesc = MTLVertexDescriptor()
        
        _vertexDesc.layouts[0] = layout
        _vertexDesc.attributes[0] = vert
        _vertexDesc.attributes[1] = tex
        
        
        // create filter parameter buffer
        // create common pipeline states

        _currentColorFilter = cachedPipelineStateFor("yuv_rgb")

        _screenBlitState = cachedPipelineStateFor("blit")
        _screenInvertState = cachedPipelineStateFor("invert")

        var fragmentArgs = (_shaderArguments["blit"]!.fragmentArguments!).filter({$0.name == "filterParameters"})
        if fragmentArgs.count == 1 {
            _filterArgs = MetalBufferArray<FilterBuffer>(arguments: fragmentArgs[0], count: _numberShaderBuffers)
        }
    
        fragmentArgs = (_shaderArguments["yuv_rgb"]!.fragmentArguments!).filter({$0.name == "colorParameters"})
        if fragmentArgs.count == 1 {
            _colorArgs = MetalBufferArray<ColorBuffer>(arguments: fragmentArgs[0], count: _numberShaderBuffers)
        }
        
        if _device!.supportsFeatureSet(.iOS_GPUFamily2_v1) {
            print("Using high quality blur...")
            highQuality = true
            _blurPipelineStates = ["BlurX_HQ", "BlurY_HQ"].map {self.cachedPipelineStateFor($0)!}
            let fragmentArgs = (_shaderArguments["BlurX_HQ"]!.fragmentArguments!).filter({$0.name == "blurParameters"})
            if fragmentArgs.count == 1 {
                _blurArgs = MetalBufferArray<BlurBuffer>(arguments: fragmentArgs[0], count: _numberShaderBuffers)
            }
        } else {
            highQuality = false
            _blurPipelineStates = ["BlurX", "BlurY"].map {self.cachedPipelineStateFor($0)!}
            let fragmentArgs = (_shaderArguments["BlurX"]!.fragmentArguments!).filter({$0.name == "blurParameters"})
            if fragmentArgs.count == 1 {
                _blurArgs = MetalBufferArray<BlurBuffer>(arguments: fragmentArgs[0], count: _numberShaderBuffers)
            }
        }
        
        setFilterBuffer()
        
        
        let nearest = MTLSamplerDescriptor()
        nearest.label = "nearest"
        
        let bilinear = MTLSamplerDescriptor()
        bilinear.label = "bilinear"
        bilinear.minFilter = .linear
        bilinear.magFilter = .linear
        _samplerStates = [nearest, bilinear].map {self._device!.makeSamplerState(descriptor: $0)}


        
        // create the command queue
        _commandQueue = _device!.makeCommandQueue()
    }
    
    // create a pipeline state descriptor for a vertex/fragment shader combo
    func pipelineStateFor(label:String!, fragmentShader:String!, vertexShader: String?) -> (MTLRenderPipelineState?, MTLRenderPipelineReflection?) {
        if let fragmentProgram = _shaderLibrary.makeFunction(name: fragmentShader), let vertexProgram = _shaderLibrary.makeFunction(name: vertexShader ?? "defaultVertex") {
            let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
            pipelineStateDescriptor.label = label
            pipelineStateDescriptor.vertexFunction = vertexProgram
            pipelineStateDescriptor.fragmentFunction = fragmentProgram
            
            pipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            pipelineStateDescriptor.vertexDescriptor = _vertexDesc
            
            // create the actual pipeline state
            var info:MTLRenderPipelineReflection? = nil
            
            do {
                let pipelineState = try _device!.makeRenderPipelineState(descriptor: pipelineStateDescriptor, options: MTLPipelineOption.bufferTypeInfo, reflection: &info)
                return (pipelineState, info)
            } catch let pipelineError as NSError {
                print("Failed to create pipeline state for shaders \(vertexShader):\(fragmentShader) error \(pipelineError)")
            }
        }
        return (nil, nil)
    }
    
    func cachedPipelineStateFor(_ shaderName:String) -> MTLRenderPipelineState? {
        guard let pipeline = _shaderPipelineStates[shaderName] else {
            
            var fragment:String! = shaderName
            var vertex:String? = nil
            
            if let s = _shaderDictionary.object(forKey: shaderName) as? NSDictionary {
                vertex = s.object(forKey: "vertex") as? String
                if let frag:String = s.object(forKey: "fragment") as? String {
                    fragment = frag
                }
            }
            
            let (state, reflector) = pipelineStateFor(label:shaderName, fragmentShader: fragment, vertexShader: vertex)
            if let pipelineState = state
            {
                _shaderPipelineStates[shaderName] = pipelineState
                _shaderArguments[shaderName] = reflector
            } else {
                print("Fatal error trying to load pipeline state for \(shaderName)")
            }
            return state
                
        }
        return pipeline
    }
    
    // create generic render pass
    func createRenderPass(_ commandBuffer: MTLCommandBuffer!,
        pipeline:MTLRenderPipelineState!,
        vertexIndex:Int, fragmentBuffers:[(MTLBuffer,Int)],
        sourceTextures:[MTLTexture],
        descriptor: MTLRenderPassDescriptor!,
        viewport:MTLViewport?) {
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
            
            let name:String = pipeline.label ?? "Unnamed Render Pass"
            renderEncoder.pushDebugGroup(name)
            renderEncoder.label = name
            if let view = viewport {
                renderEncoder.setViewport(view)
            }
            renderEncoder.setRenderPipelineState(pipeline)
            
            renderEncoder.setVertexBuffer(_vertexBuffer, offset: 0, at: 0)
            
            for (index,(buffer, offset)) in fragmentBuffers.enumerated() {
                renderEncoder.setFragmentBuffer(buffer, offset: offset, at: index)
            }
            for (index,texture) in sourceTextures.enumerated() {
                renderEncoder.setFragmentTexture(texture, at: index)
            }
            for (index,samplerState) in _samplerStates.enumerated() {
                renderEncoder.setFragmentSamplerState(samplerState, at: index)
            }
            
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: vertexIndex, vertexCount: 6, instanceCount: 1)
            renderEncoder.popDebugGroup()
            renderEncoder.endEncoding()
    }

    func render(_ view: MetalView) {

        let currentOrientation:UIInterfaceOrientation = _isiPad ? UIApplication.shared.statusBarOrientation : .portrait
        
        guard let currentOffset = _vertexStart[currentOrientation], _rgbTexture != nil else {
            return
        }
        
        _renderSemaphore.wait(timeout: DispatchTime.distantFuture)

        let commandBuffer = _commandQueue.makeCommandBuffer()

        var sourceTexture:MTLTexture = _rgbTexture
        var destDescriptor:MTLRenderPassDescriptor = _intermediateRenderPassDescriptor[_currentDestTexture]
        
        func swapTextures() {
            self._currentSourceTexture += 1
            sourceTexture = self._intermediateTextures[self._currentSourceTexture]
            destDescriptor = self._intermediateRenderPassDescriptor[self._currentDestTexture]
        }
        
        var blurTex = _rgbTexture
        
        if applyBlur && _currentVideoFilterUsesBlur, let args = _blurArgs {
            let parameters = [args.bufferAndOffsetForElement(_currentBlurBuffer)]
            createRenderPass(commandBuffer,
                pipeline:  _blurPipelineStates[0],
                vertexIndex: 0,
                fragmentBuffers: parameters,
                sourceTextures: [_rgbTexture],
                descriptor: _intermediateRenderPassDescriptor[0],
                viewport: nil)
            
            createRenderPass(commandBuffer,
                pipeline:  _blurPipelineStates[1],
                vertexIndex: 0,
                fragmentBuffers: parameters,
                sourceTextures: [_intermediateTextures[0]],
                descriptor: _blurDescriptor,
                viewport: nil)
            blurTex = _blurTexture
        }
        
        
        // apply all render passes in the current filter
        let filterParameters = [_filterArgs.bufferAndOffsetForElement(_currentFilterBuffer)]
        for (_, filter) in _currentVideoFilter.enumerated() {
            createRenderPass(commandBuffer,
                pipeline: filter,
                vertexIndex: 0,
                fragmentBuffers: filterParameters,
                sourceTextures: [sourceTexture, blurTex!, _rgbTexture],
                descriptor: destDescriptor,
                viewport: nil)
            
            swapTextures()
        }
        
        
        if let screenDescriptor = view.renderPassDescriptor {
            
            createRenderPass(commandBuffer,
                pipeline: invertScreen ? _screenInvertState! : _screenBlitState!,
                vertexIndex: currentOffset,
                fragmentBuffers: filterParameters,
                sourceTextures: [sourceTexture, blurTex!, _rgbTexture],
                descriptor: screenDescriptor,
                viewport: self._viewport)
            
            swapTextures()
            
        }

        // commit buffers to GPU
        commandBuffer.addCompletedHandler() {
            (cmdb:MTLCommandBuffer!) in
            self._renderSemaphore.signal()
            return
        }
        
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
    }
    
    func resize(_ size: CGSize) {
        if _rgbTexture != nil {
            let iWidth = Double(_rgbTexture.width)
            let iHeight = Double(_rgbTexture.height)
            let aspect = iHeight / iWidth
            
            
            if size.width > size.height {
                let newHeight = Double(size.width) * aspect
                let diff = (Double(size.height) - newHeight) * 0.5
                _viewport = MTLViewport(originX: 0.0, originY: diff, width: Double(size.width), height: newHeight, znear: 0.0, zfar: 1.0)
            } else {
                let newHeight = Double(size.height) * aspect
                let diff = (Double(size.width) - newHeight) * 0.5
                _viewport = MTLViewport(originX: diff, originY: 0.0, width: newHeight, height: Double(size.height), znear: 0.0, zfar: 1.0)
            }
            
            if _viewport.originX < 0.0 {
                _viewport.originX = 0.0
            }
            if _viewport.originY < 0.0 {
                _viewport.originY = 0.0
            }
            
            if _viewport.width > Double(size.width) {
                _viewport.width = Double(size.width)
            }
            
            if _viewport.height > Double(size.height) {
                _viewport.height = Double(size.height)
            }

        }
    }
    
    func setVideoFilter(_ filter:VideoFilter)
    {
        _currentVideoFilter = filter.passes.map {self.cachedPipelineStateFor($0)!}
        _currentVideoFilterUsesBlur = filter.canBlur
    }
    
    func setColorFilter(_ filter:InputFilter) {

        guard let shader = cachedPipelineStateFor(filter.shaderName) else {
            print("Fatal error: could not set color filter to \(filter.shaderName)")
            return
        }
        
        let nextBuffer = (_currentColorBuffer + 1) % _numberShaderBuffers

        _currentColorFilter = shader
        
        _colorArgs[nextBuffer].setConvolution(filter.convolution)
        _currentColorBuffer += 1
    }

    func setResolution(width: Int, height: Int) {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        
        let scale = UIScreen.main.nativeScale
  
        var textureWidth = Int(_controller.view.bounds.width * scale)
        var textureHeight = Int(_controller.view.bounds.height * scale)
        
        if (textureHeight > textureWidth) {
            let temp = textureHeight
            textureHeight = textureWidth
            textureWidth = temp
        }
        
        if ((textureHeight > height) || (textureWidth > width)) {
            textureHeight = height
            textureWidth = width
        }
        
        print("Setting offscreen texure resolution to \(textureWidth)x\(textureHeight)")
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: textureWidth, height: textureHeight, mipmapped: false)
        
        if #available(iOS 9.0, *) {
            descriptor.resourceOptions = .storageModePrivate
            descriptor.storageMode = .private
            descriptor.usage = [.renderTarget, .shaderRead]
        }
        
        
        _intermediateTextures = [descriptor,descriptor].map { self._device!.makeTexture(descriptor: $0) }
        _intermediateRenderPassDescriptor = _intermediateTextures.map {
            let renderDescriptor = MTLRenderPassDescriptor()
            renderDescriptor.colorAttachments[0].texture = $0
            renderDescriptor.colorAttachments[0].loadAction = .dontCare
            renderDescriptor.colorAttachments[0].storeAction = .store
            return renderDescriptor
        }
        
        _rgbTexture = _device!.makeTexture(descriptor: descriptor)
        _rgbDescriptor = MTLRenderPassDescriptor()
        _rgbDescriptor.colorAttachments[0].texture = _rgbTexture
        _rgbDescriptor.colorAttachments[0].loadAction = .dontCare
        _rgbDescriptor.colorAttachments[0].storeAction = .store
        
        _blurTexture = _device!.makeTexture(descriptor: descriptor)
        _blurDescriptor = MTLRenderPassDescriptor()
        _blurDescriptor.colorAttachments[0].texture = _blurTexture
        _blurDescriptor.colorAttachments[0].loadAction = .dontCare
        _blurDescriptor.colorAttachments[0].storeAction = .store
        
        setBlurBuffer()
    }
    
    
    func captureBuffer(_ sampleBuffer: CMSampleBuffer!) {
        if _rgbDescriptor != nil, let tc = _textureCache, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            
            var y_texture: CVMetalTexture? = nil
            let y_width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let y_height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, tc, pixelBuffer, nil, MTLPixelFormat.r8Unorm, y_width, y_height, 0, &y_texture)
            
            var uv_texture: CVMetalTexture? = nil
            let uv_width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
            let uv_height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, tc, pixelBuffer, nil, MTLPixelFormat.rg8Unorm, uv_width, uv_height, 1, &uv_texture)
            
            let luma = CVMetalTextureGetTexture(y_texture!)!
            let chroma = CVMetalTextureGetTexture(uv_texture!)!
            
            let yuvTextures:[MTLTexture] = [ luma, chroma ]
            
            let commandBuffer = _commandQueue.makeCommandBuffer()

            // create the YUV->RGB pass
            createRenderPass(commandBuffer,
                pipeline: _currentColorFilter,
                vertexIndex: 0,
                fragmentBuffers: [_colorArgs.bufferAndOffsetForElement(_currentColorBuffer)],
                sourceTextures: yuvTextures,
                descriptor: _rgbDescriptor,
                viewport: nil)
            
            commandBuffer.commit()

            CVMetalTextureCacheFlush(tc, 0)
        }
    }
    
    func setBlurBuffer() {
        //
        // Texel offset generation for linear sampled gaussian blur
        // Source: http://rastergrid.com/blog/2010/09/efficient-gaussian-blur-with-linear-sampling/
        //
        
        let nextBuffer = (_currentBlurBuffer + 1) % _numberShaderBuffers
        
        guard let currentBuffer = _blurArgs?[nextBuffer] else {
            return
        }
        
        let offsets:[Float32] = [ 0.0, 1.3846153846, 3.2307692308 ]
        
        let texelWidth = 1.0 / Float32(_rgbTexture.width)
        let texelHeight = 1.0 / Float32(_rgbTexture.height)
        
        currentBuffer.xOffsets = (
            (offsets[0] * texelWidth, 0),
            (offsets[1] * texelWidth, 0),
            (offsets[2] * texelWidth, 0)
        )
        
        currentBuffer.yOffsets = (
            (0, offsets[0] * texelHeight),
            (0, offsets[1] * texelHeight),
            (0, offsets[2] * texelHeight)
        )
        _currentBlurBuffer += 1
    }
    
    func setFilterBuffer() {
        let nextBuffer = (_currentFilterBuffer + 1) % _numberShaderBuffers
        _currentFilterBuffer += 1

        let currentBuffer = _filterArgs[nextBuffer]
        if invertScreen {
            currentBuffer.primaryColor?.inverseColor = primaryColor
            currentBuffer.secondaryColor?.inverseColor = secondaryColor
        } else {
            currentBuffer.primaryColor?.color = primaryColor
            currentBuffer.secondaryColor?.color = secondaryColor
        }
        
        if highQuality {
            currentBuffer.lowThreshold = 0.05
            currentBuffer.highThreshold = 0.10
        } else {
            currentBuffer.lowThreshold = 0.15
            currentBuffer.highThreshold = 0.25
        }
    }
    
    var primaryColor:UIColor = UIColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 0.75) {
        didSet {
            setFilterBuffer()
        }
    }
    
    var secondaryColor:UIColor = UIColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 0.75){
        didSet {
            setFilterBuffer()
        }
    }
    
    var invertScreen:Bool = false {
        didSet {
            setFilterBuffer()
        }
    }

}
