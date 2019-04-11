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
import MetalKit
import AVFoundation
import UIKit

protocol RendererControlDelegate {
    var primaryColor:float4 { get set }
    var secondaryColor:float4 { get set }
    var invertScreen:Bool { get set }
    var applyBlur:Bool { get set }
    var highQuality:Bool { get }
}

class FilterRenderer: NSObject, MTKViewDelegate, CameraCaptureDelegate, RendererControlDelegate {
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
    
    fileprivate var _blurPipelineStates:ContiguousArray<MTLRenderPipelineState?> = [nil,nil]
    fileprivate var _screenBlitState:MTLRenderPipelineState! = nil
    fileprivate var _screenInvertState:MTLRenderPipelineState! = nil
    
    fileprivate var _commandQueue: MTLCommandQueue! = nil
    
    fileprivate var _intermediateTextures:ContiguousArray<MTLTexture?> = [nil,nil]
    fileprivate var _intermediateRenderPassDescriptor:ContiguousArray<MTLRenderPassDescriptor?> = [nil,nil]

    
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
    
    fileprivate var _yuvTextures:ContiguousArray<MTLTexture?> = [nil, nil]

    fileprivate var _numberBufferedFrames:Int = 2
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
    
    fileprivate var _samplerStates:ContiguousArray<MTLSamplerState?> = [nil, nil]
    
    fileprivate var _currentVideoFilterUsesBlur = true
    fileprivate var _currentVideoFilter = [MTLRenderPipelineState]()
    fileprivate var _currentColorFilter:MTLRenderPipelineState! = nil

    lazy fileprivate var _isiPad:Bool = (UIDevice.current.userInterfaceIdiom == .pad)
    
    fileprivate var _viewport:MTLViewport = MTLViewport()
    
    init(viewController:UIViewController!, initialWidth:Double, initialHeight:Double) {
        super.init()
        _controller = viewController
        setupRenderer()
        setViewSize(width: initialWidth, height: initialHeight)
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
        _shaderLibrary = _device!.makeDefaultLibrary()!
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
            _blurPipelineStates[0] = self.cachedPipelineStateFor("BlurX_HQ")!
            _blurPipelineStates[1] = self.cachedPipelineStateFor("BlurY_HQ")!
            
            let fragmentArgs = (_shaderArguments["BlurX_HQ"]!.fragmentArguments!).filter({$0.name == "blurParameters"})
            if fragmentArgs.count == 1 {
                _blurArgs = MetalBufferArray<BlurBuffer>(arguments: fragmentArgs[0], count: _numberShaderBuffers)
            }
        } else {
            highQuality = false
            _blurPipelineStates[0] = self.cachedPipelineStateFor("BlurX")!
            _blurPipelineStates[1] = self.cachedPipelineStateFor("BlurY")!

            let fragmentArgs = (_shaderArguments["BlurX"]!.fragmentArguments!).filter({$0.name == "blurParameters"})
            if fragmentArgs.count == 1 {
                _blurArgs = MetalBufferArray<BlurBuffer>(arguments: fragmentArgs[0], count: _numberShaderBuffers)
            }
        }
        
        setFilterBuffer()
        
        
        let nearest = MTLSamplerDescriptor()
        nearest.label = "nearest"
        _samplerStates[0] = self._device!.makeSamplerState(descriptor:nearest)
        
        let bilinear = MTLSamplerDescriptor()
        bilinear.label = "bilinear"
        bilinear.minFilter = .linear
        bilinear.magFilter = .linear
        _samplerStates[1] = self._device!.makeSamplerState(descriptor:bilinear)
        
        // create the command queue
        _commandQueue = _device!.makeCommandQueue()
    }
    
    // create a pipeline state descriptor for a vertex/fragment shader combo
    func pipelineStateFor(label:String!, fragmentShader:String!, vertexShader: String?) -> (MTLRenderPipelineState?, MTLRenderPipelineReflection?) {
        if let fragmentProgram = _shaderLibrary.makeFunction(name: fragmentShader), let vertexProgram = _shaderLibrary.makeFunction(name: vertexShader ?? "defaultVertex") {
            if #available(iOS 10, *) {
                fragmentProgram.label = "Fragment: " + fragmentShader
                vertexProgram.label = "Vertex: " + vertexProgram.name
            }
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
                print("Failed to create pipeline state for shaders \(String(describing: vertexShader)):\(String(describing: fragmentShader)) error \(pipelineError)")
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
    
    struct RenderPass {
        var descriptor:MTLRenderPassDescriptor
        var pipeline:MTLRenderPipelineState
        var vertexIndex:Int
        var fragmentBuffers:[(MTLBuffer,Int)]
        var sourceTextures:ContiguousArray<MTLTexture?>
        var viewport:MTLViewport?
    }
    
    func encodeRenderPass(_ commandBuffer: MTLCommandBuffer!, renderPass: RenderPass) {
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass.descriptor)
        
        let name:String = renderPass.pipeline.label ?? "Unnamed Render Pass"
        renderEncoder?.pushDebugGroup(name)
        renderEncoder?.label = name
        if let view = renderPass.viewport {
            renderEncoder?.setViewport(view)
        }
        renderEncoder?.setRenderPipelineState(renderPass.pipeline)
        
        renderEncoder?.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)
        
        for (index,(buffer, offset)) in renderPass.fragmentBuffers.enumerated() {
            renderEncoder?.setFragmentBuffer(buffer, offset: offset, index: index)
        }
        
        renderPass.sourceTextures.withUnsafeBufferPointer() { buffer in
            let range = NSMakeRange(0, buffer.count)
            if let base = buffer.baseAddress {
                renderEncoder?.__setFragmentTextures(base, with: range)
            }
        }
        
        _samplerStates.withUnsafeBufferPointer() { buffer in
            let range = NSMakeRange(0, buffer.count)
            if let base = buffer.baseAddress {
                renderEncoder?.__setFragmentSamplerStates(base, with: range)
            }
        }
        
        renderEncoder?.drawPrimitives(type: .triangle, vertexStart: renderPass.vertexIndex, vertexCount: 6, instanceCount: 1)
        renderEncoder?.popDebugGroup()
        renderEncoder?.endEncoding()
    }
    
    public func commitRenderPass(_ renderPass:RenderPass, closure: ((MTLCommandBuffer) -> ())? = nil)
    {

        let commandBuffer = _commandQueue.makeCommandBuffer()
        
        encodeRenderPass(commandBuffer, renderPass: renderPass)
        
        // commit buffers to GPU
        if let cl = closure {
            cl(commandBuffer!)
        }
        
        commandBuffer?.commit()
    }
    
    public func commitRenderPasses(_ renderPasses:[RenderPass], closure: ((MTLCommandBuffer) -> ())? = nil)
    {
        guard renderPasses.count > 0 else {
            return
        }

        let commandBuffer = _commandQueue.makeCommandBuffer()
        
        for pass in renderPasses {
            encodeRenderPass(commandBuffer, renderPass: pass)
        }
        
        // commit buffers to GPU
        if let cl = closure {
            cl(commandBuffer!)
        }
        
        commandBuffer?.commit()
    }
    
    public func draw(in view: MTKView) {
        let currentOrientation:UIInterfaceOrientation = _isiPad ? UIApplication.shared.statusBarOrientation : .portrait
        
        guard let currentOffset = _vertexStart[currentOrientation], _rgbTexture != nil else {
            return
        }
        
        _renderSemaphore.wait(timeout: DispatchTime.distantFuture)

        var yuvTextures:ContiguousArray<MTLTexture?>! = nil
        
        synced(lock: _textureCache!) {
            yuvTextures = _yuvTextures
        }

        commitRenderPass(
            RenderPass(descriptor: _rgbDescriptor, pipeline: _currentColorFilter, vertexIndex: 0, fragmentBuffers:  [_colorArgs.bufferAndOffsetForElement(_currentColorBuffer)], sourceTextures: yuvTextures, viewport: nil)
        )
        
        var blurTex = _rgbTexture!
        
        if applyBlur && _currentVideoFilterUsesBlur, let args = _blurArgs {
            var inputProcessPasses:[RenderPass] = []

            let parameters = [_blurArgs.bufferAndOffsetForElement(_currentBlurBuffer)]

            
            inputProcessPasses.append(
                RenderPass(descriptor: _intermediateRenderPassDescriptor[self._currentSourceTexture]!,
                           pipeline:  _blurPipelineStates[0]!,
                           vertexIndex: 0,
                           fragmentBuffers: parameters,
                           sourceTextures: [_rgbTexture],
                           viewport: nil))
            
            inputProcessPasses.append(
                RenderPass(descriptor: _blurDescriptor,
                           pipeline:  _blurPipelineStates[1]!,
                           vertexIndex: 0,
                           fragmentBuffers: parameters,
                           sourceTextures: [_intermediateTextures[self._currentSourceTexture]],
                           viewport: nil))
            blurTex = _blurTexture
            
            commitRenderPasses(inputProcessPasses)
        }


        var sourceTextures:ContiguousArray<MTLTexture?> = [_rgbTexture, blurTex, _rgbTexture]
        var destDescriptor:MTLRenderPassDescriptor = _intermediateRenderPassDescriptor[_currentDestTexture]!
        var sourceTextureSets:[ContiguousArray<MTLTexture?>] = [
            [self._intermediateTextures[0]!, blurTex, _rgbTexture],
            [self._intermediateTextures[1]!, blurTex, _rgbTexture]
        ]
        
        
        func swapTextures() {
            self._currentSourceTexture += 1
            sourceTextures = sourceTextureSets[self._currentSourceTexture]
            destDescriptor = self._intermediateRenderPassDescriptor[self._currentDestTexture]!
        }
        
        // apply all render passes in the current filter
        let filterParameters = [_filterArgs.bufferAndOffsetForElement(_currentFilterBuffer)]

        let filterPasses:[RenderPass] = _currentVideoFilter.map()
        {
            (filter:MTLRenderPipelineState) -> (RenderPass) in
            let pass = RenderPass(descriptor: destDescriptor,
                                  pipeline: filter,
                                  vertexIndex: 0,
                                  fragmentBuffers: filterParameters,
                                  sourceTextures: sourceTextures,
                                  viewport: nil)
            swapTextures()
            return pass
        }
        
        commitRenderPasses(filterPasses)

        if let screenDescriptor = view.currentRenderPassDescriptor,
            let currentDrawable = view.currentDrawable {
            
            let renderPass = RenderPass(descriptor: screenDescriptor,
                                        pipeline: invertScreen ? _screenInvertState! : _screenBlitState!,
                                        vertexIndex: currentOffset,
                                        fragmentBuffers: filterParameters,
                                        sourceTextures: sourceTextures,
                                        viewport: self._viewport)
            swapTextures()

            commitRenderPass(renderPass) {
                commandBuffer in
                commandBuffer.addCompletedHandler() {
                    _ in
                    self._renderSemaphore.signal()
                }
                commandBuffer.present(currentDrawable)
            }
        }

    }
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        setViewSize(width: Double(size.width), height: Double(size.height))
    }
    
    public func setViewSize(width: Double, height: Double)
    {
        if _rgbTexture != nil {
            let aspect = Double(_rgbTexture.height) / Double(_rgbTexture.width)
            
            if width > height {
                let newHeight = width * aspect
                let diff = (height - newHeight) * 0.5
                _viewport = MTLViewport(originX: 0.0, originY: diff, width: width, height: newHeight, znear: 0.0, zfar: 1.0)
            } else {
                let newWidth = height * aspect
                let diff = (width - newWidth) * 0.5
                _viewport = MTLViewport(originX: diff, originY: 0.0, width: newWidth, height: height, znear: 0.0, zfar: 1.0)
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
        
        for i in 0...1 {
            let texture = self._device!.makeTexture(descriptor: descriptor)
            texture?.label = "Intermediate Texture " + String(i)
            let renderDescriptor = MTLRenderPassDescriptor()
            renderDescriptor.colorAttachments[0].texture = texture
            renderDescriptor.colorAttachments[0].loadAction = .dontCare
            renderDescriptor.colorAttachments[0].storeAction = .store
            
            _intermediateTextures[i] = texture
            _intermediateRenderPassDescriptor[i] = renderDescriptor
        }
        
        _rgbTexture = _device!.makeTexture(descriptor: descriptor)
        _rgbTexture.label = "RGB Texture"
        _rgbDescriptor = MTLRenderPassDescriptor()
        _rgbDescriptor.colorAttachments[0].texture = _rgbTexture
        _rgbDescriptor.colorAttachments[0].loadAction = .dontCare
        _rgbDescriptor.colorAttachments[0].storeAction = .store
        
        _blurTexture = _device!.makeTexture(descriptor: descriptor)
        _blurTexture.label = "Blur Texture"
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

            
            var uv_texture: CVMetalTexture? = nil
            let uv_width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
            let uv_height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)

            
            synced(lock: tc) {
                CVMetalTextureCacheFlush(tc, 0)

                CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, tc, pixelBuffer, nil, MTLPixelFormat.r8Unorm, y_width, y_height, 0, &y_texture)
                CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, tc, pixelBuffer, nil, MTLPixelFormat.rg8Unorm, uv_width, uv_height, 1, &uv_texture)
                
                let luma = CVMetalTextureGetTexture(y_texture!)!
                luma.label = "Luma Texture"
                let chroma = CVMetalTextureGetTexture(uv_texture!)!
                chroma.label = "Chroma Texture"
                _yuvTextures = [ luma, chroma ]
            }
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
            float2(x: offsets[0] * texelWidth, y: 0),
            float2(x: offsets[1] * texelWidth, y: 0),
            float2(x: offsets[2] * texelWidth, y: 0)
        )
        
        currentBuffer.yOffsets = (
            float2(x: 0, y: offsets[0] * texelHeight),
            float2(x: 0, y: offsets[1] * texelHeight),
            float2(x: 0, y: offsets[2] * texelHeight)
        )
        _currentBlurBuffer += 1
        
        
    }
    
    func setFilterBuffer() {
        let nextBuffer = (_currentFilterBuffer + 1) % _numberShaderBuffers
        _currentFilterBuffer += 1

        let currentBuffer = _filterArgs[nextBuffer]
        if invertScreen {
            currentBuffer.primaryColor = float4(1.0 - primaryColor.x,
                                                1.0 - primaryColor.y,
                                                1.0 - primaryColor.z,
                                                primaryColor.w)
            currentBuffer.secondaryColor = float4(1.0 - secondaryColor.x,
                                                  1.0 - secondaryColor.y,
                                                  1.0 - secondaryColor.z,
                                                  secondaryColor.w)
        } else {
            currentBuffer.primaryColor = primaryColor
            currentBuffer.secondaryColor = secondaryColor
        }
        
        if highQuality {
            currentBuffer.lowThreshold = 0.05
            currentBuffer.highThreshold = 0.15
        } else {
            currentBuffer.lowThreshold = 0.15
            currentBuffer.highThreshold = 0.25
        }
    }
    
    var primaryColor:float4 = float4(0.0, 0.8, 1.0, 0.75) {
        didSet {
            setFilterBuffer()
        }
    }
    
    var secondaryColor:float4 = float4(0.6, 0.0, 1.0, 0.75){
        didSet {
            setFilterBuffer()
        }
    }
    
    var invertScreen:Bool = false {
        didSet {
            setFilterBuffer()
        }
    }
    
    func synced(lock: AnyObject, closure: () -> ()) {
        objc_sync_enter(lock)
        closure()
        objc_sync_exit(lock)
    }
}
