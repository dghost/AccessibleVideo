//
//  FilterModel.swift
//  AccessibleVideo
//
//  Created by Luke Groeninger on 11/29/15.
//  Copyright © 2015 Luke Groeninger. All rights reserved.
//

import Foundation


class FilterModel {
    fileprivate var _dict:NSDictionary!
    
    let videoFilters:FilterManager<VideoFilter>!
    
    let inputFilters:FilterManager<InputFilter>!
    
    
    init?(path:String) {
        guard let dict = NSDictionary(contentsOfFile: path),
            let vidFilters:[[String : Any]] = dict["Video"] as? [[String : Any]],
            let inFilters:[[String : Any]] = dict["Input"] as? [[String : Any]]
            else {
                return nil
        }
        
        self._dict = dict
        videoFilters = FilterManager<VideoFilter>(filters:vidFilters)
        inputFilters = FilterManager<InputFilter>(filters:inFilters)
    }
    
    subscript (element:String) -> NSArray? {
        get {
            if let result = _dict[element] as? NSArray {
                return result
            }
            return nil
        }
    }
    
    func getVideoFilter(name:String) -> VideoFilter? {
        return videoFilters.getFilter(name: name)
    }
    
    func nextVideoFilter() -> VideoFilter? {
        return videoFilters.nextFilter()
    }
    
    func prevVideoFilter() -> VideoFilter? {
        return videoFilters.prevFilter()
    }
    
    func getInputFilter(name:String) -> InputFilter? {
        return inputFilters.getFilter(name: name)
    }
    
    func nextInputFilter() -> InputFilter? {
        return inputFilters.nextFilter()
    }
    
    func prevInputFilter() -> InputFilter? {
        return inputFilters.prevFilter()
        
    }
}

class InputFilter: FilterProtocol {
    let name:String
    let shaderName:String
    let convolution:[Float32]
    
    required init()
    {
        name="Invalid Filter"
        shaderName = "yuv_rgb"
        convolution = [1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,1.0]
    }
    
    required init?(filterDef: [String : Any])
    {
        guard let newName = filterDef["Name"] as? String
            else {
                return nil
        }
        
        name = newName

        shaderName = filterDef["Shader"] as? String ?? "yuv_rgb"
        if let param = filterDef["Convolution"] as? [NSNumber], param.count == 9
        {
            convolution = param.map {Float32($0.floatValue)}
        } else {
            convolution = [1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,1.0]
        }
    }
}


class VideoFilter: FilterProtocol {
    let name:String
    let canBlur:Bool
    let passes:[String]
    
    required init()
    {
        name="Invalid Filter"
        canBlur=false
        passes=["blit"]
    }
    
    required init?(filterDef: [String : Any])
    {
        guard let newName = filterDef["Name"] as? String
            else {
                return nil
        }
        name = newName
        canBlur = filterDef["CanUseBlur"] as? Bool ?? false
        passes = filterDef["Passes"] as? [String] ?? ["blit"]
    }
}

protocol FilterProtocol {
    var name:String { get }
    init()
    init?(filterDef: [String : Any])
}


class FilterManager<T:FilterProtocol>
{
    let _filterArray:[T]!
    let _filterMap:[String:T]!
    var _currentFilter:Int = 0
    
    init(filters: [[String : Any]])
    {
        var filterArray:[T] = []
        var filterMap:[String:T] = [:]

        filterArray.reserveCapacity(filters.count)
        for filter in filters
        {
            if let newFilter = T(filterDef: filter)
            {
                print("Loaded definition for filter \(newFilter.name)")

                filterArray.append(newFilter)
                filterMap[newFilter.name] = newFilter
            } else {
                print("Error instantiating malformed filter \(String(describing: filter["Name"]))")
            }
        }
        
        if filterArray.count == 0 {
            let emptyFilter = T()
            filterArray.append(emptyFilter)
            filterMap[emptyFilter.name] = emptyFilter
        }
        
        _filterArray = filterArray
        _filterMap = filterMap
    }
    
    func getFilter(name:String) -> T? {
        if let filter = _filterMap[name]
        {
            return filter
        }
        return nil
    }
    
    func setFilter(name:String) {
        if let index = _filterArray.index(where: { $0.name == name }) {
            _currentFilter = index
        }
    }
    
    func nextFilter() -> T? {
        guard _filterArray.count > 0 else {
            return nil
        }
        
        _currentFilter = (_currentFilter + 1) % _filterArray.count
        return _filterArray[_currentFilter]
    }
    
    func prevFilter() -> T? {
        guard _filterArray.count > 0 else {
            return nil
        }
        
        _currentFilter = (_currentFilter - 1) % _filterArray.count
        if _currentFilter < 0 {
            _currentFilter += _filterArray.count
        }
        return _filterArray[_currentFilter]
    }
}

