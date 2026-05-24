import AVFoundation
import CoreAudio

/// Captures microphone input and yields float32 PCM buffers via AsyncStream.
final class MicCapture {
    private let engine = AVAudioEngine()
    private var isRunning = false

    /// Sample rate of the current input device. Call after engine is prepared.
    var sampleRate: Double { engine.inputNode.outputFormat(forBus: 0).sampleRate }

    /// Start capturing from the specified input device.
    /// Returns an AsyncStream of float32 PCM sample arrays, each representing ~100ms of audio.
    func start(deviceUID: String? = nil) throws -> AsyncStream<[Float]> {
        if let uid = deviceUID, let device = findDevice(byUID: uid) {
            let audioUnit = engine.inputNode.audioUnit!
            var deviceID = device.deviceID
            AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let recordFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: 1,
            interleaved: false
        )!

        engine.prepare()

        return AsyncStream { continuation in
            inputNode.installTap(
                onBus: 0,
                bufferSize: AVAudioFrameCount(recordFormat.sampleRate * 0.1), // ~100ms
                format: recordFormat
            ) { buffer, _ in
                guard let channelData = buffer.floatChannelData?[0] else { return }
                let frameCount = Int(buffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
                continuation.yield(samples)
            }

            do {
                try engine.start()
                isRunning = true
            } catch {
                continuation.finish()
            }
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    deinit {
        stop()
    }

    private func findDevice(byUID uid: String) -> (deviceID: AudioDeviceID, uid: String)? {
        let devices = AudioDeviceManager.enumerateInputDevices()
        return devices.first { $0.uid == uid }.map { (deviceID: $0.id, uid: $0.uid) }
    }
}
