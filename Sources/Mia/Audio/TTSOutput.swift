import AVFoundation
import CoreAudio

/// Plays PCM audio buffers to a selected output device (typically BlackHole virtual device).
/// Used for the "outbound" flow: translated TTS audio → virtual mic → meeting app.
final class TTSOutput {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var isConfigured = false

    /// Configure the TTS output to play to a specific device.
    /// - Parameter deviceUID: The UID of the output device (e.g., BlackHole).
    /// - Parameter sampleRate: Expected sample rate of incoming PCM data.
    func configure(deviceUID: String?, sampleRate: Double = 24000) throws {
        stop()

        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        self.format = outputFormat

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)

        // Route to the specific output device if provided
        if let uid = deviceUID {
            guard let device = AudioDeviceManager.findOutputDevice(byUID: uid) else {
                throw OutputError.deviceNotFound(uid)
            }
            setOutputDevice(deviceID: device.id)
        }

        engine.prepare()
        isConfigured = true
    }

    /// Start playback.
    func start() throws {
        guard isConfigured else { throw OutputError.notConfigured }
        try engine.start()
        playerNode.play()
    }

    /// Enqueue a PCM float32 audio buffer (mono) for playback.
    func scheduleBuffer(_ samples: [Float]) {
        guard let format = format, !samples.isEmpty else { return }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        // Copy samples into buffer
        samples.withUnsafeBufferPointer { ptr in
            buffer.floatChannelData?[0].initialize(from: ptr.baseAddress!, count: samples.count)
        }

        playerNode.scheduleBuffer(buffer)
    }

    /// Check if the player is still playing (not starved).
    var isPlaying: Bool {
        playerNode.isPlaying
    }

    /// Get current playback time (useful for latency measurement).
    var lastRenderTime: AVAudioTime? {
        playerNode.lastRenderTime
    }

    func stop() {
        playerNode.stop()
        engine.stop()
        isConfigured = false
    }

    deinit {
        stop()
    }

    // MARK: - Private

    private func setOutputDevice(deviceID: AudioDeviceID) {
        let audioUnit = engine.outputNode.audioUnit!
        var id = deviceID
        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    enum OutputError: Error, LocalizedError {
        case notConfigured
        case deviceNotFound(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "TTS 输出未配置"
            case .deviceNotFound(let uid): return "找不到输出设备: \(uid)"
            }
        }
    }
}

// MARK: - Device lookup helper

extension AudioDeviceManager {
    static func findOutputDevice(byUID uid: String) -> AudioDevice? {
        enumerateOutputDevices().first { $0.uid == uid }
    }
}
