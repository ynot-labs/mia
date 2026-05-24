import Foundation

/// Orchestrates the full speech-to-speech translation pipeline:
/// Audio capture → STT + Translation → TTS output + Subtitles
///
/// Uses two independent providers to separate the two flows:
///   Outbound: mic → STT+Translation → TTS audio → BlackHole → meeting hears translated voice
///   Inbound:  system capture → STT+Translation → HUD subtitles → user reads what others say
@MainActor
final class TranslationPipeline: @unchecked Sendable {
    private var outboundProvider: (any TranslationProvider)?
    private var inboundProvider: (any TranslationProvider)?
    private let micCapture = MicCapture()
    private let systemCapture = SystemAudioCapture()
    private let ttsOutput = TTSOutput()

    private var inputLanguage = "zh"
    private var outputLanguage = "en"
    private var inputDeviceID: String?
    private var outputDeviceID: String?
    private var captureAppBundleID: String?

    private var outboundTask: Task<Void, Never>?
    private var inboundTask: Task<Void, Never>?
    private var outboundEventTask: Task<Void, Never>?
    private var inboundEventTask: Task<Void, Never>?

    // MARK: - Callbacks

    var onSubtitle: ((SubtitleLine) -> Void)?
    var onStatusChange: ((ConnectionStatus) -> Void)?
    var onError: ((String) -> Void)?
    var onInputLevel: ((Float) -> Void)?

    // MARK: - Configuration

    func configure(
        outboundProvider: any TranslationProvider,
        inboundProvider: any TranslationProvider,
        inputLanguage: String,
        outputLanguage: String,
        inputDeviceID: String?,
        outputDeviceID: String?,
        captureAppBundleID: String?
    ) {
        self.outboundProvider = outboundProvider
        self.inboundProvider = inboundProvider
        self.inputLanguage = inputLanguage
        self.outputLanguage = outputLanguage
        self.inputDeviceID = inputDeviceID
        self.outputDeviceID = outputDeviceID
        self.captureAppBundleID = captureAppBundleID
    }

    // MARK: - Lifecycle

    func start() async throws {
        guard let outboundProvider = outboundProvider,
              let inboundProvider = inboundProvider else {
            throw PipelineError.notConfigured
        }

        onStatusChange?(.connecting)

        // 1. Connect both providers
        let sr = micCapture.sampleRate
        try await outboundProvider.connect(inputLanguage: inputLanguage, outputLanguage: outputLanguage, sampleRate: sr)
        try await inboundProvider.connect(inputLanguage: inputLanguage, outputLanguage: outputLanguage, sampleRate: sr)

        // 2. Configure TTS output to virtual device
        try ttsOutput.configure(deviceUID: outputDeviceID)
        try ttsOutput.start()

        onStatusChange?(.connected)

        // Capture references before entering detached tasks (actor isolation)
        let micCapture = self.micCapture
        let systemCapture = self.systemCapture
        let ttsOutput = self.ttsOutput
        let onSubtitle = self.onSubtitle
        let onError = self.onError
        let onInputLevel = self.onInputLevel
        let bundleID = self.captureAppBundleID

        // 3. Outbound event stream: audio chunks → TTS, errors → onError
        //    (no subtitles — user doesn't need to see their own translation)
        let outboundStream = outboundProvider.events()
        outboundEventTask = Task.detached(priority: .userInitiated) {
            for await event in outboundStream {
                switch event {
                case .audioChunk(let samples):
                    await MainActor.run { ttsOutput.scheduleBuffer(samples) }
                case .error(let message):
                    await MainActor.run { onError?(message) }
                case .partial, .utteranceEnd:
                    break // outbound translations go to TTS only, not HUD
                }
            }
        }

        // 4. Inbound event stream: translations → subtitles, errors → onError
        //    (no TTS — inbound is for reading only)
        let inboundStream = inboundProvider.events()
        inboundEventTask = Task.detached(priority: .userInitiated) {
            for await event in inboundStream {
                switch event {
                case .partial(let text, let language, let isFinal):
                    let line = SubtitleLine(text: text, language: language, timestamp: Date(), isFinal: isFinal)
                    await MainActor.run { onSubtitle?(line) }
                case .error(let message):
                    await MainActor.run { onError?(message) }
                case .audioChunk, .utteranceEnd:
                    break // inbound audio chunks are ignored (no TTS for inbound)
                }
            }
        }

        // 5. Start mic capture → outbound provider
        let micStream = try micCapture.start(deviceUID: inputDeviceID)
        outboundTask = Task.detached(priority: .userInitiated) {
            var audioBuffer = [Float]()
            for await samples in micStream {
                let level = computeRMS(samples)
                await MainActor.run { onInputLevel?(level) }

                audioBuffer.append(contentsOf: samples)
                if audioBuffer.count >= 2400 {
                    let chunk = audioBuffer
                    audioBuffer.removeAll()
                    do {
                        try await outboundProvider.sendAudio(chunk)
                    } catch {
                        await MainActor.run { onError?(error.localizedDescription) }
                    }
                }
            }
        }

        // 6. Start system audio capture → inbound provider (best-effort)
        inboundTask = Task.detached(priority: .userInitiated) {
            do {
                let sysStream = try await systemCapture.start(bundleID: bundleID)
                for await samples in sysStream {
                    do {
                        try await inboundProvider.sendAudio(samples)
                    } catch {
                        await MainActor.run { onError?(error.localizedDescription) }
                    }
                }
            } catch {
                await MainActor.run {
                    onError?("系统音频采集失败: \(error.localizedDescription)")
                }
            }
        }
    }

    func stop() async {
        outboundTask?.cancel()
        inboundTask?.cancel()
        outboundEventTask?.cancel()
        inboundEventTask?.cancel()

        await outboundProvider?.disconnect()
        await inboundProvider?.disconnect()
        micCapture.stop()
        systemCapture.stop()
        ttsOutput.stop()
    }

    enum PipelineError: Error, LocalizedError {
        case notConfigured

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "翻译管线未配置"
            }
        }
    }
}

// MARK: - Free helpers

private func computeRMS(_ samples: [Float]) -> Float {
    guard !samples.isEmpty else { return 0 }
    let sum = samples.reduce(0) { $0 + $1 * $1 }
    return sqrt(sum / Float(samples.count))
}
