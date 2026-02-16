import Foundation
import AVFoundation

class MicrophoneService: NSObject, ObservableObject {
    static let shared = MicrophoneService()
    
    @Published var audioData: Data = Data()
    @Published var isRecording: Bool = false
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    
    override init() {
        super.init()
    }
    
    func requestPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    func startRecording() async {
        guard !isRecording else { return }
        
        let granted = await requestPermission()
        guard granted else { return }
        
        audioEngine = AVAudioEngine()
        inputNode = audioEngine?.inputNode
        
        guard let inputNode = inputNode else { return }
        
        let format = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let data = self?.convertBufferToData(buffer) else { return }
            DispatchQueue.main.async {
                self?.audioData.append(data)
            }
        }
        
        do {
            try audioEngine?.start()
            isRecording = true
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    func stopRecording() async {
        guard isRecording else { return }
        
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        isRecording = false
    }
    
    private func convertBufferToData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map { channelDataValue[$0] }
        return Data(bytes: channelDataValueArray, count: channelDataValueArray.count * MemoryLayout<Float>.size)
    }
}
