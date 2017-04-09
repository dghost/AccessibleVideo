//
//  ViewController.swift
//  AccessibleVideo
//
//  Created by Luke Groeninger on 9/14/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//

import UIKit
import Metal
import MetalKit
import QuartzCore
import AVFoundation
import CoreVideo

protocol ControlsDelegate {
    var blur:Bool { get set }
    var lock:Bool { get set }
    var invert:Bool { get set }
    var frontCamera:Bool { get set }
    var autoHideUI:Bool { get set }
    var videoFilter:String { get set }
    var colorFilter:String { get set }
}

class MainViewController: UIViewController, UIGestureRecognizerDelegate, UIPopoverPresentationControllerDelegate, MBProgressHUDDelegate, ControlsDelegate {
    
    // MARK: Public properties

    @IBOutlet weak var _switchView: UIView!
    @IBOutlet weak var _settingsView: UIView!
    @IBOutlet weak var _hudView: UIView!
    
    @IBOutlet var tapGesture: UITapGestureRecognizer!
    @IBOutlet var longPressGesture: UILongPressGestureRecognizer!
    
    var renderer:FilterRenderer! = nil
    lazy var camera = CameraController()
    
    var renderview: MTKView! = nil
    
    fileprivate var _filters = FilterModel(path:Bundle.main.path(forResource: "Filters", ofType: "plist")!)!


    var _swipeActions = Dictionary<UInt, () -> ()> ()
    
    // MARK: Private properties
        
    lazy fileprivate var _hud: MBProgressHUD! = MBProgressHUD()
    
    fileprivate var _lockedImage = UIImageView(image: UIImage(named: "Lock"))
    fileprivate var _unlockedImage = UIImageView(image: UIImage(named: "Unlock"))
    fileprivate var _filterImage = UIImageView(image: UIImage(named: "VideoFilter"))
    fileprivate var _colorImage = UIImageView(image: UIImage(named: "ColorFilter"))
    
    lazy fileprivate var _defaults = NSUbiquitousKeyValueStore.default()
    fileprivate var _defaultsTimer:Timer? = nil
    
    fileprivate var _uiTimer:Timer? = nil
    
    fileprivate var _settingsDelegate:SettingsViewDelegate? = nil
    
    fileprivate var _currentVideoFilter:VideoFilter = VideoFilter()

    fileprivate var _currentColorFilter:InputFilter = InputFilter()
    
    fileprivate var _counterRotation:CGAffineTransform = CGAffineTransform.identity
    
    lazy fileprivate var _isiPad:Bool = (UIDevice.current.userInterfaceIdiom == .pad)

    fileprivate var _buttonEnabledColor = UIColor(red: 0.4, green: 1.0, blue: 1.0, alpha: 1.0)

    // MARK: Constructors / Deconstructors
    
    deinit {
        writeDefaults()
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
        NotificationCenter.default.removeObserver(self, name: UserDefaults.didChangeNotification, object:nil)
    }
    
    // MARK: UIViewController overrides
    
    override func viewDidLoad() {

        super.viewDidLoad()
        
        let scale = UIScreen.main.nativeScale

        _switchView.tintColor = UIColor.white
        _switchView.layer.shouldRasterize = true
        _switchView.layer.rasterizationScale = scale
        _switchView.isHidden = true
        
        _settingsView.tintColor = UIColor.white
        _settingsView.layer.shouldRasterize = true
        _settingsView.layer.rasterizationScale = scale
        _settingsView.isHidden = true

        _hud.margin = 10.0
        _hud.delegate = self
        _hudView.addSubview(_hud)

        tapGesture.require(toFail: longPressGesture)
        
        NotificationCenter.default.addObserver(self, selector: #selector(MainViewController.willEnterForeground(_:)), name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MainViewController.didEnterBackground(_:)), name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MainViewController.externalUpdate(_:)), name:
            NSUbiquitousKeyValueStore.didChangeExternallyNotification
            , object: nil)
        
        renderer = FilterRenderer(viewController: self)
        
        // cast view as MetalView type
        renderview = view as! MTKView
        
        // set up the renderer and set the view delegate
        renderview.delegate = renderer
        renderview.device = renderer.device
        renderview.preferredFramesPerSecond = 60
        renderview.framebufferOnly = true
        
        // set up the camera controller and set the delegate
        camera.delegate = renderer
        
        loadDefaults()
        
        startRenderLoop()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        enableVideo(true)
        setSwipeFunctions(UIApplication.shared.statusBarOrientation)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        enableVideo(false)
    }
    
    func willEnterForeground(_ sender : AnyObject) {
        enableVideo(true)
        _defaults.synchronize()
        loadDefaults()
        if lock {
            hideUI()
        } else {
            showUI()
        }
    }
    
    func didEnterBackground(_ sender : AnyObject) {
        writeDefaults()
        enableVideo(false)
    }
    
    func endRotation() {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        if _isRotating {
            setSwipeFunctions(UIApplication.shared.statusBarOrientation)
            UIView.setAnimationsEnabled(true)
            
            UIView.animate(withDuration: 0.5, animations: {
                    () -> Void in
                    self._settingsView.transform = self._counterRotation
                    self._switchView.transform = self._counterRotation
                    self._hudView.transform = self._counterRotation
            })
                
            _isRotating = false
        }
    }
    
    fileprivate var _isRotating = false
    func startRotation(_ coordinator:UIViewControllerTransitionCoordinator) {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        if !_isRotating {
            _isRotating = true

            if _settingsDelegate == nil {
                UIView.setAnimationsEnabled(false)
            }
            
            let transform = coordinator.targetTransform

            let invertedRotation = transform.inverted()
            
            
            let currentBounds = self.view.bounds
            let settingsFrame = self._settingsView.frame
            let switchFrame = self._switchView.frame
            let hudFrame = self._hudView.frame
            self._counterRotation = self._counterRotation.concatenating(transform)

            coordinator.animate(
                alongsideTransition: {
                    (_) -> Void in
                    self.view.transform = self.view.transform.concatenating(invertedRotation)
                    self.view.bounds = currentBounds
                    self._settingsView.frame = settingsFrame
                    self._switchView.frame = switchFrame
                    self._hudView.frame = hudFrame
                },
                completion: {
                    (_) -> Void  in
                    self.endRotation()
                }
            )
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        if !_isiPad {
            self.startRotation(coordinator)
        }
        super.viewWillTransition(to: size, with: coordinator)
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {

        if touch.view!.superview == _switchView || touch.view!.superview == _settingsView {
            return false
        }
        return true
    }
    
    @IBAction func handleSettingsButton(_ sender: UIButton) {
        if renderer.highQuality {
            self.performSegue(withIdentifier: "settings-hq", sender: self)
        } else {
            self.performSegue(withIdentifier: "settings", sender: self)
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "settings" || segue.identifier == "settings-hq" {
            let nav = segue.destination as! UINavigationController
            let popover = nav.viewControllers.first as! SettingsViewController
            
            // set the navigation controller to be it's own popover presentation controller delegate
            nav.popoverPresentationController?.delegate = self

            
            // set delegates for settings communication
            popover.delegate = self
            _settingsDelegate = popover
            
            // kill the UI dismissal timer
            _uiTimer?.invalidate()
            enableUI = true
            UIView.animate(withDuration: 0.5, animations: {
                () -> Void in
                self._settingsView.tintColor = self._buttonEnabledColor
            }) 
        }
    }
    
    func setSwipeFunctions(_ orientation:UIInterfaceOrientation) {
        if (_isiPad) {
            _swipeActions[UISwipeGestureRecognizerDirection.left.rawValue] = nextVideoFilter
            _swipeActions[UISwipeGestureRecognizerDirection.right.rawValue] = prevVideoFilter
            _swipeActions[UISwipeGestureRecognizerDirection.down.rawValue] = nextColorFilter
            _swipeActions[UISwipeGestureRecognizerDirection.up.rawValue] = prevColorFilter
        } else {
            switch(orientation) {
            case .portrait:
                _swipeActions[UISwipeGestureRecognizerDirection.left.rawValue] = nextVideoFilter
                _swipeActions[UISwipeGestureRecognizerDirection.right.rawValue] = prevVideoFilter
                _swipeActions[UISwipeGestureRecognizerDirection.up.rawValue] = nextColorFilter
                _swipeActions[UISwipeGestureRecognizerDirection.down.rawValue] = prevColorFilter
                break;
            case .portraitUpsideDown:
                _swipeActions[UISwipeGestureRecognizerDirection.right.rawValue] = nextVideoFilter
                _swipeActions[UISwipeGestureRecognizerDirection.left.rawValue] = prevVideoFilter
                _swipeActions[UISwipeGestureRecognizerDirection.down.rawValue] = nextColorFilter
                _swipeActions[UISwipeGestureRecognizerDirection.up.rawValue] = prevColorFilter
                break;
            case .landscapeLeft:
                _swipeActions[UISwipeGestureRecognizerDirection.up.rawValue] = nextVideoFilter
                _swipeActions[UISwipeGestureRecognizerDirection.down.rawValue] = prevVideoFilter
                _swipeActions[UISwipeGestureRecognizerDirection.left.rawValue] = nextColorFilter
                _swipeActions[UISwipeGestureRecognizerDirection.right.rawValue] = prevColorFilter
                break;
            case .landscapeRight:
                _swipeActions[UISwipeGestureRecognizerDirection.up.rawValue] = nextVideoFilter
                _swipeActions[UISwipeGestureRecognizerDirection.down.rawValue] = prevVideoFilter
                _swipeActions[UISwipeGestureRecognizerDirection.right.rawValue] = nextColorFilter
                _swipeActions[UISwipeGestureRecognizerDirection.left.rawValue] = prevColorFilter
                break;
            default:
                break;
            }
        }
    }
    
    @IBAction func unwindSegue (_ segue:UIStoryboardSegue){
        if (!_isiPad) {
            _settingsDelegate = nil
            UIView.animate(withDuration: 0.5, animations: {
                () -> Void in
                self._settingsView.tintColor = UIColor.white
            }) 
            saveDefaults()
            if lock {
                hideUI()
            } else {
                showUI()
            }
        }
    }
    
    // MARK: Render Loop
    
    func startRenderLoop() {
        enableVideo(true)

    }
    
    func stopRenderLoop() {
        enableVideo(false)

    }
    
    func enableVideo(_ enable:Bool) {
        print("Video processing: \(enable)")
        camera.running = enable
        UIApplication.shared.isIdleTimerDisabled = enable
    }
    
    // MARK: iCloud updating
    
    func saveDefaults() {
        // coalesce writes to the iCloud key/value store to only occure once every 2 seconds at max
        _defaultsTimer?.invalidate()
        _defaultsTimer = Timer(timeInterval: TimeInterval(2.0), target: self, selector: #selector(MainViewController.writeDefaults), userInfo: nil, repeats: false)
        RunLoop.current.add(_defaultsTimer!, forMode: RunLoopMode.defaultRunLoopMode)
    }
    
    func writeDefaults() {
        _defaultsTimer = nil
        
        var changed:Bool = false
        
        // synchronize values in the key value store
        if _defaults.bool(forKey: "lock") != lock {
            _defaults.set(lock, forKey: "lock")
            changed = true
        }
        
        if _defaults.bool(forKey: "autoHideUI") != autoHideUI {
            _defaults.set(autoHideUI, forKey: "autoHideUI")
            changed = true
        }
        
        if _defaults.bool(forKey: "blur") != blur {
            _defaults.set(blur, forKey: "blur")
            changed = true
        }
        
        if _defaults.bool(forKey: "invert") != invert {
            _defaults.set(invert, forKey: "invert")
            changed = true
        }
        
        if camera.supportsFrontCamera {
            if _defaults.bool(forKey: "useFrontCamera") != frontCamera {
                _defaults.set(frontCamera, forKey: "useFrontCamera")
                changed = true
            }
        }
        
        if _defaults.string(forKey: "videoFilter") != videoFilter {
            _defaults.set(videoFilter, forKey: "videoFilter")
            changed = true
        }

        if _defaults.string(forKey: "colorFilter") != colorFilter {
            _defaults.set(colorFilter, forKey: "colorFilter")
            changed = true
        }
        
        // if something changed, force a synchronization of the key value store
        // in reality, this is probably a bad thing to be doing frequently and is likely to get the app throttled
        if changed == true {
            print("Writing to key-value store...")
            _defaults.synchronize()
        }
    }
    
    func loadDefaults() {
        // load the defaults from the key value store
        autoHideUI = _defaults.bool(forKey: "autoHideUI")
        lock = _defaults.bool(forKey: "lock")
        blur = _defaults.bool(forKey: "blur")
        invert = _defaults.bool(forKey: "invert")
        frontCamera = camera.supportsFrontCamera  ? _defaults.bool(forKey: "useFrontCamera") : false
        colorFilter = _defaults.string(forKey: "colorFilter") ?? ""
        videoFilter = _defaults.string(forKey: "videoFilter") ?? ""
    }
    
    func externalUpdate(_ notification:Notification) {
        
        
        // read in the updates
        guard let keys:NSArray = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? NSArray else {
            return
        }
        
        // stop observing iCloud updates while we update
        NotificationCenter.default.removeObserver(self, name: UserDefaults.didChangeNotification, object:nil)
  
        print("Processing updates...")
        for key in keys as! [String] {
            print("Received update for \(key)")
            switch key {
            case "lock":
                lock = _defaults.bool(forKey: key)
                break;
            case "autoHideUI":
                autoHideUI = _defaults.bool(forKey: key)
                break;
            case "blur":
                blur = _defaults.bool(forKey: key)
                break;
            case "invert":
                invert = _defaults.bool(forKey: key)
                break;
            case "useFrontCamera":
                if camera.supportsFrontCamera {
                    frontCamera = _defaults.bool(forKey: key)
                }
            case "videoFilter":
                videoFilter = _defaults.string(forKey: key) ?? ""
                break;
            case "colorFilter":
                colorFilter = _defaults.string(forKey: key) ?? ""
                break;
            default:
                print("Unrecognized key \(key)")
                break;
            }
        }
        
        // start observing iCloud updates again
        NotificationCenter.default.addObserver(self, selector: #selector(MainViewController.externalUpdate(_:)), name: UserDefaults.didChangeNotification, object: nil)
    }
    
    // MARK: UI / Overlay Manipulation
    
    func showOverlayWithText(_ text:String) {
        _hud.hide(animated: false)
        _hud.customView = nil
        _hud.mode = .text
        _hud.label.text = text
        _hud.show(animated: true)
        _hud.hide(animated: true, afterDelay: 2)
        
    }
    
    func showOverlayWithText(_ text:String, andImageView imageView:UIImageView) {
        _hud.hide(animated: false)
        _hud.customView = imageView
        _hud.mode = .customView
        _hud.label.text = text
        _hud.show(animated: true)
        _hud.hide(animated: true, afterDelay: 2)
    }
    
    func showLockOverlay(_ locked:Bool) {
        if locked {
            showOverlayWithText("Locked", andImageView: _lockedImage)
        } else {
            showOverlayWithText("Unlocked", andImageView: _unlockedImage)
        }
    }
    
    func showUI() {
        enableUI = true
        
        if (autoHideUI) {
            _uiTimer = Timer(timeInterval: TimeInterval(2.0), target: self, selector: #selector(MainViewController.hideUI), userInfo: nil, repeats: false)
            RunLoop.current.add(_uiTimer!, forMode: RunLoopMode.defaultRunLoopMode)
        }
    }
    
    func hideUI() {
        enableUI = false
    }
    
    var enableUI:Bool = false {
        willSet {
            _uiTimer?.invalidate()
            _uiTimer = nil
            if enableUI != newValue {
                if _settingsView.isHidden == newValue {
                    _settingsView.layer.shouldRasterize = false
                    UIView.transition(with: _settingsView, duration: 0.25, options: UIViewAnimationOptions.transitionCrossDissolve,
                        animations: {
                        () -> Void in
                        self._settingsView.isHidden = !newValue
                        },
                        completion: {
                        (finished:Bool) -> Void in
                            if finished { self._settingsView.layer.shouldRasterize = true }
                        }
                    )
                }
                
                let cameraEnable = camera.supportsFrontCamera ? newValue : false
                
                if cameraEnable == _switchView.isHidden {
                    _switchView.layer.shouldRasterize = false

                    UIView.transition(with: _switchView, duration: 0.25, options: UIViewAnimationOptions.transitionCrossDissolve,
                        animations: {
                        () -> Void in
                            self._switchView.isHidden = !cameraEnable
                        },
                        completion: {
                            (finished:Bool) -> Void in
                            if finished { self._switchView.layer.shouldRasterize = true }
                        }
                    )

                }
            }
        }
    }
    
    // MARK: Filter Manipulation    
    func setVideoFilter(_ filter:VideoFilter)
    {
        if (_currentVideoFilter.name != filter.name)
        {
            _currentVideoFilter = filter
            renderer.setVideoFilter(filter)
            showOverlayWithText(filter.name, andImageView: _filterImage)
            saveDefaults()
        }
    }
    
    func nextVideoFilter() {
        if let filter = _filters.videoFilters.nextFilter()
        {
            setVideoFilter(filter)
        }
    }
    
    func prevVideoFilter() {
        if let filter = _filters.videoFilters.prevFilter()
        {
            setVideoFilter(filter)
        }
    }
    
    func setColorFilter(_ newFilter:InputFilter)
    {
        if (_currentColorFilter.name != newFilter.name)
        {
            _currentColorFilter = newFilter
            renderer.setColorFilter(newFilter)

            showOverlayWithText(newFilter.name, andImageView: _colorImage)
            saveDefaults()
        }
    }
    func nextColorFilter() {
        if let colorFilter = _filters.inputFilters.nextFilter() {
            setColorFilter(colorFilter)
        }
    }
    
    func prevColorFilter() {
        if let colorFilter = _filters.inputFilters.prevFilter() {
            setColorFilter(colorFilter)
        }
    }
    
    // MARK: Delegate Members
    
    var videoFilter:String {
        get {
            return _currentVideoFilter.name
        }
        set {
            if let filter = _filters.videoFilters.getFilter(name: newValue)
            {
                setVideoFilter(filter)
            }
        }
    }
    
    var colorFilter:String {
        get {
            return _currentColorFilter.name
        }
        set {
            if let filter = _filters.inputFilters.getFilter(name: newValue)
            {
                setColorFilter(filter)
            }
        }
    }
    
    var lock:Bool = false {
        didSet {
            print("Setting lock: \(lock)")
            if _settingsDelegate == nil {
                if lock {
                    hideUI()
                } else {
                    showUI()
                }
            }
            showLockOverlay(lock)
            saveDefaults()
        }
    }
    
    var blur:Bool = false {
        didSet {
            print("Setting blur: \(blur)")
            _settingsDelegate?.setBlur(blur)
            renderer.applyBlur = blur
            saveDefaults()
        }
    }
    
    var invert:Bool = false {
        didSet {
            print("Setting invert: \(invert)")
            _settingsDelegate?.setInvert(invert)
            renderer.invertScreen = invert
            saveDefaults()
        }
    }
    
    var frontCamera:Bool = false {
        didSet {
            print("Setting front camera: \(frontCamera)")
            camera.useFrontCamera = frontCamera
            UIView.animate(withDuration: 0.5, animations: {
                () -> Void in
                if (self.frontCamera){
                    self._switchView.tintColor = self._buttonEnabledColor

                } else {
                    self._switchView.tintColor = UIColor.white
                }
            }) 
                
            saveDefaults()
        }
    }
    
    var autoHideUI:Bool = false {
        didSet {
            if !autoHideUI {
                _uiTimer?.invalidate()
                _uiTimer = nil
            } else {
                if _settingsDelegate == nil && enableUI {
                    _uiTimer = Timer(timeInterval: TimeInterval(2.0), target: self, selector: #selector(MainViewController.hideUI), userInfo: nil, repeats: false)
                    RunLoop.current.add(_uiTimer!, forMode: RunLoopMode.defaultRunLoopMode)
                }
            }
            _settingsDelegate?.setAutoHide(autoHideUI)
            saveDefaults()
        }
    }
    
    // MARK: Gesture Recognizers
    
    @IBAction func tapGestureRecognizer(_ sender: UITapGestureRecognizer) {
        if sender.state == .ended && !lock {
            if _settingsView.isHidden {
                showUI()
            } else {
                hideUI()
            }
        }
    }
    
    @IBAction func swipeGestureRecognizer(_ sender: UISwipeGestureRecognizer) {
        if sender.state == .ended && !lock {
            _swipeActions[sender.direction.rawValue]?()
        }
    }
    @IBAction func longPressRecognizer(_ sender: UILongPressGestureRecognizer) {
        if sender.state == UIGestureRecognizerState.began {
            lock = !lock
        }
    }
    
    @IBAction func switchButton(_ sender: AnyObject) {
        if camera.supportsFrontCamera {
            frontCamera = !frontCamera
        }
    }
    
    func popoverPresentationControllerShouldDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) -> Bool {
        if (_isiPad) {
            _settingsDelegate = nil
            UIView.animate(withDuration: 0.5, animations: {
                () -> Void in
                self._settingsView.tintColor = UIColor.white
            }) 
            saveDefaults()
            if lock {
                hideUI()
            } else {
                showUI()
            }
        }
        return true
    }
    
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return UIModalPresentationStyle.overFullScreen
    }
}

