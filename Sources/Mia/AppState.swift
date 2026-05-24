import SwiftUI
import Combine
import CoreAudio
import AppKit

@MainActor
final class AppState: ObservableObject {
    // MARK: - Language settings
    @AppStorage("inputLanguage") var inputLanguage = "zh"
    @AppStorage("outputLanguage") var outputLanguage = "en"
    @AppStorage("selectedProvider") var selectedProvider: ProviderType = .soniox
    @AppStorage("openaiAPIKey") var openaiAPIKey = ""
    @AppStorage("sonioxAPIKey") var sonioxAPIKey = ""
    @AppStorage("ttsVoice") var ttsVoice = "Maya"

    // MARK: - Audio device settings
    @Published var selectedInputDeviceID: String?
    @Published var selectedOutputDeviceID: String?
    @Published var captureAppBundleID: String?  // ScreenCaptureKit target for inbound audio

    // MARK: - Runtime state
    @Published var isTranslating = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var subtitleLines: [SubtitleLine] = []
    @Published var inputAudioLevel: Float = 0.0
    @Published var outputAudioLevel: Float = 0.0
    @Published var errorMessage: String?

    let audioDeviceManager = AudioDeviceManager()
    let pipeline = TranslationPipeline()
    let hud = SubtitleHUDController()

    func toggleTranslation() async {
        if isTranslating {
            await pipeline.stop()
            isTranslating = false
            connectionStatus = .disconnected
        } else {
            connectionStatus = .connecting
            errorMessage = nil

            let outbound = makeProvider()
            let inbound = makeProvider()
            pipeline.configure(
                outboundProvider: outbound,
                inboundProvider: inbound,
                inputLanguage: inputLanguage,
                outputLanguage: outputLanguage,
                inputDeviceID: selectedInputDeviceID,
                outputDeviceID: selectedOutputDeviceID,
                captureAppBundleID: captureAppBundleID
            )

            pipeline.onSubtitle = { [weak self] line in
                Task { @MainActor in
                    self?.subtitleLines.append(line)
                    if self?.subtitleLines.count ?? 0 > 20 {
                        self?.subtitleLines.removeFirst()
                    }
                    self?.hud.show(line)
                }
            }

            pipeline.onStatusChange = { [weak self] status in
                Task { @MainActor in
                    self?.connectionStatus = status
                }
            }

            pipeline.onError = { [weak self] error in
                Task { @MainActor in
                    self?.errorMessage = error
                    self?.connectionStatus = .error
                }
            }

            pipeline.onInputLevel = { [weak self] level in
                Task { @MainActor in
                    self?.inputAudioLevel = level
                }
            }

            do {
                try await pipeline.start()
                isTranslating = true
                connectionStatus = .connected
            } catch {
                errorMessage = error.localizedDescription
                connectionStatus = .error
            }
        }
    }

    private func makeProvider() -> any TranslationProvider {
        switch selectedProvider {
        case .openAI:
            return OpenAIProvider(apiKey: openaiAPIKey)
        case .soniox:
            return SonioxProvider(apiKey: sonioxAPIKey, voice: ttsVoice)
        }
    }

    // MARK: - Global hotkey

    func setupGlobalHotkey() {
        let manager = HotkeyManager()
        manager.onAction = { [weak self] in
            Task { @MainActor in
                await self?.toggleTranslation()
            }
        }
        manager.register()
        objc_setAssociatedObject(self, &Self.hotkeyKey, manager, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private static var hotkeyKey: UInt8 = 0
}

// MARK: - Supporting types

enum ProviderType: String, CaseIterable {
    case openAI = "OpenAI Realtime"
    case soniox = "Soniox"
}

enum ConnectionStatus {
    case disconnected
    case connecting
    case connected
    case error

    var label: String {
        switch self {
        case .disconnected: "未连接"
        case .connecting: "连接中..."
        case .connected: "已连接"
        case .error: "连接错误"
        }
    }

    var color: Color {
        switch self {
        case .disconnected: .secondary
        case .connecting: .orange
        case .connected: .green
        case .error: .red
        }
    }
}

struct SubtitleLine: Identifiable {
    let id = UUID()
    let text: String
    let language: String
    let timestamp: Date
    let isFinal: Bool
}
