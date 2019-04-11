//
//  SettingsViewController.swift
//  AccessibleVideo
//
//  Created by Luke Groeninger on 11/9/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//

import UIKit

protocol SettingsViewDelegate {
    func setBlur(_ on:Bool)
    func setAutoHide(_ on:Bool)
    func setInvert(_ on:Bool)
}

class SettingsViewController: UIViewController, SettingsViewDelegate {

    var delegate:ControlsDelegate! = nil

    @IBOutlet weak var blurSwitch: UISwitch!
    
    @IBOutlet weak var autoHideSwitch: UISwitch!
    
    @IBOutlet weak var invertSwitch: UISwitch!
    
    lazy fileprivate var _isiPad:Bool = (UIDevice.current.userInterfaceIdiom == .pad)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if !_isiPad {
            let barButton = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(SettingsViewController.performUnwind))
            self.navigationItem.rightBarButtonItem = barButton
        }
        // Do any additional setup after loading the view.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        blurSwitch.setOn(delegate.blur, animated: false)
        autoHideSwitch.setOn(delegate.autoHideUI, animated: false)
        invertSwitch.setOn(delegate.invert, animated: false)
    }
    
    func setBlur(_ on: Bool) {
        if blurSwitch.isOn != on {
            blurSwitch.setOn(on, animated: true)
        }
    }
    
    @IBAction func handleBlur   (_ sender: UISwitch!) {
        if delegate.blur != blurSwitch.isOn {
            delegate.blur = blurSwitch.isOn
        }
    }
    
    func setAutoHide(_ on: Bool) {
        if autoHideSwitch.isOn != on {
            autoHideSwitch.setOn(on, animated: true)
        }
    }
    
    @IBAction func handleAutoHideUI(_ sender: UISwitch) {
        if delegate.autoHideUI != autoHideSwitch.isOn {
            delegate.autoHideUI = autoHideSwitch.isOn
        }
    }
    
    func setInvert(_ on: Bool) {
        if invertSwitch.isOn != on {
            invertSwitch.setOn(on, animated: true)
        }
    }
    
    @IBAction func handleInvertUI(_ sender: AnyObject) {
        if delegate.invert != invertSwitch.isOn {
            delegate.invert = invertSwitch.isOn
        }
    }
    
    @objc func performUnwind() {
        self.performSegue(withIdentifier: "unwind", sender: self)
    }

}
