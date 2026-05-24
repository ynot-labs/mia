import ScreenCaptureKit
import CoreMedia
import AVFoundation

/// Captures audio from a specific app (Zoom, Teams, etc.) using ScreenCaptureKit.
/// Used for the "inbound" flow: meeting audio → translation → subtitles.
///
/// The API requires a video track even for audio-only capture, so we use a
/// 1×1 pixel stream at minimum framerate — no visible screen content.
///
/// User only needs to grant "Screen Recording" permission once.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var bufferContinuation: AsyncStream<[Float]>.Continuation?
    private var isCapturing = false

    /// Start capturing audio from a specific application.
    /// - Parameter bundleID: The bundle identifier of the app to capture (e.g. "us.zoom.xos").
    ///   If nil, captures audio from all apps except our own.
    func start(bundleID: String? = nil) async throws -> AsyncStream<[Float]> {
        let shareableContent = try await SCShareableContent.current

        let apps = shareableContent.applications.filter { app in
            // Exclude our own process
            app.bundleIdentifier != Bundle.main.bundleIdentifier
        }

        // Try to find the requested app, or use the first available
        let targetApp: SCRunningApplication?
        if let bid = bundleID {
            targetApp = apps.first { $0.bundleIdentifier == bid }
        } else {
            // Default: pick known meeting apps if running
            let knownMeetingApps = [
                "us.zoom.xos",           // Zoom
                "com.microsoft.teams2",  // Microsoft Teams (new)
                "com.microsoft.teams",   // Microsoft Teams (classic)
                "com.google.Chrome",     // Google Meet (in Chrome)
                "com.tencent.meeting",   // 腾讯会议
                "com.alibaba.dingtalk",  // 钉钉
                "com.bytedance.lark",    // 飞书
            ]
            targetApp = apps.first { app in
                knownMeetingApps.contains(app.bundleIdentifier)
            } ?? apps.first
        }

        guard let targetApp = targetApp else {
            throw CaptureError.noAppAvailable
        }

        // Filter that captures from the target app only
        guard let display = shareableContent.displays.first else {
            throw CaptureError.noDisplayAvailable
        }
        let filter = SCContentFilter(
            display: display,
            including: [targetApp],
            exceptingWindows: []
        )

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 24000
        config.channelCount = 1

        // Minimal video — API requires it but we don't use the pixel data
        config.width = 1
        config.height = 1
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps
        config.queueDepth = 3

        stream = SCStream(filter: filter, configuration: config, delegate: self)

        return AsyncStream { continuation in
            bufferContinuation = continuation

            do {
                try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
                try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .background))
                stream?.startCapture()
                isCapturing = true
            } catch {
                continuation.finish()
            }
        }
    }

    /// List currently running apps that can be captured.
    static func availableCaptureTargets() async throws -> [(bundleID: String, name: String)] {
        let content = try await SCShareableContent.current
        return content.applications
            .filter { $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .map { (bundleID: $0.bundleIdentifier, name: $0.applicationName) }
    }

    func stop() {
        guard isCapturing else { return }
        isCapturing = false

        try? stream?.removeStreamOutput(self, type: .audio)
        try? stream?.removeStreamOutput(self, type: .screen)
        stream?.stopCapture()
        bufferContinuation?.finish()
        stream = nil
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Only process audio; skip the 1x1 video frames
        guard type == .audio else { return }

        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )

        guard let pointer = dataPointer, totalLength > 0 else { return }

        let sampleCount = totalLength / MemoryLayout<Float32>.size
        let floatPointer = pointer.withMemoryRebound(to: Float32.self, capacity: sampleCount) { $0 }
        let samples = Array(UnsafeBufferPointer(start: floatPointer, count: sampleCount))

        bufferContinuation?.yield(samples)
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        bufferContinuation?.finish()
    }

    enum CaptureError: Error, LocalizedError {
        case noAppAvailable
        case noDisplayAvailable

        var errorDescription: String? {
            switch self {
            case .noAppAvailable: return "没有可用的应用用于音频采集，请先打开会议软件"
            case .noDisplayAvailable: return "无法获取显示器用于音频采集"
            }
        }
    }
}
