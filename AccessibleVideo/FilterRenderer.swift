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
    private var _vertexBuffers = [UIInterfaceOrientation : (MTLBuffer,Int)]()

    private var _passthroughBuffer:(MTLBuffer,Int)! = nil
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
        CVMetalTextureCacheCreate(nil, nil, _device, nil, &_unmanagedTextureCache)
        _textureCache = _unmanagedTextureCache!.takeUnretainedValue()
        
        // set up the full screen quads
        let dataPassthrough:[Float] =
        [ -1.0,  -1.0,  0.0, 1.0,
            1.0,  -1.0,  1.0, 1.0,
            -1.0,   1.0,  0.0, 0.0,
            1.0,  -1.0,  1.0, 1.0,
            -1.0,   1.0,  0.0, 0.0,
            1.0,   1.0,  1.0, 0.0]
        
        // set up vertex buffer
        var dataSize = dataPassthrough.count * sizeofValue(dataPassthrough[0]) // 1
        _passthroughBuffer = (_device.newBufferWithBytes(dataPassthrough, length: dataSize, options: nil),0)
        _vertexBuffers[.LandscapeRight] = _passthroughBuffer
        
        let dataLandscapeLeft:[Float] =
        [ -1.0,  -1.0,  1.0, 0.0,
            1.0,  -1.0,  0.0, 0.0,
            -1.0,   1.0,  1.0, 1.0,
            1.0,  -1.0,  0.0, 0.0,
            -1.0,   1.0,  1.0, 1.0,
            1.0,   1.0,  0.0, 1.0]
        
        // set up vertex buffer
        dataSize = dataLandscapeLeft.count * sizeofValue(dataLandscapeLeft[0]) // 1
        _vertexBuffers[.LandscapeLeft] = (_device.newBufferWithBytes(dataLandscapeLeft, length: dataSize, options: nil),0)
        
        let dataPortrait:[Float] =
        [ -1.0,  -1.0,  1.0, 1.0,
            1.0,  -1.0,  1.0, 0.0,
            -1.0,   1.0,  0.0, 1.0,
            1.0,  -1.0,  1.0, 0.0,
            -1.0,   1.0,  0.0, 1.0,
            1.0,   1.0,  0.0, 0.0]
        
        // set up vertex buffer
        dataSize = dataPortrait.count * sizeofValue(dataPortrait[0]) // 1
        _vertexBuffers[.Portrait] = (_device.newBufferWithBytes(dataPortrait, length: dataSize, options: nil),0)
        
        let dataPortraitUpsideDown:[Float] =
        [ -1.0,  -1.0,  0.0, 0.0,
            1.0,  -1.0,  0.0, 1.0,
            -1.0,   1.0,  1.0, 0.0,
            1.0,  -1.0,  0.0, 1.0,
            -1.0,   1.0,  1.0, 0.0,
            1.0,   1.0,  1.0, 1.0]
        
        // set up vertex buffer
        dataSize = dataPortraitUpsideDown.count * sizeofValue(dataPortraitUpsideDown[0]) // 1
        _vertexBuffers[.PortraitUpsideDown] = (_device.newBufferWithBytes(dataPortraitUpsideDown, length: dataSize, options: nil),0)
        
        // create default shader library
        _shaderLibrary = _device.newDefaultLibrary()!
        println("Loading shader library...")
        for str in _shaderLibrary.functionNames as! [String] {
            println("Found shader: \(str)")
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

        var fragmentArgs = (_shaderArguments["blit"]!.fragmentArguments as! [MTLArgument]).filter({$0.name == "filterParameters"})
        if fragmentArgs.count == 1 {
            _filterArgs = MetalBufferArray<FilterBuffer>(arguments: fragmentArgs[0], count: _numberShaderBuffers)
        }
    
        fragmentArgs = (_shaderArguments["yuv_rgb"]!.fragmentArguments as! [MTLArgument]).filter({$0.name == "colorParameters"})
        if fragmentArgs.count == 1 {
            _colorArgs = MetalBufferArray<ColorBuffer>(arguments: fragmentArgs[0], count: _numberShaderBuffers)
        }
        
        if _device.supportsFeatureSet(._iOS_GPUFamily2_v1) {
            println("Using high quality blur...")
            highQuality = true
            _blurPipelineStates = ["BlurX_HQ", "BlurY_HQ"].map {self.cachedPipelineStateFor($0)!}
            let fragmentArgs = (_shaderArguments["BlurX_HQ"]!.fragmentArguments as! [MTLArgument]).filter({$0.name == "blurParameters"})
            if fragmentArgs.count == 1 {
                _blurArgs = MetalBufferArray<BlurBuffer>(arguments: fragmentArgs[0], count: _numberShaderBuffers)
            }
        } else {
            highQuality = false
            _blurPipelineStates = ["BlurX", "BlurY"].map {self.cachedPipelineStateFor($0)!}
            let fragmentArgs = (_shaderArguments["BlurX"]!.fragmentArguments as! [MTLArgument]).filter({$0.name == "blurParameters"})
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
        _samplerStates = [nearest, bilinear].map {self._device.newSamplerStateWithDescriptor($0)}


        
        // create the command queue
        _commandQueue = _device.newCommandQueue()
    }
    
    // create a pipeline state descriptor for a vertex/fragment shader combo
    func pipelineStateFor(#label:String!, fragmentShader:String!, vertexShader: String?) -> (MTLRenderPipelineState?, MTLRenderPipelineReflection?) {
        if let fragmentProgram = _shaderLibrary.newFunctionWithName(fragmentShader), let vertexProgram = _shaderLibrary.newFunctionWithName(vertexShader ?? "defaultVertex") {
            let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
            pipelineStateDescriptor.label = label
            pipelineStateDescriptor.vertexFunction = vertexProgram
            pipelineStateDescriptor.fragmentFunction = fragmentProgram
            
            pipelineStateDescriptor.colorAttachments[0].pixelFormat = .BGRA8Unorm
            
            pipelineStateDescriptor.vertexDescriptor = _vertexDesc
            
            // create the actual pipeline state
            var pipelineError : NSError?
            var info:MTLRenderPipelineReflection? = nil
            
            if var pipelineState = _device.newRenderPipelineStateWithDescriptor(pipelineStateDescriptor, options: .BufferTypeInfo, reflection: &info, error: &pipelineError) {
                return (pipelineState, info)
            }
            
            println("Failed to create pipeline state for shaders \(vertexShader):\(fragmentShader) error \(pipelineError)")
        }
        return (nil, nil)
    }
    
    func cachedPipelineStateFor(shaderName:String) -> MTLRenderPipelineState? {
        let pipeline:MTLRenderPipelineState?
        if let shader = _shaderPipelineStates[shaderName] {
            pipeline = shader
        } else {
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
            pipeline = state
            _shaderArguments[shaderName] = reflector
        }
        return pipeline
    }
    
    // create generic render pass
    func createRenderPass(commandBuffer: MTLCommandBuffer!,
        pipeline:MTLRenderPipelineState!,
        vertexBuffers:[(MTLBuffer,Int)], fragmentBuffers:[(MTLBuffer,Int)],
        sourceTextures:[MTLTexture],
        descriptor: MTLRenderPassDescriptor!,
        viewport:MTLViewport?) {
            if let renderEncoder = commandBuffer.renderCommandEncoderWithDescriptor(descriptor) {
                
                let name:String = pipeline.label ?? "Unnamed Render Pass"
                renderEncoder.pushDebugGroup(name)
                renderEncoder.label = name
                if let view = viewport {
                    renderEncoder.setViewport(view)
                }
                renderEncoder.setRenderPipelineState(pipeline)
                
                for (index,(buffer, offset)) in enumerate(vertexBuffers) {
                    renderEncoder.setVertexBuffer(buffer, offset: offset, atIndex: index)
                }
                for (index,(buffer, offset)) in enumerate(fragmentBuffers) {
                    renderEncoder.setFragmentBuffer(buffer, offset: offset, atIndex: index)
                }
                for (index,texture) in enumerate(sourceTextures) {
                    renderEncoder.setFragmentTexture(texture, atIndex: index)
                }
                for (index,samplerState) in enumerate(_samplerStates) {
                    renderEncoder.setFragmentSamplerState(samplerState, atIndex: index)
                }
                
                renderEncoder.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: 6, instanceCount: 1)
                renderEncoder.popDebugGroup()
                renderEncoder.endEncoding()
                
            }
    }

    func render(view: MetalView) {
        
        if _rgbTexture == nil {
            return
        }
        
        dispatch_semaphore_wait(_renderSemaphore, DISPATCH_TIME_FOREVER)

        let currentOrientation:UIInterfaceOrientation = _isiPad ? UIApplication.sharedApplication().statusBarOrientation : .Portrait

        
        if let screenDescriptor = view.renderPassDescriptor, currentBuffer = _vertexBuffers[currentOrientation] {
            
            
            
            // get the command buffer
            let commandBuffer = _commandQueue.commandBuffer()
            commandBuffer.enqueue()
            
            
            
            var sourceTexture:MTLTexture = _rgbTexture
            var destDescriptor:MTLRenderPassDescriptor = _intermediateRenderPassDescriptor[_currentDestTexture]
            
            func swapTextures() {
                self._currentSourceTexture++
                sourceTexture = self._intermediateTextures[self._currentSourceTexture]
                destDescriptor = self._intermediateRenderPassDescriptor[self._currentDestTexture]
            }
            
            var blurTex = _rgbTexture
            let passthroughParameters:[(MTLBuffer,Int)] = [_passthroughBuffer]

            if applyBlur && _currentVideoFilterUsesBlur {
                let parameters = [_blurArgs!.bufferAndOffsetForElement(_currentBlurBuffer)]
                createRenderPass(commandBuffer,
                    pipeline:  _blurPipelineStates[0],
                    vertexBuffers: passthroughParameters,
                    fragmentBuffers: parameters,
                    sourceTextures: [_rgbTexture],
                    descriptor: _intermediateRenderPassDescriptor[0],
                    viewport: nil)
                
                createRenderPass(commandBuffer,
                    pipeline:  _blurPipelineStates[1],
                    vertexBuffers: passthroughParameters,
                    fragmentBuffers: parameters,
                    sourceTextures: [_intermediateTextures[0]],
                    descriptor: _blurDescriptor,
                    viewport: nil)
                blurTex = _blurTexture
            }
            
            
            // apply all render passes in the current filter
            let filterParameters = [_filterArgs.bufferAndOffsetForElement(_currentFilterBuffer)]
            for (i, filter) in enumerate(_currentVideoFilter) {
                createRenderPass(commandBuffer,
                    pipeline: filter,
                    vertexBuffers: passthroughParameters,
                    fragmentBuffers: filterParameters,
                    sourceTextures: [sourceTexture, blurTex, _rgbTexture],
                    descriptor: destDescriptor,
                    viewport: nil)
                
                swapTextures()
            }
            
            
            createRenderPass(commandBuffer,
                pipeline: invertScreen ? _screenInvertState! : _screenBlitState!,
                vertexBuffers:[currentBuffer],
                fragmentBuffers: filterParameters,
                sourceTextures: [sourceTexture, blurTex, _rgbTexture],
                descriptor: screenDescriptor,
                viewport: self._viewport)
            
            swapTextures()
            
            // commit buffers to GPU
            commandBuffer.addCompletedHandler( {
                (cmdb:MTLCommandBuffer!) in
                dispatch_semaphore_signal(self._renderSemaphore)
                return
                }
            )
            commandBuffer.presentDrawable(view.currentDrawable!)
            commandBuffer.commit()
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
        println("Setting filter...")
        _currentVideoFilter = filterPasses.map {self.cachedPipelineStateFor($0)!}
        _currentVideoFilterUsesBlur = usesBlur
    }
    
    func setColorFilter(shaderName:String, convolution:[Float32]) {
        if let shader = cachedPipelineStateFor(shaderName) {
            _currentColorFilter = shader
            _currentColorConvolution = convolution
        }
    }
    
    func setResolution(#width: Int, height: Int) {
        objc_sync_enter(self)
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
        
        print("Setting offscreen texure resolution to \(textureWidth)x\(textureHeight)\n")
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(.BGRA8Unorm, width: textureWidth, height: textureHeight, mipmapped: false)
        
        _intermediateTextures = [descriptor,descriptor].map { self._device.newTextureWithDescriptor($0) }
        _intermediateRenderPassDescriptor = _intermediateTextures.map {
            let renderDescriptor = MTLRenderPassDescriptor()
            renderDescriptor.colorAttachments[0].texture = $0
            renderDescriptor.colorAttachments[0].loadAction = .DontCare
            renderDescriptor.colorAttachments[0].storeAction = .DontCare
            return renderDescriptor
        }
        
        _rgbTexture = _device.newTextureWithDescriptor(descriptor)
        _rgbDescriptor = MTLRenderPassDescriptor()
        _rgbDescriptor.colorAttachments[0].texture = _rgbTexture
        _rgbDescriptor.colorAttachments[0].loadAction = .DontCare
        _rgbDescriptor.colorAttachments[0].storeAction = .Store
        
        _blurTexture = _device.newTextureWithDescriptor(descriptor)
        _blurDescriptor = MTLRenderPassDescriptor()
        _blurDescriptor.colorAttachments[0].texture = _blurTexture
        _blurDescriptor.colorAttachments[0].loadAction = .DontCare
        _blurDescriptor.colorAttachments[0].storeAction = .Store
        
        setBlurBuffer()
        
        objc_sync_exit(self)

    }
    
    
    func captureBuffer(sampleBuffer: CMSampleBuffer!) {
        if _rgbTexture != nil, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            
            let commandBuffer = _commandQueue.commandBuffer()
            commandBuffer.enqueue()
            
            var y_texture: Unmanaged<CVMetalTexture>?
            let y_width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let y_height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, pixelBuffer, nil, MTLPixelFormat.R8Unorm, y_width, y_height, 0, &y_texture)
            
            var uv_texture: Unmanaged<CVMetalTexture>?
            let uv_width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
            let uv_height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, pixelBuffer, nil, MTLPixelFormat.RG8Unorm, uv_width, uv_height, 1, &uv_texture)
            
            let luma = CVMetalTextureGetTexture(y_texture!.takeRetainedValue())
            let chroma = CVMetalTextureGetTexture(uv_texture!.takeRetainedValue())
            
            let yuvTextures:[MTLTexture] = [ luma, chroma ]
            
            // create the YUV->RGB pass
            createRenderPass(commandBuffer,
                pipeline: _currentColorFilter,
                vertexBuffers: [_passthroughBuffer],
                fragmentBuffers: [_colorArgs.bufferAndOffsetForElement(_currentColorBuffer)],
                sourceTextures: yuvTextures,
                descriptor: _rgbDescriptor,
                viewport: nil)
            

            commandBuffer.commit()
            
            CVMetalTextureCacheFlush(_textureCache, 0)

        }
    }
    
    func setBlurBuffer() {
        //
        // Texel offset generation for linear sampled gaussian blur
        // Source: http://rastergrid.com/blog/2010/09/efficient-gaussian-blur-with-linear-sampling/
        //
        
        let offsets:[Float32] = [ 0.0, 1.3846153846, 3.2307692308 ]
        
        let texelWidth = 1.0 / Float32(_rgbTexture.width)
        let texelHeight = 1.0 / Float32(_rgbTexture.height)
        
        let nextBuffer = (_currentBlurBuffer + 1) % _numberShaderBuffers
        
        if let currentBuffer = _blurArgs?[nextBuffer] {
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
            _currentBlurBuffer++
        }
    }
    
    func setColorBuffer() {
        let nextBuffer = (_currentColorBuffer + 1) % _numberShaderBuffers

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
        _currentColorBuffer++

    }
    
    func setFilterBuffer() {
        let nextBuffer = (_currentFilterBuffer + 1) % _numberShaderBuffers

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
        _currentFilterBuffer++

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