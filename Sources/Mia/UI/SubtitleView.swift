import SwiftUI

/// Renders the subtitle text with a close button and drag hint.
struct SubtitleView: View {
    @ObservedObject var controller: SubtitleHUDController

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main content
            VStack(spacing: 6) {
                Spacer()

                if !controller.currentText.isEmpty {
                    Text(controller.currentText)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .id(controller.currentText)
                }

                Spacer()

                if controller.subtitleLines.count > 1 {
                    VStack(spacing: 2) {
                        ForEach(controller.subtitleLines.suffix(3).reversed()) { line in
                            Text(line.text)
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Close button — top right
            Button(action: { controller.hide() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(8)
            .help("关闭字幕浮窗")
        }
    }
}
