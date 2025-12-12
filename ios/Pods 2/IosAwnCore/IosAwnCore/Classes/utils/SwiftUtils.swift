//
//  SwiftUtils.swift
//  Pods
//
//  Created by Rafael Setragni on 16/10/20.
//

import Foundation
public class SwiftUtils{
    
    private static var _isExtension:Bool?
    
    public static func isRunningOnExtension() -> Bool {
        if _isExtension == nil {
            _isExtension = Bundle.main.bundlePath.hasSuffix(".appex")
        }
        return _isExtension!
    }
    
    public static func getMainBundle() -> Bundle {
        var components = Bundle.main.bundleURL.path.split(separator: "/")
        var bundle: Bundle?

        if let index = components.lastIndex(where: { $0.hasSuffix(".app") }) {
            components.removeLast((components.count - 1) - index)
            bundle = Bundle(path: components.joined(separator: "/"))
        }

        return bundle ?? Bundle.main
    }
    
    public static func getFlutterAssetPath(forAsset assetPath:String) -> String? {
        let realPath = getMainBundle().bundlePath + "/Frameworks/App.framework/flutter_assets/" + assetPath
        return realPath
    }
}
