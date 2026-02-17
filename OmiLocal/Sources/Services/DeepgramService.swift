import Foundation

class DeepgramService: NSObject {
    let apiKey: String
    let language: String
    var onTranscript: (([TranscriptSegment]) -> Void)?
    var onError: ((Error) -> Void)?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false
    
    init(apiKey: String, language: String = "en", encoding: String = "opus", sampleRate: Int = 16000) {
        self.apiKey = apiKey
        self.language = language
        super.init()
    }
    
    func connect() async throws {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "Deepgram", code: 1, userInfo: [NSLocalizedDescriptionKey: "API key required"])
        }
        
        let urlString = "wss://api.deepgram.com/v1/listen?language=\(language)&encoding=opus&sample_rate=16000&model=nova-2"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Deepgram", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        webSocketTask = urlSession?.webSocketTask(with: request)
        
        webSocketTask?.resume()
        isConnected = true
        
        receiveMessage()
    }
    
    func sendAudio(_ audioData: Data) {
        guard isConnected else { return }
        
        let base64Audio = audioData.base64EncodedString()
        let message = URLSessionWebSocketTask.Message.string(base64Audio)
        
        webSocketTask?.send(message) { error in
            if let error = error {
                print("Deepgram send error: \(error)")
            }
        }
    }
    
    func disconnect() {
        isConnected = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleTranscript(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleTranscript(text)
                    }
                @unknown default:
                    break
                }
                self?.receiveMessage()
                
            case .failure(let error):
                self?.onError?(error)
            }
        }
    }
    
    private func handleTranscript(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let channels = results["channels"] as? [[String: Any]],
              let firstChannel = channels.first,
              let alternatives = firstChannel["alternatives"] as? [[String: Any]],
              let firstAlt = alternatives.first,
              let transcript = firstAlt["transcript"] as? String,
              !transcript.isEmpty else {
            return
        }
        
        let isFinal = (json["is_final"] as? Bool) ?? true
        
        if isFinal {
            let segment = TranscriptSegment(
                text: transcript,
                speakerId: 0,
                startTime: 0,
                endTime: 0,
                isUser: false
            )
            onTranscript?([segment])
        }
    }
}

extension DeepgramService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("Deepgram WebSocket connected")
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("Deepgram WebSocket closed: \(closeCode)")
        isConnected = false
    }
}
