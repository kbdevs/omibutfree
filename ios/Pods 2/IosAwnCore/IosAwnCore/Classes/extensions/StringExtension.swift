
import CommonCrypto

extension String {
    
    public func charAt(_ pos:Int) -> Character {
        if(pos < 0 || pos >= count) { return Character("") }
        return Array(self)[pos]
    }
    
    public func index(from: Int) -> Index {
        return self.index(startIndex, offsetBy: from)
    }
    
    public func indexOf(_ char: Character) -> Int? {
       return firstIndex(of: char)?.utf16Offset(in: self)
    }

    public func substring(from: Int) -> String {
        let fromIndex = index(from: from)
        return String(self[fromIndex...])
    }

    public func substring(_ from: Int,_ until: Int) -> String? {
        let fromIndex = index(from: from)
        let untilIndex = index(from: until)
        return String(self[fromIndex..<untilIndex])
    }
    
    public func indexOf(_ char: Character, offsetBy:Int) -> Int? {
        return substring(from: offsetBy).firstIndex(of: char)?.utf16Offset(in: self)
    }
    
    public var isDigits: Bool {
        let notDigits = NSCharacterSet.decimalDigits.inverted
        return rangeOfCharacter(from: notDigits, options: String.CompareOptions.literal, range: nil) == nil
    }
    
    public var isLetters: Bool {
        let notLetters = NSCharacterSet.letters.inverted
        return rangeOfCharacter(from: notLetters, options: String.CompareOptions.literal, range: nil) == nil
    }
    
    public var isAlphanumeric: Bool {
        let notAlphanumeric = NSCharacterSet.decimalDigits.union(NSCharacterSet.letters).inverted
        return rangeOfCharacter(from: notAlphanumeric, options: String.CompareOptions.literal, range: nil) == nil
    }
    
    public func matches(_ regex: String) -> Bool {
        let range = NSRange(location: 0, length: self.utf16.count)
        let regex = try! NSRegularExpression(pattern: regex, options: .caseInsensitive)
        return regex.firstMatch(in: self, options: [], range: range) != nil
    }
    
    public func matchList(_ regex: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: regex, options: []) else { return [] }
        let nsString = self as NSString
        let results  = regex.matches(in: self, options: [], range: NSMakeRange(0, nsString.length))
        return results.map { result in
            (0..<result.numberOfRanges).map {
                result.range(at: $0).location != NSNotFound
                    ? nsString.substring(with: result.range(at: $0))
                    : ""
            }
        }
    }

    public mutating func replaceRegex(_ pattern: String, replaceWith: String = "") -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: NSRegularExpression.Options.caseInsensitive)
            let range = NSMakeRange(0, self.count)
            self = regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: replaceWith)
            return true
        } catch {
            return false
        }
    }

    public func withoutHtmlTags() -> String {
        return self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
    }
    
    public func htmlToRichText() -> NSAttributedString? {
        guard let data = self.data(using: String.Encoding.unicode) else { return nil }

        guard let converted = try? NSAttributedString(
            data: data,
            options: [.documentType:NSAttributedString.DocumentType.html],
            documentAttributes: nil
        )
        else { return nil }
        
        return converted
    }
    
    public func toDate(_ format: String = "yyyy-MM-dd HH:mm:ss", fromTimeZone timeZone:String?)-> Date? {
        
        let dateFormatter = DateFormatter()
        guard let timeZone:TimeZone = timeZone == nil ? TimeZone.autoupdatingCurrent : TimeZone(identifier: timeZone!)
        else { return nil }
        
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = Definitions.DATE_FORMAT

        return dateFormatter.date(from: self)
    }

    public func split(regex pattern: String) -> [String] {

        guard let re = try? NSRegularExpression(pattern: pattern, options: [])
            else { return [] }

        let nsString = self as NSString // needed for range compatibility
        let stop = "<SomeStringThatYouDoNotExpectToOccurInSelf>"
        let modifiedString = re.stringByReplacingMatches(
            in: self,
            options: [],
            range: NSRange(location: 0, length: nsString.length),
            withTemplate: stop)
        return modifiedString.components(separatedBy: stop)
    }
    
    func localized(forLanguageCode languageCode: String) -> String? {
        let formattedLanguageCode = formatLanguageCode(languageCode)

        // Try with the full language code first (e.g., "en-US")
        if let path = Bundle.main.path(forResource: formattedLanguageCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return NSLocalizedString(self, bundle: bundle, comment: "")
        }

        // If not found, try with only the language part (e.g., "en")
        let primaryLanguageCode = onlyFirstLanguageCode(formattedLanguageCode)
        if let path = Bundle.main.path(forResource: primaryLanguageCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return NSLocalizedString(self, bundle: bundle, comment: "")
        }

        return nil // Return nil if no localization is found
    }
    
    private func formatLanguageCode(_ code: String) -> String {
        let parts = code.split(separator: "-")
        var formattedCode = parts[0].lowercased()

        if parts.count > 1 {
            formattedCode += "-" + parts[1].uppercased()
        }

        return formattedCode
    }
    
    private func onlyFirstLanguageCode(_ code: String) -> String {
        let parts = code.split(separator: "-")
        return parts[0].lowercased()
    }
    
    var md5: String {
        let data = Data(self.utf8)
        let hash = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [UInt8] in
            var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            CC_MD5(bytes.baseAddress, CC_LONG(data.count), &hash)
            return hash
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
