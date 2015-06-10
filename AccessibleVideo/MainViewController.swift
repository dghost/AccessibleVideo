//
//  ViewController.swift
//  AccessibleVideo
//
//  Created by Luke Groeninger on 9/14/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//

import UIKit
import Metal
import QuartzCore
import AVFoundation
import CoreVideo

protocol ControlsDelegate {
    var blur:Bool { get set }
    var lock:Bool { get set }
    var invert:Bool { get set }
    var frontCamera:Bool { get set }
    var autoHideUI:Bool { get set }
    var videoFilter:String? { get set }
    var colorFilter:String? { get set }
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
    
    var renderview: MetalView! = nil
    
    private var _videoFilters = NSArray(contentsOfFile: NSBundle.mainBundle().pathForResource("VideoFilters", ofType: "plist")!)
    private var _colorFilters = NSArray(contentsOfFile: NSBundle.mainBundle().pathForResource("ColorFilters", ofType: "plist")!)

    var _swipeActions = Dictionary<UInt, () -> ()> ()
    
    // MARK: Private properties
    
    private var _timer: CADisplayLink? = nil
    
    lazy private var _hud: MBProgressHUD! = MBProgressHUD()
    
    private var _lockedImage = UIImageView(image: UIImage(named: "Lock"))
    private var _unlockedImage = UIImageView(image: UIImage(named: "Unlock"))
    private var _filterImage = UIImageView(image: UIImage(named: "VideoFilter"))
    private var _colorImage = UIImageView(image: UIImage(named: "ColorFilter"))
    
    lazy private var _defaults = NSUbiquitousKeyValueStore.defaultStore()
    private var _defaultsTimer:NSTimer? = nil
    
    private var _uiTimer:NSTimer? = nil
    
    private var _settingsDelegate:SettingsViewDelegate? = nil
    
    private var _currentVideoFilter:Int = 0
    private var _currentColorFilter:Int = 0
    
    private var _counterRotation:CGAffineTransform = CGAffineTransformIdentity
    
    lazy private var _isiPad:Bool = (UIDevice.currentDevice().userInterfaceIdiom == .Pad)

    private var _buttonEnabledColor = UIColor(red: 0.4, green: 1.0, blue: 1.0, alpha: 1.0)

    // MARK: Constructors / Deconstructors
    
    deinit {
        writeDefaults()
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationWillEnterForegroundNotification, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationDidEnterBackgroundNotification, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NSUserDefaultsDidChangeNotification, object:nil)
    }
    
    // MARK: UIViewController overrides
    
    override func viewDidLoad() {

        super.viewDidLoad()
        
        let scale = UIScreen.mainScreen().nativeScale

        _switchView.tintColor = UIColor.whiteColor()
        _switchView.layer.shouldRasterize = true
        _switchView.layer.rasterizationScale = scale
        _switchView.hidden = true
        
        _settingsView.tintColor = UIColor.whiteColor()
        _settingsView.layer.shouldRasterize = true
        _settingsView.layer.rasterizationScale = scale
        _settingsView.hidden = true

        _hud.margin = 10.0
        _hud.delegate = self
        _hud.removeFromSuperViewOnHide = true
        
        tapGesture.requireGestureRecognizerToFail(longPressGesture)
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("willEnterForeground:"), name: UIApplicationWillEnterForegroundNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("didEnterBackground:"), name: UIApplicationDidEnterBackgroundNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("externalUpdate:"), name:
            NSUbiquitousKeyValueStoreDidChangeExternallyNotification
            , object: nil)
        
        renderer = FilterRenderer(viewController: self)
        
        // cast view as MetalView type
        renderview = view as! MetalView
        
        // set up the renderer and set the view delegate
        renderview.delegate = renderer
        
        // set up the camera controller and set the delegate
        camera.delegate = renderer
        
        loadDefaults()
        
        startRenderLoop()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewWillAppear(animated: Bool) {
        enableVideo(true)
        setSwipeFunctions(UIApplication.sharedApplication().statusBarOrientation)
    }
    
    override func viewDidDisappear(animated: Bool) {
        enableVideo(false)
    }
    
    func willEnterForeground(sender : AnyObject) {
        enableVideo(true)
        _defaults.synchronize()
        loadDefaults()
        if lock {
            hideUI()
        } else {
            showUI()
        }
    }
    
    func didEnterBackground(sender : AnyObject) {
        writeDefaults()
        enableVideo(false)
    }
    
    func endRotation() {
        objc_sync_enter(self)
        if _isRotating {
            setSwipeFunctions(UIApplication.sharedApplication().statusBarOrientation)
            UIView.setAnimationsEnabled(true)
            
            UIView.animateWithDuration(0.5)
                {
                    () -> Void in
                    self._settingsView.transform = self._counterRotation
                    self._switchView.transform = self._counterRotation
                    self._hudView.transform = self._counterRotation
            }
            _isRotating = false
        }
        objc_sync_exit(self)
    }
    
    private var _isRotating = false
    func startRotation(coordinator:UIViewControllerTransitionCoordinator) {
        objc_sync_enter(self)
        if !_isRotating {
            _isRotating = true

            if _settingsDelegate == nil {
                UIView.setAnimationsEnabled(false)
            }
            
            let transform = coordinator.targetTransform()

            let invertedRotation = CGAffineTransformInvert(transform)
            
            
            let currentBounds = self.view.bounds
            let settingsFrame = self._settingsView.frame
            let switchFrame = self._switchView.frame
            let hudFrame = self._hudView.frame
            self._counterRotation = CGAffineTransformConcat(self._counterRotation, transform)

            coordinator.animateAlongsideTransition(
                {
                    (_) -> Void in
                    self.view.transform = CGAffineTransformConcat(self.view.transform, invertedRotation)
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
        objc_sync_exit(self)
    }
    
    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        if !_isiPad {
            self.startRotation(coordinator)
        }
        super.viewWillTransitionToSize(size, withTransitionCoordinator: coordinator)
    }
    
    override func willTransitionToTraitCollection(newCollection: UITraitCollection, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        if !_isiPad {
            self.startRotation(coordinator)
        }
        super.willTransitionToTraitCollection(newCollection, withTransitionCoordinator: coordinator)
    }
    
    func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWithGestureRecognizer otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldReceiveTouch touch: UITouch) -> Bool {

        if touch.view!.superview == _switchView || touch.view!.superview == _settingsView {
            return false
        }
        return true
    }
    
    @IBAction func handleSettingsButton(sender: UIButton) {
        if renderer.highQuality {
            self.performSegueWithIdentifier("settings-hq", sender: self)
        } else {
            self.performSegueWithIdentifier("settings", sender: self)
        }
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "settings" || segue.identifier == "settings-hq" {
            let nav = segue.destinationViewController as! UINavigationController
            let popover = nav.viewControllers.first as! SettingsViewController
            
            // set the navigation controller to be it's own popover presentation controller delegate
            nav.popoverPresentationController?.delegate = self

            
            // set delegates for settings communication
            popover.delegate = self
            _settingsDelegate = popover
            
            // kill the UI dismissal timer
            _uiTimer?.invalidate()
            enableUI = true
            UIView.animateWithDuration(0.5) {
                () -> Void in
                self._settingsView.tintColor = self._buttonEnabledColor
            }
        }
    }
    
    func setSwipeFunctions(orientation:UIInterfaceOrientation) {
        if (_isiPad) {
            _swipeActions[UISwipeGestureRecognizerDirection.Left.rawValue] = nextVideoFilter
            _swipeActions[UISwipeGestureRecognizerDirection.Right.rawValue] = prevVideoFilter
            _swipeActions[UISwipeGestureRecognizerDirection.Down.rawValue] = nextColorFilter
            _swipeActions[UISwipeGestureRecognizerDirection.Up.rawValue] = prevColorFilter
        } else {
            switch(orientation) {
            case .Portrait:
                _swipeActions[UISwipeGestureRecognizerDirection.Left.rawValue] = nextVideoFilter
                _swipeActions[UISwipeGestureRecognizerDirection.Right.rawValue] = prevVideoFilter
                _swipeActions[UISwipeGestureRecognizerDirection.Up.rawValue] = nextColorFilter
                _swipeActions[UISwipeGestureRecognizerDirection.Down.rawValue] = prevColorFilter
                break;
            case .PortraitUpsideDown:
                _swipeActions[UISwipeGestureRecognizerDirection.Right.rawValue] = nextVideoFilter
                _swipeActions[UISwipeGestureRecognizerDirection.Left.rawValue] = prevVideoFilter
                _swipeActions[UISwipeGestureRecognizerDirection.Down.rawValue] = nextColorFilter
                _swipeActions[UISwipeGestureRecognizerDirection.Up.rawValue] = prevColorFilter
                break;
            case .LandscapeLeft:
                _swipeActions[UISwipeGestureRecognizerDirection.Up.rawValue] = nextVideoFilter
                _swipeActions[UISwipeGestureRecognizerDirection.Down.rawValue] = prevVideoFilter
                _swipeActions[UISwipeGestureRecognizerDirection.Left.rawValue] = nextColorFilter
                _swipeActions[UISwipeGestureRecognizerDirection.Right.rawValue] = prevColorFilter
                break;
            case .LandscapeRight:
                _swipeActions[UISwipeGestureRecognizerDirection.Up.rawValue] = nextVideoFilter
                _swipeActions[UISwipeGestureRecognizerDirection.Down.rawValue] = prevVideoFilter
                _swipeActions[UISwipeGestureRecognizerDirection.Right.rawValue] = nextColorFilter
                _swipeActions[UISwipeGestureRecognizerDirection.Left.rawValue] = prevColorFilter
                break;
            default:
                break;
            }
        }
    }
    
    @IBAction func unwindSegue (segue:UIStoryboardSegue){
        if (!_isiPad) {
            _settingsDelegate = nil
            UIView.animateWithDuration(0.5) {
                () -> Void in
                self._settingsView.tintColor = UIColor.whiteColor()
            }
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
        _timer = CADisplayLink(target: self, selector: Selector("render"))
        _timer?.frameInterval = 1
        _timer?.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
        enableVideo(true)

    }
    
    func stopRenderLoop() {
        enableVideo(false)
        _timer?.invalidate()
        _timer = nil
    }
    
    func enableVideo(enable:Bool) {
        print("Video processing: \(enable)")
        
        camera.running = enable
        UIApplication.sharedApplication().idleTimerDisabled = enable
        
        _timer?.paused = !enable
        
    }
    
    func render() {
        autoreleasepool {
            self.renderview.display()
        }
    }
    
    // MARK: iCloud updating
    
    func saveDefaults() {
        // coalesce writes to the iCloud key/value store to only occure once every 2 seconds at max
        _defaultsTimer?.invalidate()
        _defaultsTimer = NSTimer(timeInterval: NSTimeInterval(2.0), target: self, selector: Selector("writeDefaults"), userInfo: nil, repeats: false)
        NSRunLoop.currentRunLoop().addTimer(_defaultsTimer!, forMode: NSDefaultRunLoopMode)
    }
    
    func writeDefaults() {
        _defaultsTimer = nil
        
        var changed:Bool = false
        
        // synchronize values in the key value store
        if _defaults.boolForKey("lock") != lock {
            _defaults.setBool(lock, forKey: "lock")
            changed = true
        }
        
        if _defaults.boolForKey("autoHideUI") != autoHideUI {
            _defaults.setBool(autoHideUI, forKey: "autoHideUI")
            changed = true
        }
        
        if _defaults.boolForKey("blur") != blur {
            _defaults.setBool(blur, forKey: "blur")
            changed = true
        }
        
        if _defaults.boolForKey("invert") != invert {
            _defaults.setBool(invert, forKey: "invert")
            changed = true
        }
        
        if camera.supportsFrontCamera {
            if _defaults.boolForKey("useFrontCamera") != frontCamera {
                _defaults.setBool(frontCamera, forKey: "useFrontCamera")
                changed = true
            }
        }
        
        if _defaults.stringForKey("videoFilter") != videoFilter {
            _defaults.setString(videoFilter, forKey: "videoFilter")
            changed = true
        }

        if _defaults.stringForKey("colorFilter") != colorFilter {
            _defaults.setString(colorFilter, forKey: "colorFilter")
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
        autoHideUI = _defaults.boolForKey("autoHideUI")
        lock = _defaults.boolForKey("lock")
        blur = _defaults.boolForKey("blur")
        invert = _defaults.boolForKey("invert")
        frontCamera = camera.supportsFrontCamera  ? _defaults.boolForKey("useFrontCamera") : false
        colorFilter = _defaults.stringForKey("colorFilter")
        videoFilter = _defaults.stringForKey("videoFilter")
    }
    
    func externalUpdate(notification:NSNotification) {
        
        
        // read in the updates
        guard let keys:NSArray = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? NSArray  else {
            return
        }
        
        // stop observing iCloud updates while we update
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NSUserDefaultsDidChangeNotification, object:nil)
  
        print("Processing updates...")
        for key in keys as! [String] {
            print("Received update for \(key)")
            switch key {
            case "lock":
                lock = _defaults.boolForKey(key)
                break;
            case "autoHideUI":
                autoHideUI = _defaults.boolForKey(key)
                break;
            case "blur":
                blur = _defaults.boolForKey(key)
                break;
            case "invert":
                invert = _defaults.boolForKey(key)
                break;
            case "useFrontCamera":
                if camera.supportsFrontCamera {
                    frontCamera = _defaults.boolForKey(key)
                }
            case "videoFilter":
                videoFilter = _defaults.stringForKey(key)
                break;
            case "colorFilter":
                colorFilter = _defaults.stringForKey(key)
                break;
            default:
                print("Unrecognized key \(key)")
                break;
            }
        }
        
        // start observing iCloud updates again
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("externalUpdate:"), name: NSUserDefaultsDidChangeNotification, object: nil)
    }
    
    // MARK: UI / Overlay Manipulation
    
    func showOverlayWithText(text:String) {
        MBProgressHUD.hideAllHUDsForView(_hudView, animated: false)
        _hudView.addSubview(_hud)
        _hud.customView = nil
        _hud.mode = .Text
        _hud.labelText = text
        _hud.show(true)
        _hud.hide(true, afterDelay: 2)
    }
    
    func showOverlayWithText(text:String, andImageView imageView:UIImageView) {
        MBProgressHUD.hideAllHUDsForView(_hudView, animated: false)
        _hudView.addSubview(_hud)
        _hud.customView = imageView
        _hud.mode = .CustomView
        _hud.labelText = text
        _hud.show(true)
        _hud.hide(true, afterDelay: 2)
    }
    
    func showLockOverlay(locked:Bool) {
        if locked {
            showOverlayWithText("Locked", andImageView: _lockedImage)
        } else {
            showOverlayWithText("Unlocked", andImageView: _unlockedImage)
        }
    }
    
    func showUI() {
        enableUI = true
        
        if (autoHideUI) {
            _uiTimer = NSTimer(timeInterval: NSTimeInterval(2.0), target: self, selector: Selector("hideUI"), userInfo: nil, repeats: false)
            NSRunLoop.currentRunLoop().addTimer(_uiTimer!, forMode: NSDefaultRunLoopMode)
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
                if _settingsView.hidden == newValue {
                    _settingsView.layer.shouldRasterize = false
                    UIView.transitionWithView(_settingsView, duration: 0.25, options: UIViewAnimationOptions.TransitionCrossDissolve,
                        animations: {
                        () -> Void in
                        self._settingsView.hidden = !newValue
                        },
                        completion: {
                        (finished:Bool) -> Void in
                            if finished { self._settingsView.layer.shouldRasterize = true }
                        }
                    )
                }
                
                let cameraEnable = camera.supportsFrontCamera ? newValue : false
                
                if cameraEnable == _switchView.hidden {
                    _switchView.layer.shouldRasterize = false

                    UIView.transitionWithView(_switchView, duration: 0.25, options: UIViewAnimationOptions.TransitionCrossDissolve,
                        animations: {
                        () -> Void in
                            self._switchView.hidden = !cameraEnable
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
    
    func setVideoFilterIndex(newFilter:Int) {
        _currentVideoFilter = newFilter
        let passes = (_videoFilters?[newFilter]["Passes"] as? [String]) ?? ["blit"]
        let blur = (_videoFilters?[newFilter]["CanUseBlur"] as? Bool) ?? true
        renderer.setVideoFilter(passes, usesBlur: blur)
        showOverlayWithText(videoFilter!, andImageView: _filterImage)
        saveDefaults()
    }
    
    func nextVideoFilter() {
        guard let vidFilter = _videoFilters  else {
            return
        }
        let newFilter = (_currentVideoFilter + 1) % vidFilter.count
        setVideoFilterIndex(newFilter)
        
    }
    
    func prevVideoFilter() {
        guard let vidFilter = _videoFilters  else {
            return
        }
        
        var newFilter = (_currentVideoFilter - 1) % vidFilter.count
        if newFilter < 0 {
            newFilter += vidFilter.count
        }
        setVideoFilterIndex(newFilter)
    }
    
    func setColorFilterIndex(newFilter:Int) {
        _currentColorFilter = newFilter
        let shaderName = (_colorFilters?[newFilter]["Shader"] as? String) ?? "yuv_rgb"
        let convolution:[Float32]
        if let param = _colorFilters?[newFilter]["Convolution"] as? [NSNumber] where param.count == 9 {
            convolution = param.map {Float32($0.floatValue)}
        } else {
            convolution = [1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,1.0]
        }
        
        renderer.setColorFilter(shaderName, convolution: convolution)
        showOverlayWithText(colorFilter!, andImageView: _colorImage)
        saveDefaults()
    }
    
    func nextColorFilter() {
        if let colorFilter = _colorFilters {
            let newFilter = (_currentColorFilter + 1) % colorFilter.count
            setColorFilterIndex(newFilter)
        }
    }
    
    func prevColorFilter() {
        if let colorFilter = _colorFilters {
            var newFilter = (_currentColorFilter - 1) % colorFilter.count
            if newFilter < 0 {
                newFilter += colorFilter.count
            }
            setColorFilterIndex(newFilter)
        }
    }
    
    // MARK: Delegate Members
    
    var videoFilter:String? {
        get {
            return _videoFilters?[_currentVideoFilter]["Name"] as? String
        }
        set {
            if let videoFilter = _videoFilters {
                for (i, filter) in videoFilter.enumerate() {
                    if let name = filter["Name"] as? String where name == newValue{
                        setVideoFilterIndex(i)
                        return;
                    }
                }
            }
            setVideoFilterIndex(0)
        }
    }
    
    var colorFilter:String? {
        get {
            return _colorFilters?[_currentColorFilter]["Name"] as? String
        }
        set {
            if let colorFilters = _colorFilters {
                for (i, filter) in colorFilters.enumerate() {
                    if let name = filter["Name"] as? String where name == newValue {
                        setColorFilterIndex(i)
                        return;
                    }
                }
            }
            setColorFilterIndex(0)
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
            UIView.animateWithDuration(0.5) {
                () -> Void in
                if (self.frontCamera){
                    self._switchView.tintColor = self._buttonEnabledColor

                } else {
                    self._switchView.tintColor = UIColor.whiteColor()
                }
            }
                
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
                    _uiTimer = NSTimer(timeInterval: NSTimeInterval(2.0), target: self, selector: Selector("hideUI"), userInfo: nil, repeats: false)
                    NSRunLoop.currentRunLoop().addTimer(_uiTimer!, forMode: NSDefaultRunLoopMode)
                }
            }
            _settingsDelegate?.setAutoHide(autoHideUI)
            saveDefaults()
        }
    }
    
    // MARK: Gesture Recognizers
    
    @IBAction func tapGestureRecognizer(sender: UITapGestureRecognizer) {
        if sender.state == .Ended && !lock {
            if _settingsView.hidden {
                showUI()
            } else {
                hideUI()
            }
        }
    }
    
    @IBAction func swipeGestureRecognizer(sender: UISwipeGestureRecognizer) {
        if sender.state == .Ended && !lock {
            _swipeActions[sender.direction.rawValue]?()
        }
    }
    @IBAction func longPressRecognizer(sender: UILongPressGestureRecognizer) {
        if sender.state == UIGestureRecognizerState.Began {
            lock = !lock
        }
    }
    
    @IBAction func switchButton(sender: AnyObject) {
        if camera.supportsFrontCamera {
            frontCamera = !frontCamera
        }
    }
    
    func popoverPresentationControllerShouldDismissPopover(popoverPresentationController: UIPopoverPresentationController) -> Bool {
        if (_isiPad) {
            _settingsDelegate = nil
            UIView.animateWithDuration(0.5) {
                () -> Void in
                self._settingsView.tintColor = UIColor.whiteColor()
            }
            saveDefaults()
            if lock {
                hideUI()
            } else {
                showUI()
            }
        }
        return true
    }
    
    func adaptivePresentationStyleForPresentationController(controller: UIPresentationController) -> UIModalPresentationStyle {
        return UIModalPresentationStyle.OverFullScreen
    }
}

