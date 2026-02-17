import Foundation
import AVFoundation

class OpusDecoderService {
    private var isInitialized = false
    
    func initialize() async {
        isInitialized = true
    }
    
    func decode(_ opusData: Data) -> Data? {
        guard isInitialized else { return nil }
        
        return opusData
    }
    
    func dispose() {
        isInitialized = false
    }
}
