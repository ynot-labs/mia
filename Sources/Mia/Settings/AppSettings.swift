import SwiftUI

/// Centralized user defaults keys. Uses @AppStorage in AppState for most values;
/// this file provides additional helpers and defaults.
enum AppSettings {
    static let defaultInputLanguage = "zh"
    static let defaultOutputLanguage = "en"
    static let defaultProvider = ProviderType.openAI
    static let defaultTTSVoice = "alloy"
    static let ttsSampleRate: Double = 24000

    /// Supported provider configurations
    static let providers: [(ProviderType, String, String)] = [
        (.openAI, "OpenAI Realtime", "单连接 STT + 翻译 + TTS，需要 API Key"),
        (.soniox, "Soniox", "双 WebSocket STT + TTS 串联，延迟更低"),
    ]
}
