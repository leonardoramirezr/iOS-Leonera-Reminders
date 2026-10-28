import EventKit
import SwiftUI
import UIKit

/// Row of an Apple Calendar event in the reminder list. It has no swipe actions: the event is only read.
struct CalendarEventRow: View {
    let synced: SyncedCalendarEvent
    let now: Date
    let calendar: EKCalendar?
    let isRinging: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(synced.event.displayTitle)
                    .foregroundStyle(Color.primary)
                Label(DateText.relative(synced.event.startDate, now: now), systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if let calendar {
                        Circle()
                            .fill(calendar.swiftUIColor)
                            .frame(width: 8, height: 8)
                        Text("\(calendar.title) · \(alarmsText)")
                    } else {
                        Text(alarmsText)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isRinging {
                Image(systemName: "alarm.waves.left.and.right.fill")
                    .foregroundStyle(Color.calendarEvent)
                    .symbolEffect(.wiggle, options: .repeating)
                    .accessibilityLabel("Sonando")
            }
        }
        .padding(.vertical, 2)
    }

    /// "Suena 9:55 y 9:59".
    private var alarmsText: String {
        "Suena " + synced.alarms.map { DateText.time($0.fireDate) }.formatted(.list(type: .and))
    }
}

/// Details of an Apple Calendar event, read-only: the event is edited in the Calendar app.
struct CalendarEventDetailView: View {
    let synced: SyncedCalendarEvent

    @Environment(CalendarEventSource.self) private var calendarEvents
    @Environment(AlarmSyncService.self) private var alarms
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var event: CalendarEventSnapshot { synced.event }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(event.displayTitle)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                }

                Section("Fecha") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DateText.relative(event.startDate))
                            .font(.title3.weight(.semibold))
                        Text(DateText.full(event.startDate))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let end = event.endDate, end > event.startDate {
                        LabeledContent("Termina", value: endText(end))
                        LabeledContent("Duración", value: durationText(end))
                    }
                    if let calendar = calendarEvents.calendar(id: event.calendarID) {
                        LabeledContent("Calendario") {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(calendar.swiftUIColor)
                                    .frame(width: 10, height: 10)
                                Text(calendar.title)
                            }
                        }
                    }
                }

                if let location = event.location {
                    Section("Ubicación") {
                        Text(location)
                            .textSelection(.enabled)
                    }
                }

                if let notes = event.notes {
                    Section("Notas") {
                        Text(linkedNotes(notes))
                            .textSelection(.enabled)
                    }
                }

                Section {
                    ForEach(synced.alarms) { alarm in
                        LabeledContent {
                            Text(alarm.isRepeat ? "Sin confirmar" : "\(alarm.leadMinutes) min antes")
                        } label: {
                            Label(DateText.time(alarm.fireDate), systemImage: "alarm")
                        }
                    }
                } header: {
                    Text("Alarmas")
                } footer: {
                    Text("El evento viene de Calendario de Apple; para cambiarlo, edítalo ahí.")
                }

                Section {
                    Button("Enterado") {
                        Task {
                            await alarms.acknowledgeCalendarEvent(synced)
                            dismiss()
                        }
                    }
                } footer: {
                    Text("Mientras no lo confirmes, la alarma vuelve a sonar un minuto después de cada vez que la detengas.")
                }

                Section {
                    Button {
                        if let url = URL(string: "calshow:\(event.startDate.timeIntervalSinceReferenceDate)") { openURL(url) }
                    } label: {
                        Label("Abrir en Calendario", systemImage: "calendar")
                    }
                }
            }
            .navigationTitle("Evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    /// The end time, with the day when it ends on another day.
    private func endText(_ end: Date) -> String {
        Calendar.current.isDate(end, inSameDayAs: event.startDate) ? DateText.time(end) : DateText.relative(end)
    }

    private func durationText(_ end: Date) -> String {
        Duration.seconds(end.timeIntervalSince(event.startDate))
            .formatted(.units(allowed: [.days, .hours, .minutes], width: .wide))
    }

    /// The notes with every link detected and drawn as blue underlined text that opens it when tapped.
    private func linkedNotes(_ notes: String) -> AttributedString {
        var text = AttributedString(notes)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: notes, range: NSRange(notes.startIndex..., in: notes)) ?? []
        for match in matches {
            guard let url = match.url, let range = Range(match.range, in: text) else { continue }
            text[range].link = url
            text[range].foregroundColor = .blue
            text[range].underlineStyle = .single
        }
        return text
    }
}

extension CalendarEventSnapshot {
    /// The title, or a generic one for untitled events.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Evento" : trimmed
    }
}

extension EKCalendar {
    /// The calendar's color as set in the Calendar app.
    var swiftUIColor: Color {
        Color(cgColor: cgColor ?? UIColor.systemGray.cgColor)
    }
}
