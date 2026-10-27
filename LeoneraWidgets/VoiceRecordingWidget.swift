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
            VStack(alignment: .leading, spacing: 2) {
                Label("Leonera", systemImage: "mic.fill")
                    .font(.headline)
                Text("Grabar recordatorio")
                    .font(.caption)
            }
        case .accessoryInline:
            Label("Grabar recordatorio", systemImage: "mic.fill")
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill")
                    .font(.title2)
            }
            .accessibilityLabel("Grabar recordatorio")
        }
    }
}
