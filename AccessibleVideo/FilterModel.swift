//
//  FilterModel.swift
//  AccessibleVideo
//
//  Created by Luke Groeninger on 11/29/15.
//  Copyright © 2015 Luke Groeninger. All rights reserved.
//

import Foundation

class FilterModel {
    private var _dict:NSDictionary!
    
    init?(path:String) {
        if let dict = NSDictionary(contentsOfFile: path) {
            self._dict = dict
        } else {
            return nil
        }
    }
    subscript (element:String) -> NSArray? {
        get {
            if let result = _dict[element] as? NSArray {
                return result
            }
            return nil
        }
    }

}