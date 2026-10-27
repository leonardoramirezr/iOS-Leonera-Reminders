import BackgroundTasks
import EventKit
import Foundation
import Observation
import os

/// Reads the events of the calendars in the Apple Calendar app, so `AlarmSyncService` can ring an alarm
/// 5 and 1 minutes before each one.
@MainActor
@Observable
final class CalendarEventSource {
    static let shared = CalendarEventSource()

    /// Identifier of the background refresh that keeps the event alarms up to date while the app is closed.
    /// It must also be listed in `BGTaskSchedulerPermittedIdentifiers` (Info.plist).
    nonisolated static let refreshTaskID = (Bundle.main.bundleIdentifier ?? "LeoneraReminders") + ".calendarRefresh"

    private(set) var authorizationStatus: EKAuthorizationStatus
    /// Event calendars of every account, refreshed when the calendar database changes.
    private(set) var calendars: [EKCalendar] = []
    private(set) var lastError: String?

    private let store = EKEventStore()
    private let logger = Logger(subsystem: "LeoneraReminders", category: "calendar")
    @ObservationIgnored private var isObserving = false

    private init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    var hasAccess: Bool { authorizationStatus == .fullAccess }

    /// Starts following changes in the calendar database (events created, moved or deleted, here or synced
    /// from another device) to reschedule the alarms.
    func start() {
        refreshCalendars()
        guard !isObserving else { return }
        isObserving = true
        Task {
            for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                refreshCalendars()
                AlarmSyncService.shared.requestSync()
            }
        }
    }

    @discardableResult
    func requestAccess() async -> Bool {
        do {
            _ = try await store.requestFullAccessToEvents()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            logger.error("Calendar access: \(error.localizedDescription, privacy: .public)")
        }
        refreshCalendars()
        AlarmSyncService.shared.requestSync()
        return hasAccess
    }

    /// The events of the calendars in `calendarIDs` that start in `start...end`, occurrence by occurrence.
    func events(calendarIDs: [String], from start: Date, to end: Date) -> [CalendarEventSnapshot] {
        updateAuthorizationStatus()
        guard hasAccess else { return [] }
        let wanted = Set(calendarIDs)
        // A calendar that no longer exists (deleted, or its account removed) is simply ignored.
        let selected = store.calendars(for: .event).filter { wanted.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
        return store.events(matching: predicate).compactMap { event in
            guard let startDate = event.startDate else { return nil }
            let declined = event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
            let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
            let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
            return CalendarEventSnapshot(
                eventID: event.calendarItemIdentifier,
                title: event.title ?? "",
                startDate: startDate,
                isAllDay: event.isAllDay,
                isSkipped: event.status == .canceled || declined,
                calendarID: event.calendar?.calendarIdentifier ?? "",
                endDate: event.endDate,
                location: location?.isEmpty == false ? location : nil,
                notes: notes?.isEmpty == false ? notes : nil
            )
        }
    }

    /// The calendar with `id` among the ones last read, for its name and color.
    func calendar(id: String) -> EKCalendar? {
        calendars.first { $0.calendarIdentifier == id }
    }

    /// Asks iOS to wake the app in a few hours to refresh the event alarms (only when the feature is on).
    nonisolated static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(6 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Logger(subsystem: "LeoneraReminders", category: "calendar")
                .error("Background refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshCalendars() {
        updateAuthorizationStatus()
        calendars = hasAccess
            ? store.calendars(for: .event).sorted { lhs, rhs in
                let lhsSource = lhs.source?.title ?? "", rhsSource = rhs.source?.title ?? ""
                if lhsSource != rhsSource { return lhsSource.localizedStandardCompare(rhsSource) == .orderedAscending }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            : []
    }

    private func updateAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if authorizationStatus != status { authorizationStatus = status }
    }
}
