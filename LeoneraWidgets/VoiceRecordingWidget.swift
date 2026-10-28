import SwiftUI
import WidgetKit

/// Lock screen widget that opens Leonera already recording a voice reminder.
struct VoiceRecordingWidget: Widget {
    private let kind = "VoiceRecordingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VoiceRecordingProvider()) { _ in
            VoiceRecordingWidgetView()
        }
        .configurationDisplayName("Grabar recordatorio")
        .description("Abre Leonera grabando para crear recordatorios con la voz.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// The widget never changes, so a single entry is enough.
struct VoiceRecordingProvider: TimelineProvider {
    func placeholder(in context: Context) -> VoiceRecordingEntry {
        VoiceRecordingEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (VoiceRecordingEntry) -> Void) {
        completion(VoiceRecordingEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VoiceRecordingEntry>) -> Void) {
        completion(Timeline(entries: [VoiceRecordingEntry(date: .now)], policy: .never))
    }
}

struct VoiceRecordingEntry: TimelineEntry {
    let date: Date
}

/// What each lock screen slot shows. Tapping it opens the app on voice capture.
struct VoiceRecordingWidgetView: View {
    @Environment(\.widgetFamily) private var family

    /// The same link as `DeepLink.voiceRecordingURL` in the app (`LeoneraReminders/Core/DeepLink.swift`): keep both in sync.
    private static let voiceRecordingURL = URL(string: "leonera://voice-recording")!

    var body: some View {
        content
            .widgetURL(Self.voiceRecordingURL)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular:
            HStack(spacing: 8) {
                LogoWithMicBadge()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leonera")
                        .font(.headline)
                    Text("Grabar recordatorio")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            // Inline widgets only show one symbol next to the text, so the microphone stays on its own.
            Label("Grabar recordatorio", systemImage: "mic.fill")
        default:
            ZStack {
                AccessoryWidgetBackground()
                LogoWithMicBadge()
                    .padding(10)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Grabar recordatorio")
        }
    }
}

/// The app logo with a small microphone badge on its bottom-right corner.
/// The logo is a one-color glyph (`LogoGlyph` in the widget assets) because the lock screen renders widgets without color.
struct LogoWithMicBadge: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let badge = side * 0.36
            let gap = side * 0.07
            ZStack(alignment: .bottomTrailing) {
                Image("LogoGlyph")
                    .resizable()
                    .scaledToFit()
                    // Cut a ring around the badge out of the logo so both stay readable.
                    .mask {
                        Rectangle()
                            .overlay(alignment: .bottomTrailing) {
                                Circle()
                                    .frame(width: badge + gap * 2, height: badge + gap * 2)
                                    .offset(x: gap, y: gap)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                    }
                Image(systemName: "mic.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: badge, height: badge)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}
