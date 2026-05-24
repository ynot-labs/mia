import Foundation

/// OpenAI Realtime API provider: single WebSocket connection handles
/// STT, translation, and TTS together.
///
/// WebSocket: wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview
final class OpenAIProvider: TranslationProvider, @unchecked Sendable {
    private let apiKey: String
    private var connection: WebSocketConnection?
    private let eventStream = TranslationEventStream()
    private var inputLanguage = "zh"
    private var outputLanguage = "en"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func connect(inputLanguage: String, outputLanguage: String, sampleRate: Double) async throws {
        self.inputLanguage = inputLanguage
        self.outputLanguage = outputLanguage

        connection = WebSocketConnection()
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview") else {
            throw ProviderError.invalidURL
        }

        try await connection?.connect(to: url, headers: [
            "Authorization": "Bearer \(apiKey)",
            "OpenAI-Beta": "realtime=v1"
        ])

        // Configure session for translation
        let instructions = """
        You are a real-time translator. Translate speech from \(inputLanguage) to \(outputLanguage).
        Translate directly without adding explanations, commentary, or extra text.
        Output ONLY the translated text. Keep the translation natural and conversational.
        Respond to every user audio input with the translated text.
        """

        let sessionConfig: [String: Any] = [
            "type": "session.update",
            "session": [
                "modalities": ["text", "audio"],
                "instructions": instructions,
                "voice": "alloy",
                "input_audio_format": [
                    "type": "pcm16",
                    "sample_rate": 24000
                ],
                "output_audio_format": [
                    "type": "pcm16",
                    "sample_rate": 24000
                ],
                "input_audio_transcription": [
                    "enabled": true,
                    "model": "whisper-1"
                ],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.5,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 500
                ],
                "temperature": 0.6
            ]
        ]

        let configData = try JSONSerialization.data(withJSONObject: sessionConfig)
        try await connection?.sendData(configData)

        // Listen for responses
        connection?.onMessage = { [weak self] message in
            Task { [weak self] in
                await self?.handleMessage(message)
            }
        }
    }

    func events() -> AsyncStream<TranslationEvent> {
        eventStream.makeStream()
    }

    func sendAudio(_ samples: [Float]) async throws {
        guard let conn = connection else { return }

        // Convert float32 [-1.0, 1.0] to int16 PCM
        let int16Data = samplesToInt16(samples)
        let base64 = int16Data.base64EncodedString()

        let message: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: message)
        try await conn.sendData(jsonData)
    }

    func disconnect() async {
        connection?.close()
        eventStream.finish()
        connection = nil
    }

    // MARK: - Message handling

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            handleEvent(json)

        case .data(let data):
            // Binary data from OpenAI Realtime is typically audio
            handleBinaryAudio(data)

        @unknown default:
            break
        }
    }

    private func handleEvent(_ json: [String: Any]) {
        let type = json["type"] as? String ?? ""

        switch type {
        case "response.audio_transcript.delta":
            // Streaming translated text
            let delta = json["delta"] as? String ?? ""
            let responseId = json["response_id"] as? String ?? ""
            if !delta.isEmpty {
                eventStream.yield(.partial(
                    text: delta,
                    language: outputLanguage,
                    isFinal: false
                ))
            }

        case "response.audio_transcript.done":
            // Final transcript for this turn
            let transcript = json["transcript"] as? String ?? ""
            if !transcript.isEmpty {
                eventStream.yield(.partial(
                    text: transcript,
                    language: outputLanguage,
                    isFinal: true
                ))
                eventStream.yield(.utteranceEnd)
            }

        case "response.audio.delta":
            // Binary audio delta — base64 encoded in JSON
            if let audioB64 = json["delta"] as? String,
               let audioData = Data(base64Encoded: audioB64) {
                let samples = int16DataToSamples(audioData)
                eventStream.yield(.audioChunk(samples))
            }

        case "error":
            if let errObj = json["error"] as? [String: Any],
               let message = errObj["message"] as? String {
                eventStream.yield(.error(message))
            }

        case "session.created":
            break // Session established

        case "session.updated":
            break // Session config applied

        case "input_audio_buffer.speech_started":
            break // VAD detected speech

        case "input_audio_buffer.speech_stopped":
            break // VAD detected silence

        default:
            break
        }
    }

    private func handleBinaryAudio(_ data: Data) {
        // Direct binary audio from the API
        let samples = int16DataToSamples(data)
        if !samples.isEmpty {
            eventStream.yield(.audioChunk(samples))
        }
    }

    // MARK: - Audio conversion helpers

    private func samplesToInt16(_ samples: [Float]) -> Data {
        var int16Samples = [Int16](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            let clamped = max(-1.0, min(1.0, Double(samples[i])))
            int16Samples[i] = Int16(clamped * 32767.0)
        }
        return int16Samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func int16DataToSamples(_ data: Data) -> [Float] {
        return data.withUnsafeBytes { ptr -> [Float] in
            let int16Ptr = ptr.bindMemory(to: Int16.self)
            return int16Ptr.map { Float($0) / 32768.0 }
        }
    }

    enum ProviderError: Error, LocalizedError {
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "无效的 OpenAI API URL"
            }
        }
    }
}
