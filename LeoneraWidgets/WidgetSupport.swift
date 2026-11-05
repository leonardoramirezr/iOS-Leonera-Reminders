import SwiftUI
import WidgetKit

/// Timeline for widgets that never change, so a single entry is enough.
struct StaticWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> StaticWidgetEntry {
        StaticWidgetEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (StaticWidgetEntry) -> Void) {
        completion(StaticWidgetEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StaticWidgetEntry>) -> Void) {
        completion(Timeline(entries: [StaticWidgetEntry(date: .now)], policy: .never))
    }
}

struct StaticWidgetEntry: TimelineEntry {
    let date: Date
}

/// The app logo as a one-color glyph (`LogoGlyph` in the widget assets), because the lock screen renders widgets
/// without color.
struct LogoGlyph: View {
    var body: some View {
        Image("LogoGlyph")
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}
