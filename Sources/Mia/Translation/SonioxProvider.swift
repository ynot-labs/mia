import Foundation

/// Soniox provider: chains real-time STT + Translation WebSocket
/// with real-time TTS WebSocket for speech-to-speech translation.
///
/// Architecture (differs from OpenAI's single-WS approach):
///   WebSocket 1 (STT+Translation): receives audio, returns text + translation tokens
///   WebSocket 2 (TTS):            receives translated text, returns binary audio
///
/// The provider bridges them: translation tokens from WS1 → text input to WS2.
///
/// WebSocket 1: wss://stt-rt.soniox.com/transcribe-websocket
/// WebSocket 2: wss://tts-rt.soniox.com/tts-websocket
final class SonioxProvider: TranslationProvider, @unchecked Sendable {
    private let apiKey: String
    private var sttConnection: WebSocketConnection?
    private var ttsConnection: WebSocketConnection?
    private let eventStream = TranslationEventStream()
    private var ttsStreamID = UUID().uuidString
    private var ttsReady = false
    private var currentUtteranceText = ""
    static let voices = [
        "Adrian", "Claire", "Daniel", "Emma", "Grace", "Jack",
        "Kenji", "Maya", "Mina", "Nina", "Noah", "Owen",
    ]

    private let ttsVoice: String

    init(apiKey: String, voice: String) {
        self.apiKey = apiKey
        self.ttsVoice = voice
    }

    // MARK: - TranslationProvider

    func connect(inputLanguage: String, outputLanguage: String, sampleRate: Double) async throws {
        inputLanguageFallback = inputLanguage
        currentOutputLanguage = outputLanguage

        // 1. Open STT + Translation WebSocket
        sttConnection = WebSocketConnection()
        guard let sttURL = URL(string: "wss://stt-rt.soniox.com/transcribe-websocket") else {
            throw ProviderError.invalidURL
        }

        try await sttConnection?.connect(to: sttURL, headers: [
            "Authorization": "Bearer \(apiKey)"
        ], verifyWithPing: false)

        let sttConfig: [String: Any] = [
            "api_key": apiKey,
            "model": "stt-rt-v4",
            "audio_format": "pcm_s16le",
            "sample_rate": Int(sampleRate),
            "num_channels": 1,
            "enable_endpoint_detection": true,
            "max_endpoint_delay_ms": 500,
            "translation": [
                "type": "one_way",
                "target_language": outputLanguage
            ]
        ]
        let sttConfigJSON = try JSONSerialization.data(withJSONObject: sttConfig)
        let sttConfigString = String(data: sttConfigJSON, encoding: .utf8)!
        try await sttConnection?.sendText(sttConfigString)

        sttConnection?.onMessage = { [weak self] message in
            Task { [weak self] in await self?.handleSTTMessage(message) }
        }
        sttConnection?.onClose = { [weak self] reason in
            Task { [weak self] in
                self?.eventStream.yield(.error("STT 连接断开: \(reason ?? "未知原因")"))
            }
        }

    }

    func events() -> AsyncStream<TranslationEvent> {
        eventStream.makeStream()
    }

    func sendAudio(_ samples: [Float]) async throws {
        guard let conn = sttConnection else { return }

        // Convert float32 → int16 to match Soniox pcm_s16le format.
        // Reference: soniox_examples/speech_to_text/python/soniox_realtime.py
        let int16Samples = samples.map { Int16(max(-32768, min(32767, $0 * 32767.0))) }
        let data = int16Samples.withUnsafeBufferPointer { Data(buffer: $0) }
        try await conn.sendData(data)
    }

    func disconnect() async {
        // Signal end-of-audio with empty text frame (per Soniox spec)
        if let conn = sttConnection {
            try? await conn.sendText("")
        }
        sttConnection?.close()
        ttsConnection?.close()
        eventStream.finish()
        sttConnection = nil
        ttsConnection = nil
        ttsReady = false
    }

    // MARK: - STT message handler

    private func handleSTTMessage(_ message: URLSessionWebSocketTask.Message) async {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            if case .string(let raw) = message, raw.lowercased().contains("error") {
                eventStream.yield(.error("Soniox STT: \(raw)"))
            }
            return
        }

        // Check for server-level errors
        if let error = json["error"] as? String {
            eventStream.yield(.error("Soniox STT: \(error)"))
            return
        }
        if let detail = json["detail"] as? String {
            eventStream.yield(.error("Soniox STT: \(detail)"))
            return
        }
        if let errorMessage = json["error_message"] as? String {
            eventStream.yield(.error("Soniox STT: \(errorMessage)"))
            return
        }

        // Soniox STT returns a "tokens" array with per-token fields:
        //   text, is_final, confidence, language, translation_status, source_language
        guard let tokens = json["tokens"] as? [[String: Any]], !tokens.isEmpty else { return }

        // Separate original and translation tokens
        let translationTokens = tokens.filter {
            ($0["translation_status"] as? String) == "translation"
        }
        let originalTokens = tokens.filter {
            let status = $0["translation_status"] as? String ?? "original"
            return status != "translation"
        }

        // Build translated text by concatenating translation tokens
        let translatedText = translationTokens.compactMap { $0["text"] as? String }.joined()
        let originalText = originalTokens.compactMap { $0["text"] as? String }.joined()

        // Check if the utterance is final (all tokens are final)
        let allFinal = tokens.allSatisfy { ($0["is_final"] as? Bool) ?? false }
        let lang = tokens.first?["language"] as? String

        if !translatedText.isEmpty {
            eventStream.yield(.partial(
                text: translatedText,
                language: lang ?? currentOutputLanguage,
                isFinal: allFinal
            ))

            if allFinal {
                eventStream.yield(.utteranceEnd)
                flushTTS()
            } else {
                sendTextToTTS(translatedText)
            }
        } else if !originalText.isEmpty, allFinal {
            eventStream.yield(.partial(
                text: "[\(lang ?? inputLanguageFallback)] \(originalText)",
                language: lang ?? inputLanguageFallback,
                isFinal: true
            ))
        }
    }

    // MARK: - TTS message handler

    private func handleTTSMessage(_ message: URLSessionWebSocketTask.Message) async {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }

            // Server-level error
            if let error = json["error_message"] as? String {
                eventStream.yield(.error("Soniox TTS: \(error)"))
                return
            }
            if let error = json["error"] as? String {
                eventStream.yield(.error("Soniox TTS: \(error)"))
                return
            }

            // Audio comes as base64-encoded PCM in JSON: {"audio": "<base64>"}
            if let audioB64 = json["audio"] as? String,
               let audioData = Data(base64Encoded: audioB64) {
                let samples = audioData.withUnsafeBytes { ptr -> [Float] in
                    let count = audioData.count / MemoryLayout<Float>.stride
                    return ptr.withMemoryRebound(to: Float.self) { Array($0.prefix(count)) }
                }
                if !samples.isEmpty {
                    eventStream.yield(.audioChunk(samples))
                }
            }

            // Session terminated
            if json["terminated"] as? Bool == true {
                ttsReady = false
                ttsConnection = nil
                eventStream.yield(.utteranceEnd)
            }

        case .data:
            break // TTS doesn't send binary frames

        @unknown default:
            break
        }
    }

    // MARK: - Bridging: STT translation → TTS input

    private func sendTextToTTS(_ text: String) {
        currentUtteranceText = text

        Task {
            // Lazy-connect TTS on first text to avoid server timeout between
            // config and first text message (Soniox TTS requires text immediately
            // after the start/config message).
            if !ttsReady || ttsConnection == nil {
                await connectTTS()
            }
            guard ttsReady, let conn = ttsConnection else { return }

            let msg: [String: Any] = ["text": text, "stream_id": ttsStreamID, "text_end": false]
            let jsonData = try JSONSerialization.data(withJSONObject: msg)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            try await conn.sendText(jsonString)
        }
    }

    private func flushTTS() {
        guard ttsReady, let conn = ttsConnection else { return }
        currentUtteranceText = ""

        Task {
            let msg: [String: Any] = ["text": "", "stream_id": ttsStreamID, "text_end": true]
            let jsonData = try JSONSerialization.data(withJSONObject: msg)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            try await conn.sendText(jsonString)
        }
        // Reset for next utterance — new TTS stream will be created
        ttsReady = false
        ttsConnection = nil
        // New stream ID for the next utterance (refreshed in connectTTS)
        ttsStreamID = UUID().uuidString
    }

    private func connectTTS() async {
        do {
            let ttsConn = WebSocketConnection()
            guard let ttsURL = URL(string: "wss://tts-rt.soniox.com/tts-websocket") else { return }

            try await ttsConn.connect(to: ttsURL, headers: [
                "Authorization": "Bearer \(apiKey)"
            ], verifyWithPing: false)

            ttsStreamID = UUID().uuidString

            let ttsConfig: [String: Any] = [
                "api_key": apiKey,
                "stream_id": ttsStreamID,
                "model": "tts-rt-v1",
                "language": currentOutputLanguage,
                "voice": ttsVoice,
                "audio_format": "pcm_f32le"
            ]
            let ttsConfigJSON = try JSONSerialization.data(withJSONObject: ttsConfig)
            let ttsConfigString = String(data: ttsConfigJSON, encoding: .utf8)!
            try await ttsConn.sendText(ttsConfigString)

            ttsConnection = ttsConn
            ttsReady = true
            ttsConn.onMessage = { [weak self] message in
                Task { [weak self] in await self?.handleTTSMessage(message) }
            }
            ttsConn.onClose = { [weak self] reason in
                Task { [weak self] in
                    self?.ttsReady = false
                    self?.eventStream.yield(.error("TTS 连接断开: \(reason ?? "未知原因")"))
                }
            }
        } catch {
            eventStream.yield(.error("TTS 连接失败: \(error.localizedDescription)"))
        }
    }

    // MARK: - Private

    private var inputLanguageFallback = ""
    private var currentOutputLanguage = "en"

    enum ProviderError: Error, LocalizedError {
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "无效的 Soniox API URL"
            }
        }
    }
}
