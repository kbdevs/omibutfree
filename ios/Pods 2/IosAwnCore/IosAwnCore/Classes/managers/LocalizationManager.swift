//
//  LocalizationManager.swift
//  IosAwnCore
//
//  Created by Rafael Setragni on 18/02/23.
//

import Foundation

class LocalizationManager {
    static let shared = LocalizationManager()
    
    let _userDefaults = UserDefaults(suiteName: Definitions.USER_DEFAULT_TAG)
    let localizationKey = "awn_localization_languageCode"
    
    func setLocalization(languageCode: String? = nil) -> Bool {
        
        guard let userDefaults = _userDefaults ?? UserDefaults(suiteName: Definitions.USER_DEFAULT_TAG)
        else { return false }
        
        let langCode =
            (languageCode ?? Locale.preferredLanguages[0])
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")
        
        userDefaults.set(langCode, forKey: localizationKey)
        
        return true
    }
    
    func getLocalization() -> String {
        let appLangCode = Locale.preferredLanguages[0]
        let awnLangCode = _userDefaults?.string(forKey: localizationKey)
        return (awnLangCode ?? appLangCode)
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")
    }
}
