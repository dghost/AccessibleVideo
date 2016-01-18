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
    
    private var _controller:UIViewController! = nil
    
    lazy private var _device = MTLCreateSystemDefaultDevice()
    lazy private var _vertexStart = [UIInterfaceOrientation : Int]()

    private var _vertexBuffer:MTLBuffer! = nil
    private var _filterArgs:MetalBufferArray<FilterBuffer>! = nil
    private var _colorArgs:MetalBufferArray<ColorBuffer>! = nil
    private var _blurArgs:MetalBufferArray<BlurBuffer>? = nil
    
    private var _currentFilterBuffer:Int = 0 {
        didSet {
            _currentFilterBuffer = _currentFilterBuffer % _numberShaderBuffers
        }
    }
    
    private var _currentColorBuffer:Int = 0 {
        didSet {
            _currentColorBuffer = _currentColorBuffer % _numberShaderBuffers
        }
    }
    
    private var _currentBlurBuffer:Int = 0 {
        didSet {
            _currentBlurBuffer = _currentBlurBuffer % _numberShaderBuffers
        }
    }
    
    private var _blurPipelineStates = [MTLRenderPipelineState]()
    private var _screenBlitState:MTLRenderPipelineState! = nil
    private var _screenInvertState:MTLRenderPipelineState! = nil
    
    private var _commandQueue: MTLCommandQueue! = nil
    
    private var _intermediateTextures = [MTLTexture]()
    private var _intermediateRenderPassDescriptor = [MTLRenderPassDescriptor]()

    
    private var _rgbTexture:MTLTexture! = nil
    private var _rgbDescriptor:MTLRenderPassDescriptor! = nil
    private var _blurTexture:MTLTexture! = nil
    private var _blurDescriptor:MTLRenderPassDescriptor! = nil
    
    
    // ping/pong index variable
    private var _currentSourceTexture:Int = 0 {
        didSet {
            _currentSourceTexture = _currentSourceTexture % 2
        }
    }
    
    private var _currentDestTexture:Int {
        return (_currentSourceTexture + 1) % 2
    }
    
    private var _numberBufferedFrames:Int = 2
    private var _numberShaderBuffers:Int {
        return _numberBufferedFrames + 1
    }
    
    private var _renderSemaphore: dispatch_semaphore_t! = nil
    
    private var _unmanagedTextureCache: Unmanaged<CVMetalTextureCache>?
    private var _textureCache: CVMetalTextureCache! = nil
    
    private var _vertexDesc: MTLVertexDescriptor! = nil
    
    private var _shaderLibrary: MTLLibrary! = nil
    private var _shaderDictionary: NSDictionary! = nil
    private var _shaderPipelineStates = [String : MTLRenderPipelineState]()

    private var _shaderArguments = [String : MTLRenderPipelineReflection]()
    
    private var _samplerStates = [MTLSamplerState]()
    
    private var _currentVideoFilterUsesBlur = true
    private var _currentVideoFilter = [MTLRenderPipelineState]()
    private var _currentColorFilter:MTLRenderPipelineState! = nil
    private var _currentColorConvolution:[Float32] = [] {
        didSet {
            setColorBuffer()
        }
    }
    
    lazy private var _isiPad:Bool = (UIDevice.currentDevice().userInterfaceIdiom == .Pad)
    
    private var _viewport:MTLViewport? = nil
    
    init(viewController:UIViewController!) {
        _controller = viewController
        setupRenderer()
    }
    
    func setupRenderer()
    {
        // load the shader dictionary
        let path = NSBundle.mainBundle().pathForResource("Shaders", ofType: "plist")
        _shaderDictionary = NSDictionary(contentsOfFile: path!)
        
        // create the render buffering semaphore
        _renderSemaphore = dispatch_semaphore_create(_numberBufferedFrames)
        
        // create texture caches for CoreVideo
        CVMetalTextureCacheCreate(nil, nil, _device!, nil, &_unmanagedTextureCache)
        _textureCache = _unmanagedTextureCache!.takeUnretainedValue()
        
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
        let dataSize = data.count * sizeofValue(data[0]) // 1
        
        var options:MTLResourceOptions!
        
        if #available(iOS 9.0, *) {
            options = MTLResourceOptions.StorageModeShared.union(MTLResourceOptions.CPUCacheModeDefaultCache)
        } else {
            // Fallback on earlier versions
            options = MTLResourceOptions.CPUCacheModeDefaultCache
        }
        
        _vertexBuffer = _device!.newBufferWithBytes(data, length: dataSize, options: options)

        // set vertex indicies start for each rotation
        _vertexStart[.LandscapeRight] = 0
        _vertexStart[.LandscapeLeft] = 6
        _vertexStart[.Portrait] = 12
        _vertexStart[.PortraitUpsideDown] = 18
        
        // create default shader library
        _shaderLibrary = _device!.newDefaultLibrary()!
        print("Loading shader library...")
        for str in _shaderLibrary.functionNames {
            print("Found shader: \(str)")
        }
        
        // create the full screen quad vertex attribute descriptor
        let vert = MTLVertexAttributeDescriptor()
        vert.format = .Float2
        vert.bufferIndex = 0
        vert.offset = 0
        
        let tex = MTLVertexAttributeDescriptor()
        tex.format = .Float2
        tex.bufferIndex = 0
        tex.offset = 2 * sizeof(Float)
        
        let layout = MTLVertexBufferLayoutDescriptor()
        layout.stride = 4 * sizeof(Float)
        layout.stepFunction = MTLVertexStepFunction.PerVertex
        
        
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
        bilinear.minFilter = .Linear
        bilinear.magFilter = .Linear
        _samplerStates = [nearest, bilinear].map {self._device!.newSamplerStateWithDescriptor($0)}


        
        // create the command queue
        _commandQueue = _device!.newCommandQueue()
    }
    
    // create a pipeline state descriptor for a vertex/fragment shader combo
    func pipelineStateFor(label label:String!, fragmentShader:String!, vertexShader: String?) -> (MTLRenderPipelineState?, MTLRenderPipelineReflection?) {
        if let fragmentProgram = _shaderLibrary.newFunctionWithName(fragmentShader), let vertexProgram = _shaderLibrary.newFunctionWithName(vertexShader ?? "defaultVertex") {
            let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
            pipelineStateDescriptor.label = label
            pipelineStateDescriptor.vertexFunction = vertexProgram
            pipelineStateDescriptor.fragmentFunction = fragmentProgram
            
            pipelineStateDescriptor.colorAttachments[0].pixelFormat = .BGRA8Unorm
            
            pipelineStateDescriptor.vertexDescriptor = _vertexDesc
            
            // create the actual pipeline state
            var info:MTLRenderPipelineReflection? = nil
            
            do {
                let pipelineState = try _device!.newRenderPipelineStateWithDescriptor(pipelineStateDescriptor, options: MTLPipelineOption.BufferTypeInfo, reflection: &info)
                return (pipelineState, info)
            } catch let pipelineError as NSError {
                print("Failed to create pipeline state for shaders \(vertexShader):\(fragmentShader) error \(pipelineError)")
            }
        }
        return (nil, nil)
    }
    
    func cachedPipelineStateFor(shaderName:String) -> MTLRenderPipelineState? {
        guard let pipeline = _shaderPipelineStates[shaderName] else {
            
            var fragment:String! = shaderName
            var vertex:String? = nil
            
            if let s = _shaderDictionary.objectForKey(shaderName) as? NSDictionary {
                vertex = s.objectForKey("vertex") as? String
                if let frag:String = s.objectForKey("fragment") as? String {
                    fragment = frag
                }
            }
            
            let (state, reflector) = pipelineStateFor(label:shaderName, fragmentShader: fragment, vertexShader: vertex)
            _shaderPipelineStates[shaderName] = state
            _shaderArguments[shaderName] = reflector
            return state
        }
        return pipeline
    }
    
    // create generic render pass
    func createRenderPass(commandBuffer: MTLCommandBuffer!,
        pipeline:MTLRenderPipelineState!,
        vertexIndex:Int, fragmentBuffers:[(MTLBuffer,Int)],
        sourceTextures:[MTLTexture],
        descriptor: MTLRenderPassDescriptor!,
        viewport:MTLViewport?) {
            let renderEncoder = commandBuffer.renderCommandEncoderWithDescriptor(descriptor)
            
            let name:String = pipeline.label ?? "Unnamed Render Pass"
            renderEncoder.pushDebugGroup(name)
            renderEncoder.label = name
            if let view = viewport {
                renderEncoder.setViewport(view)
            }
            renderEncoder.setRenderPipelineState(pipeline)
            
            renderEncoder.setVertexBuffer(_vertexBuffer, offset: 0, atIndex: 0)
            
            for (index,(buffer, offset)) in fragmentBuffers.enumerate() {
                renderEncoder.setFragmentBuffer(buffer, offset: offset, atIndex: index)
            }
            for (index,texture) in sourceTextures.enumerate() {
                renderEncoder.setFragmentTexture(texture, atIndex: index)
            }
            for (index,samplerState) in _samplerStates.enumerate() {
                renderEncoder.setFragmentSamplerState(samplerState, atIndex: index)
            }
            
            renderEncoder.drawPrimitives(.Triangle, vertexStart: vertexIndex, vertexCount: 6, instanceCount: 1)
            renderEncoder.popDebugGroup()
            renderEncoder.endEncoding()
    }

    func render(view: MetalView) {

        let currentOrientation:UIInterfaceOrientation = _isiPad ? UIApplication.sharedApplication().statusBarOrientation : .Portrait
        
        guard let currentOffset = _vertexStart[currentOrientation] where _rgbTexture != nil else {
            return
        }
        
        let commandBuffer = _commandQueue.commandBuffer()

        dispatch_semaphore_wait(_renderSemaphore, DISPATCH_TIME_FOREVER)
        // get the command buffer
        commandBuffer.enqueue()
        defer {
            // commit buffers to GPU
            commandBuffer.addCompletedHandler() {
            (cmdb:MTLCommandBuffer!) in
            dispatch_semaphore_signal(self._renderSemaphore)
            return
            }
            
            commandBuffer.presentDrawable(view.currentDrawable!)
            commandBuffer.commit()
        }
        
        
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
        for (_, filter) in _currentVideoFilter.enumerate() {
            createRenderPass(commandBuffer,
                pipeline: filter,
                vertexIndex: 0,
                fragmentBuffers: filterParameters,
                sourceTextures: [sourceTexture, blurTex, _rgbTexture],
                descriptor: destDescriptor,
                viewport: nil)
            
            swapTextures()
        }
        
        
        if let screenDescriptor = view.renderPassDescriptor {
            
            createRenderPass(commandBuffer,
                pipeline: invertScreen ? _screenInvertState! : _screenBlitState!,
                vertexIndex: currentOffset,
                fragmentBuffers: filterParameters,
                sourceTextures: [sourceTexture, blurTex, _rgbTexture],
                descriptor: screenDescriptor,
                viewport: self._viewport)
            
            swapTextures()
            
        }

        
    }
    
    func resize(size: CGSize) {
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
            
            if _viewport?.originX < 0.0 {
                _viewport?.originX = 0.0
            }
            if _viewport?.originY < 0.0 {
                _viewport?.originY = 0.0
            }
            
            if _viewport?.width > Double(size.width) {
                _viewport?.width = Double(size.width)
            }
            
            if _viewport?.height > Double(size.height) {
                _viewport?.height = Double(size.height)
            }

        }
    }
    
    func setVideoFilter(filterPasses:[String], usesBlur:Bool = true) {
        print("Setting filter...")
        _currentVideoFilter = filterPasses.map {self.cachedPipelineStateFor($0)!}
        _currentVideoFilterUsesBlur = usesBlur
    }
    
    func setColorFilter(shaderName:String, convolution:[Float32]) {
        
        guard let shader = cachedPipelineStateFor(shaderName) else {
            return
        }
        
        _currentColorFilter = shader
        _currentColorConvolution = convolution
    }
    
    func setResolution(width width: Int, height: Int) {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        
        let scale = UIScreen.mainScreen().nativeScale
  
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
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(.BGRA8Unorm, width: textureWidth, height: textureHeight, mipmapped: false)
        
        if #available(iOS 9.0, *) {
            descriptor.resourceOptions = MTLResourceOptions.StorageModePrivate
            descriptor.storageMode = MTLStorageMode.Private
        }
        
        _intermediateTextures = [descriptor,descriptor].map { self._device!.newTextureWithDescriptor($0) }
        _intermediateRenderPassDescriptor = _intermediateTextures.map {
            let renderDescriptor = MTLRenderPassDescriptor()
            renderDescriptor.colorAttachments[0].texture = $0
            renderDescriptor.colorAttachments[0].loadAction = .DontCare
            renderDescriptor.colorAttachments[0].storeAction = .DontCare
            return renderDescriptor
        }
        
        _rgbTexture = _device!.newTextureWithDescriptor(descriptor)
        _rgbDescriptor = MTLRenderPassDescriptor()
        _rgbDescriptor.colorAttachments[0].texture = _rgbTexture
        _rgbDescriptor.colorAttachments[0].loadAction = .DontCare
        _rgbDescriptor.colorAttachments[0].storeAction = .Store
        
        _blurTexture = _device!.newTextureWithDescriptor(descriptor)
        _blurDescriptor = MTLRenderPassDescriptor()
        _blurDescriptor.colorAttachments[0].texture = _blurTexture
        _blurDescriptor.colorAttachments[0].loadAction = .DontCare
        _blurDescriptor.colorAttachments[0].storeAction = .Store
        
        setBlurBuffer()
    }
    
    
    func captureBuffer(sampleBuffer: CMSampleBuffer!) {
        if _rgbTexture != nil, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            
            let commandBuffer = _commandQueue.commandBuffer()
            commandBuffer.enqueue()
            defer {
                commandBuffer.commit()
            }
            
            var y_texture: Unmanaged<CVMetalTexture>?
            let y_width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let y_height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, pixelBuffer, nil, MTLPixelFormat.R8Unorm, y_width, y_height, 0, &y_texture)
            
            var uv_texture: Unmanaged<CVMetalTexture>?
            let uv_width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
            let uv_height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, pixelBuffer, nil, MTLPixelFormat.RG8Unorm, uv_width, uv_height, 1, &uv_texture)
            
            let luma = CVMetalTextureGetTexture(y_texture!.takeRetainedValue())!
            let chroma = CVMetalTextureGetTexture(uv_texture!.takeRetainedValue())!
            
            let yuvTextures:[MTLTexture] = [ luma, chroma ]
            
            // create the YUV->RGB pass
            createRenderPass(commandBuffer,
                pipeline: _currentColorFilter,
                vertexIndex: 0,
                fragmentBuffers: [_colorArgs.bufferAndOffsetForElement(_currentColorBuffer)],
                sourceTextures: yuvTextures,
                descriptor: _rgbDescriptor,
                viewport: nil)
            
            CVMetalTextureCacheFlush(_textureCache, 0)

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
    
    func setColorBuffer() {
        let nextBuffer = (_currentColorBuffer + 1) % _numberShaderBuffers
        _currentColorBuffer += 1

        if _currentColorConvolution.count == 9 {
            _colorArgs[nextBuffer].yuvToRGB?.set(
                (
                    (_currentColorConvolution[0], _currentColorConvolution[1], _currentColorConvolution[2]),
                    (_currentColorConvolution[3], _currentColorConvolution[4], _currentColorConvolution[5]),
                    (_currentColorConvolution[6], _currentColorConvolution[7], _currentColorConvolution[8])
                )
            )
        } else {
            _colorArgs[nextBuffer].yuvToRGB?.clearIdentity()
        }

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