import SwiftUI

/// Language codes and display names for the translation source/target selection.
enum LanguageList {
    static let all: [(code: String, name: String)] = [
        ("zh", "中文 (Chinese)"),
        ("en", "English"),
        ("ja", "日本語 (Japanese)"),
        ("ko", "한국어 (Korean)"),
        ("fr", "Français (French)"),
        ("de", "Deutsch (German)"),
        ("es", "Español (Spanish)"),
        ("pt", "Português (Portuguese)"),
        ("it", "Italiano (Italian)"),
        ("ru", "Русский (Russian)"),
        ("ar", "العربية (Arabic)"),
        ("hi", "हिन्दी (Hindi)"),
        ("th", "ไทย (Thai)"),
        ("vi", "Tiếng Việt (Vietnamese)"),
        ("id", "Bahasa Indonesia"),
        ("ms", "Bahasa Melayu"),
        ("tl", "Filipino"),
        ("tr", "Türkçe (Turkish)"),
        ("nl", "Nederlands (Dutch)"),
        ("pl", "Polski (Polish)"),
        ("sv", "Svenska (Swedish)"),
        ("uk", "Українська (Ukrainian)"),
    ]

    static func name(for code: String) -> String {
        all.first { $0.code == code }?.name ?? code
    }

    /// Group languages by region for easier navigation
    static let popular: [(code: String, name: String)] = [
        ("zh", "中文"),
        ("en", "English"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("es", "Español"),
    ]
}
