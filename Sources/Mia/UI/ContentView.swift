import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            statusBar

            Divider()

            // Main content
            VStack(spacing: 20) {
                Spacer()

                // Status indicator
                VStack(spacing: 12) {
                    Circle()
                        .fill(appState.connectionStatus.color)
                        .frame(width: 16, height: 16)

                    Text(appState.connectionStatus.label)
                        .font(.headline)
                        .foregroundColor(.secondary)

                    if let error = appState.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                // Audio level meter
                if appState.isTranslating {
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "mic.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            AudioLevelBar(level: appState.inputAudioLevel)
                                .frame(height: 8)
                        }
                        .padding(.horizontal, 40)
                    }
                }

                // Translation toggle
                Button(action: {
                    Task { await appState.toggleTranslation() }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: appState.isTranslating ? "stop.fill" : "waveform")
                        Text(appState.isTranslating ? "停止翻译" : "开始翻译")
                    }
                    .font(.title3)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.space, modifiers: [.command, .shift])

                // Provider and language summary
                if !appState.isTranslating {
                    VStack(spacing: 6) {
                        Text("\(languageName(appState.inputLanguage)) → \(languageName(appState.outputLanguage))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("通过 \(appState.selectedProvider.rawValue)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding()

            Divider()

            // Bottom bar
            HStack {
                if appState.isTranslating, !appState.subtitleLines.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(appState.subtitleLines.suffix(5).reversed()) { line in
                                Text(line.text)
                                    .font(.caption)
                                    .foregroundColor(.primary.opacity(0.7))
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }

                Spacer()

                // HUD toggle
                Button(action: {
                    if appState.hud.isVisible { appState.hud.hide() }
                    else { appState.hud.showEmpty() }
                }) {
                    Image(systemName: appState.hud.isVisible ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle")
                        .font(.caption)
                }
                .help("切换字幕浮窗")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .onAppear { appState.setupGlobalHotkey() }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundColor(.accentColor)

            Text("Mia 同声传译")
                .font(.headline)

            Spacer()

            Text(appState.selectedProvider.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))

            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("偏好设置")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func languageName(_ code: String) -> String {
        LanguageList.name(for: code)
    }
}

// MARK: - Audio Level Bar

struct AudioLevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                RoundedRectangle(cornerRadius: 4)
                    .fill(levelColor)
                    .frame(width: geometry.size.width * CGFloat(min(level * 10, 1.0)))
            }
        }
    }

    private var levelColor: Color {
        if level < 0.1 { .green }
        else if level < 0.3 { .yellow }
        else { .orange }
    }
}
