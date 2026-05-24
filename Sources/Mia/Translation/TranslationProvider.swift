import Foundation

// MARK: - Translation Event

enum TranslationEvent {
    /// A partial (streaming) translation result — may be updated.
    case partial(text: String, language: String, isFinal: Bool)
    /// An audio chunk from TTS (raw PCM float32 mono samples).
    case audioChunk([Float])
    /// Utterance boundary detected — start/end of a sentence.
    case utteranceEnd
    /// Error from the provider.
    case error(String)
}

// MARK: - Provider Protocol

protocol TranslationProvider: AnyObject, Sendable {
    /// Connect to the translation service.
    func connect(inputLanguage: String, outputLanguage: String, sampleRate: Double) async throws

    /// Send raw PCM float32 mono audio samples.
    func sendAudio(_ samples: [Float]) async throws

    /// Stream of translation events (text translations + TTS audio chunks).
    func events() -> AsyncStream<TranslationEvent>

    /// Close the connection gracefully.
    func disconnect() async
}

// MARK: - Translation Event Stream

final class TranslationEventStream: @unchecked Sendable {
    private var continuation: AsyncStream<TranslationEvent>.Continuation?

    func makeStream() -> AsyncStream<TranslationEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func yield(_ event: TranslationEvent) {
        continuation?.yield(event)
    }

    func finish() {
        continuation?.finish()
    }
}

// MARK: - Base WebSocket class shared by providers

final class WebSocketConnection: NSObject, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.mia.websocket", qos: .userInitiated)
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var _isConnected = false

    var isConnected: Bool {
        queue.sync { _isConnected }
    }

    var onMessage: ((URLSessionWebSocketTask.Message) -> Void)?
    var onClose: ((String?) -> Void)?

    func connect(to url: URL, headers: [String: String], verifyWithPing: Bool = true) async throws {
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.timeoutInterval = 30

        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:]
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        task = session?.webSocketTask(with: request)
        task?.resume()

        if verifyWithPing {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                task?.sendPing { error in
                    if let error = error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume()
                    }
                }
            }
        }

        _isConnected = true
        receiveNext()
    }

    func sendText(_ text: String) async throws {
        try await task?.send(.string(text))
    }

    func sendData(_ data: Data) async throws {
        try await task?.send(.data(data))
    }

    func close() {
        task?.cancel(with: .normalClosure, reason: nil)
        _isConnected = false
    }

    private func receiveNext() {
        task?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.onMessage?(message)
                self?.receiveNext()
            case .failure(let error):
                self?._isConnected = false
                self?.onClose?(error.localizedDescription)
            }
        }
    }
}

extension WebSocketConnection: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        _isConnected = false
        var message: String?
        if let reason = reason, let text = String(data: reason, encoding: .utf8) {
            message = text
        }
        onClose?(message ?? "WebSocket 关闭 (code: \(closeCode.rawValue))")
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        _isConnected = false
        onClose?(error.localizedDescription)
    }
}
