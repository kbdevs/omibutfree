//
//  MapUtils.swift
//  awesome_notifications
//
//  Created by Rafael Setragni on 05/09/20.
//

import Foundation

public class MapUtils<T: Any> {
    
    public static func isNullOrEmptyKey(map: [String : Any?], key: String) -> Bool {

        if(map.isEmpty) { return true }

        let value:Any? = map[key] ?? nil

        if(value == nil) { return true }

        if (value is String){
            if((value as! String).isEmpty) { return true }
        }
        else if (value is [String : Any?]){
            if((value as! [String : Any?]).isEmpty) { return true }
        }

        return false
    }

    public static func getValueOrDefault(reference: String, arguments: [String : Any?]?) -> T? {
        let value:Any? = arguments?[reference] ?? nil
        let defaultValue:T? = Definitions.initialValues[reference] as? T
        
        if(value == nil) { return defaultValue }
        
        if(T.self == Int.self){
            return IntUtils.convertToInt(value: value) as? T
        }
        
        if(T.self == Float.self){
            return FloatUtils.convertToFloat(value: value) as? T
        }

        if(T.self == Double.self){
            return DoubleUtils.convertToDouble(value: value) as? T
        }
        
        if(T.self == TimeZone.self){
            if let identifier = value as? String {
                return TimeZoneUtils
                    .shared
                    .getValidTimeZone(
                        fromTimeZoneId: identifier) as? T
            }
        }
                
        if(T.self == [String].self) {
            return extractStringListFromValue(value) as? T
        }
        
        if(value is T) { return value as? T }
        
        if (value as AnyObject).isEmpty ?? false {
            return defaultValue
        }
        
        return defaultValue
    }
    
    public static func extractStringListFromValue(_ value:Any?) -> [String]? {
        if value is [String] { return value as? [String] }
        if let stringValue = value as? String {
            // JSON-encoded string list
            if let list:[String] = JsonUtils.fromJsonList(stringValue) {
                return list
            }
            // Comma-separated string
            let list = stringValue.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            return list
        }
        return nil
    }
    
    public static func getRealDateOrDefault(reference: String, arguments: [String : Any?]?, defaultTimeZone:TimeZone) -> RealDateTime? {
        let defaultValue:RealDateTime? = Definitions.initialValues[reference] as? RealDateTime
        
        guard let value:String = arguments?[reference] as? String
        else { return defaultValue }
                
        if(T.self == RealDateTime.self){
            return RealDateTime(
                fromDateText: value,
                defaultTimeZone: defaultTimeZone
            )
        }
        
        return defaultValue
    }
    
    public static func deepMerge(_ originalMap:[String:Any?], _ newMap:[String:Any?]) -> [String:Any?]{
        var result = originalMap
        for (key, newValue) in newMap {
            if let newValue = newValue as? [String: Any?],
               let existingValue = result[key] as? [String: Any?] {
                result[key] = deepMerge(existingValue, newValue)
            } else {
                result[key] = newValue
            }
        }
        return result
    }
}
