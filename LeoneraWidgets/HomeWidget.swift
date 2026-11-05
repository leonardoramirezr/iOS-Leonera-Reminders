import SwiftUI
import WidgetKit

/// Lock screen widget that opens Leonera on its home screen, the reminder list.
struct HomeWidget: Widget {
    private let kind = "HomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StaticWidgetProvider()) { _ in
            HomeWidgetView()
        }
        .configurationDisplayName("Abrir Leonera")
        .description("Abre Leonera en la lista de recordatorios.")
        // Inline widgets only show a system symbol next to the text, so they could not show the logo.
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

/// What each lock screen slot shows: the same logo as «Grabar recordatorio», without the microphone.
/// Tapping it opens the app on the reminder list.
struct HomeWidgetView: View {
    @Environment(\.widgetFamily) private var family

    /// The same link as `DeepLink.homeURL` in the app (`LeoneraReminders/Core/DeepLink.swift`): keep both in sync.
    private static let homeURL = URL(string: "leonera://home")!

    var body: some View {
        content
            .widgetURL(Self.homeURL)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular:
            HStack(spacing: 8) {
                LogoGlyph()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leonera")
                        .font(.headline)
                    Text("Recordatorios")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            ZStack {
                AccessoryWidgetBackground()
                LogoGlyph()
                    .padding(10)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Abrir Leonera")
        }
    }
}
