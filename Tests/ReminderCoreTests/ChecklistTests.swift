import Foundation
import Testing
@testable import ReminderCore

struct ChecklistTests {
    @Test func togglingAnItemChecksAndUnchecksIt() {
        let first = ChecklistItem(title: "Leche")
        let second = ChecklistItem(title: "Pan")
        var reminder = Reminder(title: "Compras", dueDate: local(2026, 10, 24, 18), checklist: [first, second])
        reminder.toggleChecklistItem(id: second.id)
        #expect(reminder.checklist == [first, ChecklistItem(id: second.id, title: "Pan", isDone: true)])
        reminder.toggleChecklistItem(id: second.id)
        #expect(reminder.checklist == [first, second])
    }

    @Test func togglingDoesNothingForPlainRemindersOrUnknownItems() {
        var plain = Reminder(title: "Llamar", dueDate: local(2026, 10, 24, 18))
        plain.toggleChecklistItem(id: UUID())
        #expect(plain.checklist == nil)

        var list = Reminder(title: "Compras", dueDate: local(2026, 10, 24, 18), checklist: [ChecklistItem(title: "Leche")])
        let before = list
        list.toggleChecklistItem(id: UUID())
        #expect(list == before)
    }

    @Test func appendingAddsAnUncheckedItemAtTheEnd() {
        var plain = Reminder(title: "Llamar", dueDate: local(2026, 10, 24, 18))
        plain.appendChecklistItem(titled: "Nada")
        #expect(plain.checklist == nil)

        var reminder = Reminder(title: "Compras", dueDate: local(2026, 10, 24, 18), checklist: [])
        reminder.appendChecklistItem(titled: "Leche")
        reminder.appendChecklistItem(titled: "Pan")
        #expect(reminder.checklist?.map(\.title) == ["Leche", "Pan"])
        #expect(reminder.checklist?.allSatisfy { !$0.isDone } == true)
    }

    @Test func completingARepeatingChecklistUnchecksEveryItem() {
        var reminder = Reminder(
            title: "Compras",
            dueDate: local(2026, 10, 17, 18),
            repeatRule: RepeatRule(frequency: .weekly, hour: 18, weekdays: [7]),
            checklist: [ChecklistItem(title: "Leche", isDone: true), ChecklistItem(title: "Pan")]
        )
        reminder.complete(now: local(2026, 10, 17, 18, 5), calendar: mexico)
        #expect(reminder.dueDate == local(2026, 10, 24, 18))
        #expect(reminder.checklist?.map(\.title) == ["Leche", "Pan"])
        #expect(reminder.checklist?.allSatisfy { !$0.isDone } == true)
    }

    @Test func completingAOneOffChecklistKeepsItsCheckboxes() {
        let milk = ChecklistItem(title: "Leche", isDone: true)
        var reminder = Reminder(title: "Compras", dueDate: local(2026, 10, 24, 18), checklist: [milk])
        reminder.complete(now: local(2026, 10, 24, 18, 5), calendar: mexico)
        #expect(reminder.isCompleted)
        #expect(reminder.checklist == [milk])
    }

    @Test func checklistRoundTripsThroughJSON() throws {
        let reminder = Reminder(title: "Compras", dueDate: local(2026, 10, 24, 18),
                                checklist: [ChecklistItem(title: "Leche", isDone: true), ChecklistItem(title: "Pan")])
        let again = try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(reminder))
        #expect(again == reminder)
    }

    @Test func emptyChecklistIsStillAChecklistAndPlainRemindersStayUnchanged() throws {
        let empty = Reminder(title: "Compras", dueDate: local(2026, 10, 24, 18), checklist: [])
        let again = try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(empty))
        #expect(again.checklist == [])

        let plain = Reminder(title: "Llamar", dueDate: local(2026, 10, 24, 18))
        let encoded = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!encoded.contains("checklist"))
        #expect(try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(plain)).checklist == nil)
    }
}
