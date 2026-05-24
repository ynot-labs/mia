import SwiftUI
import AppKit

@main
struct MiaApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        Window("Mia - 同声传译", id: "main") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 480, minHeight: 360)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 420)

        MenuBarExtra("Mia", systemImage: menuBarIcon) {
            menuBarContent
        }
    }

    // MARK: - Menu bar

    private var menuBarIcon: String {
        switch appState.connectionStatus {
        case .connected:    return "waveform.circle.fill"
        case .connecting:   return "waveform.circle"
        case .disconnected: return "waveform"
        case .error:        return "waveform.badge.exclamationmark"
        }
    }

    private var menuBarContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mia 同声传译").font(.headline)
            Divider()

            HStack {
                Circle().fill(appState.connectionStatus.color).frame(width: 8, height: 8)
                Text(appState.connectionStatus.label).font(.caption)
            }.padding(.vertical, 2)

            Text("\(LanguageList.name(for: appState.inputLanguage)) → \(LanguageList.name(for: appState.outputLanguage))")
                .font(.caption).foregroundColor(.secondary)

            if let error = appState.errorMessage {
                Text(error).font(.caption2).foregroundColor(.red).lineLimit(2)
            }

            Divider()

            Button(appState.isTranslating ? "停止翻译" : "开始翻译") {
                Task { await appState.toggleTranslation() }
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button(appState.hud.isVisible ? "隐藏字幕浮窗" : "显示字幕浮窗") {
                if appState.hud.isVisible { appState.hud.hide() }
                else { appState.hud.showEmpty() }
            }

            Divider()

            Button("打开主窗口...") {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                for w in NSApp.windows where w.title.contains("Mia") {
                    w.makeKeyAndOrderFront(nil)
                }
            }

            Divider()

            Button("退出 Mia") {
                Task {
                    if appState.isTranslating { await appState.toggleTranslation() }
                    NSApplication.shared.terminate(nil)
                }
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(width: 220)
    }
}
