//
//  SettingsViewController.swift
//  AccessibleVideo
//
//  Created by Luke Groeninger on 11/9/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//

import UIKit

protocol SettingsViewDelegate {
    func setBlur(on:Bool)
    func setAutoHide(on:Bool)
    func setInvert(on:Bool)
}

class SettingsViewController: UIViewController, SettingsViewDelegate {

    var delegate:ControlsDelegate! = nil

    @IBOutlet weak var blurSwitch: UISwitch!
    
    @IBOutlet weak var autoHideSwitch: UISwitch!
    
    @IBOutlet weak var invertSwitch: UISwitch!
    
    lazy private var _isiPad:Bool = (UIDevice.currentDevice().userInterfaceIdiom == .Pad)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if !_isiPad {
            let barButton = UIBarButtonItem(title: "Done", style: .Done, target: self, action: "unwind")
            self.navigationItem.rightBarButtonItem = barButton
        }
        // Do any additional setup after loading the view.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewWillAppear(animated: Bool) {
        blurSwitch.setOn(delegate.blur, animated: false)
        autoHideSwitch.setOn(delegate.autoHideUI, animated: false)
        invertSwitch.setOn(delegate.invert, animated: false)
    }
    
    func setBlur(on: Bool) {
        if blurSwitch.on != on {
            blurSwitch.setOn(on, animated: true)
        }
    }
    
    @IBAction func handleBlur   (sender: UISwitch!) {
        if delegate.blur != blurSwitch.on {
            delegate.blur = blurSwitch.on
        }
    }
    
    func setAutoHide(on: Bool) {
        if autoHideSwitch.on != on {
            autoHideSwitch.setOn(on, animated: true)
        }
    }
    
    @IBAction func handleAutoHideUI(sender: UISwitch) {
        if delegate.autoHideUI != autoHideSwitch.on {
            delegate.autoHideUI = autoHideSwitch.on
        }
    }
    
    func setInvert(on: Bool) {
        if invertSwitch.on != on {
            invertSwitch.setOn(on, animated: true)
        }
    }
    
    @IBAction func handleInvertUI(sender: AnyObject) {
        if delegate.invert != invertSwitch.on {
            delegate.invert = invertSwitch.on
        }
    }
    
    func unwind() {
        self.performSegueWithIdentifier("unwind", sender: self)
    }

}
