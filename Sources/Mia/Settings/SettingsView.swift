import SwiftUI
import CoreGraphics

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showingBlackHoleHelp = false
    @State private var showAPIKey = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("偏好设置").font(.headline)
                Spacer()
                Text("修改自动保存").font(.caption).foregroundColor(.secondary)
                Button("完成") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            // Form content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    providerSection
                    languageSection
                    audioSection
                    captureSection
                }
                .padding(20)
            }
        }
        .frame(width: 480, height: 520)
    }

    // MARK: - Sections

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("翻译服务商").font(.headline)

            Picker("翻译引擎", selection: $appState.selectedProvider) {
                ForEach(ProviderType.allCases, id: \.self) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if appState.selectedProvider == .openAI {
                HStack(spacing: 4) {
                    if showAPIKey {
                        TextField("OpenAI API Key (sk-...)", text: $appState.openaiAPIKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("OpenAI API Key (sk-...)", text: $appState.openaiAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(action: { showAPIKey.toggle() }) {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(showAPIKey ? "隐藏 API Key" : "显示 API Key")
                }
                Text("在 platform.openai.com/api-keys 创建，需开通 Realtime API。")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                HStack(spacing: 4) {
                    if showAPIKey {
                        TextField("Soniox API Key", text: $appState.sonioxAPIKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Soniox API Key", text: $appState.sonioxAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(action: { showAPIKey.toggle() }) {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(showAPIKey ? "隐藏 API Key" : "显示 API Key")
                }
                Text("在 soniox.com/dashboard 获取。免费额度可用于开发测试。")
                    .font(.caption).foregroundColor(.secondary)

                Divider().padding(.vertical, 4)

                Picker("翻译语音", selection: $appState.ttsVoice) {
                    ForEach(SonioxProvider.voices, id: \.self) { voice in
                        Text(voice).tag(voice)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("语言设置").font(.headline)

            HStack(spacing: 12) {
                Picker("我说", selection: $appState.inputLanguage) {
                    ForEach(LanguageList.popular, id: \.code) { Text($0.name).tag($0.code) }
                }
                .frame(maxWidth: .infinity)

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)

                Picker("对方听到", selection: $appState.outputLanguage) {
                    ForEach(LanguageList.popular, id: \.code) { Text($0.name).tag($0.code) }
                }
                .frame(maxWidth: .infinity)
            }

            Text("\(LanguageList.name(for: appState.inputLanguage)) → \(LanguageList.name(for: appState.outputLanguage))")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Mic input
            VStack(alignment: .leading, spacing: 6) {
                Text("麦克风").font(.headline)

                Picker("选择麦克风", selection: $appState.selectedInputDeviceID) {
                    Text("系统默认").tag(nil as String?)
                    ForEach(appState.audioDeviceManager.enumerateInputDevices()) { device in
                        Text(device.displayName).tag(device.uid as String?)
                    }
                }

                Text("选择你说话用的真实麦克风，用于采集你的语音。")
                    .font(.caption).foregroundColor(.secondary)
            }

            Divider()

            // Translated speech output
            VStack(alignment: .leading, spacing: 6) {
                Text("翻译语音输出").font(.headline)

                Picker("输出设备", selection: $appState.selectedOutputDeviceID) {
                    Text("系统默认").tag(nil as String?)
                    ForEach(appState.audioDeviceManager.enumerateOutputDevices()) { device in
                        Text(device.displayName).tag(device.uid as String?)
                    }
                }

                Text("翻译后的语音将发送到此设备。在会议软件里把麦克风设为此设备，对方就能听到翻译。")
                    .font(.caption).foregroundColor(.secondary)

                HStack(spacing: 6) {
                    let bh = appState.audioDeviceManager.findBlackHoleDevice()
                    Image(systemName: bh != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(bh != nil ? .green : .red)
                    Text(bh != nil ? "已检测到 BlackHole — 推荐选它作为输出设备" : "未检测到 BlackHole，推荐安装：")
                        .font(.caption)
                    if bh == nil {
                        Button("安装 BlackHole?") { showingBlackHoleHelp = true }
                            .font(.caption)
                    }
                }
                .sheet(isPresented: $showingBlackHoleHelp) {
                    BlackHoleHelpView()
                }
            }
        }
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("采集哪个应用的音频").font(.headline)

            CaptureAppPicker(selectedBundleID: $appState.captureAppBundleID)

            Text("选择正在运行的会议 App。首次使用需授权「屏幕录制」权限。")
                .font(.caption).foregroundColor(.secondary)
        }
    }
}

// MARK: - BlackHole Help

private struct BlackHoleHelpView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("安装 BlackHole 虚拟音频设备").font(.title2).bold()

            Group {
                Text("方法一 — Homebrew (推荐):").font(.headline)
                Text("brew install blackhole-2ch")
                Text("方法二 — 手动安装:").font(.headline).padding(.top, 8)
                Text("1. 访问 github.com/ExistentialAudio/BlackHole/releases")
                Text("2. 下载最新版 .pkg 安装包")
                Text("3. 安装后重启 Mac")
            }.font(.callout)

            Text("配置会议软件:").font(.headline).padding(.top, 8)
            Text("在 Zoom/Teams/腾讯会议中，将「麦克风」设置为「BlackHole 2ch」。").font(.callout)

            HStack {
                Spacer()
                Button("知道了") { dismiss() }.keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

// MARK: - Capture App Picker

private struct CaptureAppPicker: View {
    @Binding var selectedBundleID: String?
    @State private var availableApps: [(bundleID: String, name: String)] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var needsPermission = false

    var body: some View {
        Group {
            if isLoading {
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("正在查找运行中的应用...").font(.caption).foregroundColor(.secondary)
                }
            } else if needsPermission {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("需要「屏幕录制」权限才能采集会议音频")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 8) {
                        Button("打开系统设置") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption)
                        Button("已授权，刷新") {
                            Task { await loadApps() }
                        }
                        .font(.caption)
                    }
                }
            } else if let error = loadError {
                VStack(alignment: .leading, spacing: 4) {
                    Text(error).font(.caption).foregroundColor(.red)
                    Button("重试") { Task { await loadApps() } }
                        .font(.caption)
                }
            } else if availableApps.isEmpty {
                Text("没有检测到运行中的应用，请先打开会议软件").font(.caption).foregroundColor(.secondary)
            } else {
                Picker("会议应用", selection: $selectedBundleID) {
                    Text("自动检测").tag(nil as String?)
                    ForEach(availableApps, id: \.bundleID) { app in
                        Text(app.name).tag(app.bundleID as String?)
                    }
                }
            }
        }
        .task { await loadApps() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await loadApps() }
        }
    }

    private func loadApps() async {
        isLoading = true; defer { isLoading = false }
        do {
            availableApps = try await SystemAudioCapture.availableCaptureTargets()
            needsPermission = false
            loadError = nil
        } catch {
            let nsErr = error as NSError
            // Permission error from ScreenCaptureKit: domain SCStreamErrorDomain, code -3801
            if nsErr.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain",
                   nsErr.code == -3801 || nsErr.code == -3803 {
                needsPermission = true
                loadError = nil
            } else {
                loadError = error.localizedDescription
                needsPermission = false
            }
        }
    }
}
