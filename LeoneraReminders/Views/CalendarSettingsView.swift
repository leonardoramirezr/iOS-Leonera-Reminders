import EventKit
import SwiftUI
import UIKit

/// Calendars of the Apple Calendar app whose events ring an alarm 5 and 1 minutes before they start.
struct CalendarSettingsView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(CalendarEventSource.self) private var calendarEvents
    @Environment(\.openURL) private var openURL

    /// The calendars of one account (iCloud, Google, on this iPhone…).
    private struct CalendarGroup: Identifiable {
        let source: String
        let calendars: [EKCalendar]
        var id: String { source }
    }

    private var selectedIDs: Set<String> { Set(settingsStore.settings.calendarAlarms.calendarIDs) }

    private var groups: [CalendarGroup] {
        var groups: [CalendarGroup] = []
        for calendar in calendarEvents.calendars {
            let source = calendar.source?.title ?? "Otros"
            if let last = groups.last, last.source == source {
                groups[groups.count - 1] = CalendarGroup(source: source, calendars: last.calendars + [calendar])
            } else {
                groups.append(CalendarGroup(source: source, calendars: [calendar]))
            }
        }
        return groups
    }

    var body: some View {
        Form {
            accessSection
            if calendarEvents.hasAccess {
                if calendarEvents.calendars.isEmpty {
                    Section {
                        Text("No hay calendarios en este iPhone.")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(groups) { group in
                    Section(group.source) {
                        ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                            row(calendar)
                        }
                    }
                }
            }
        }
        .navigationTitle("Calendario de Apple")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { calendarEvents.start() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var accessSection: some View {
        Section {
            switch calendarEvents.authorizationStatus {
            case .fullAccess:
                Label("Acceso permitido", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .notDetermined:
                Button("Permitir acceso a Calendario") {
                    Task { await calendarEvents.requestAccess() }
                }
            default:
                Label("Sin acceso a los eventos", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Button("Abrir Configuración") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            if let error = calendarEvents.lastError {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
        } footer: {
            Text("Por cada evento de los calendarios que elijas suena una alarma 5 minutos y 1 minuto antes, con el sonido y el modo de silencio de los recordatorios. Se programan los eventos de los próximos \(CalendarEventAlarmPlanner.lookAheadDays) días; se actualizan al abrir la app y, cada pocas horas, en segundo plano. Los eventos de todo el día, cancelados o rechazados no suenan.")
        }
    }

    private func row(_ calendar: EKCalendar) -> some View {
        let isSelected = selectedIDs.contains(calendar.calendarIdentifier)
        return Button {
            toggle(calendar.calendarIdentifier)
        } label: {
            HStack {
                Circle()
                    .fill(Color(cgColor: calendar.cgColor ?? UIColor.systemGray.cgColor))
                    .frame(width: 12, height: 12)
                Text(calendar.title)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggle(_ id: String) {
        var ids = settingsStore.settings.calendarAlarms.calendarIDs
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
        settingsStore.settings.calendarAlarms.calendarIDs = ids
    }
}
