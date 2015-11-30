//
//  MetalView.swift
//  AccessibleVideo
//
//  Created by Luke Groeninger on 10/5/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//

import Foundation
import UIKit
import Metal
import QuartzCore

protocol MetalViewDelegate {
    func render(view:MetalView)
    func resize(size:CGSize)
}

class MetalView:UIView {
    
    var delegate:MetalViewDelegate! = nil
    
    var device:MTLDevice! {
        return _device
    }
    
    var renderPassDescriptor:MTLRenderPassDescriptor? {
        if let drawable = self.currentDrawable {
            setupRenderPassDescriptorForTexture(drawable.texture)
        } else {
            _renderPassDescriptor = nil
        }
        return _renderPassDescriptor
    }
    
    var currentDrawable:CAMetalDrawable? {
        if _currentDrawable == nil {
            _currentDrawable = _metalLayer.nextDrawable()
        }
        return _currentDrawable
    }
    
    private var _layerSizeDidUpdate:Bool = false
    private weak var _metalLayer:CAMetalLayer! = nil
    private var _currentDrawable:CAMetalDrawable? = nil
    private var _renderPassDescriptor:MTLRenderPassDescriptor? = nil
    lazy private var _device:MTLDevice = MTLCreateSystemDefaultDevice()!

    
    override class func layerClass() -> AnyClass {
        return CAMetalLayer.self
    }
    
    func initCommon() {
        self.opaque = true
        self.backgroundColor = nil
        _metalLayer = self.layer as! CAMetalLayer
        _metalLayer.presentsWithTransaction = false
        _metalLayer.device = _device
        _metalLayer.pixelFormat = .BGRA8Unorm
        _metalLayer.framebufferOnly = true
    }
    
    override func didMoveToWindow() {
        if let win = window {
            contentScaleFactor = win.screen.nativeScale
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        initCommon()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        initCommon()
    }

    func setupRenderPassDescriptorForTexture(texture:MTLTexture!) {
        if _renderPassDescriptor == nil {
            _renderPassDescriptor = MTLRenderPassDescriptor()
            _renderPassDescriptor!.colorAttachments[0].loadAction = .Clear
            _renderPassDescriptor!.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
            _renderPassDescriptor!.colorAttachments[0].storeAction = .Store
        }
        
        _renderPassDescriptor!.colorAttachments[0].texture = texture

    }

    func display() {
        autoreleasepool {
            if self._layerSizeDidUpdate {
                var drawableSize = self.bounds.size
                drawableSize.width *= self.contentScaleFactor
                drawableSize.height *= self.contentScaleFactor
                self._metalLayer.drawableSize = drawableSize
                self.delegate.resize(drawableSize)
                self._layerSizeDidUpdate = false
            }
            self.delegate.render(self)
            self._currentDrawable = nil
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        _layerSizeDidUpdate = true
    }
    
}
