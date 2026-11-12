import Foundation
import Testing
@testable import ReminderCore

struct ReminderNoteTests {
    @Test func noteRoundTripsThroughJSON() throws {
        let reminder = Reminder(title: "Dentista", dueDate: local(2026, 11, 12, 9), note: "Llevar las radiografías.\nPreguntar por la limpieza.")
        let again = try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(reminder))
        #expect(again == reminder)
        #expect(again.note == "Llevar las radiografías.\nPreguntar por la limpieza.")
    }

    @Test func remindersWithoutANoteAreSavedAndReadAsBefore() throws {
        let plain = Reminder(title: "Llamar", dueDate: local(2026, 11, 12, 9))
        let encoded = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!encoded.contains("note"))

        // A file saved before notes existed.
        let saved = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Llamar","dueDate":800000000,"createdAt":800000000,"scheduledAlarms":[]}"#
        let decoded = try JSONDecoder().decode(Reminder.self, from: Data(saved.utf8))
        #expect(decoded.note == "")
        #expect(decoded.trimmedNote == "")
    }

    @Test func trimmedNoteDropsTheBlankSpaceAroundIt() {
        let reminder = Reminder(title: "Compras", dueDate: local(2026, 11, 12, 9), note: "\n  Sin azúcar \n\n")
        #expect(reminder.trimmedNote == "Sin azúcar")
        #expect(Reminder(title: "Compras", dueDate: local(2026, 11, 12, 9), note: " \n ").trimmedNote.isEmpty)
    }

    @Test func completingKeepsTheNote() {
        var reminder = Reminder(
            title: "Vitaminas",
            dueDate: local(2026, 11, 12, 9),
            repeatRule: RepeatRule(frequency: .daily, hour: 9),
            note: "Con el desayuno"
        )
        reminder.complete(now: local(2026, 11, 12, 9, 5), calendar: mexico)
        #expect(reminder.dueDate == local(2026, 11, 13, 9))
        #expect(reminder.note == "Con el desayuno")
    }

    // MARK: - Dictation

    @Test func dictationInAnEmptyNoteIsInsertedAsIs() {
        #expect(NoteDictation.insertion(of: " Comprar leche. \n", characterBefore: nil, characterAfter: nil) == "Comprar leche.")
    }

    @Test func dictationIsSeparatedFromTheWordsAroundIt() {
        #expect(NoteDictation.insertion(of: "y pan", characterBefore: "e", characterAfter: nil) == " y pan")
        #expect(NoteDictation.insertion(of: "Comprar", characterBefore: nil, characterAfter: "l") == "Comprar ")
        #expect(NoteDictation.insertion(of: "mucha", characterBefore: "n", characterAfter: "l") == " mucha ")
        #expect(NoteDictation.insertion(of: "Además", characterBefore: ".", characterAfter: nil) == " Además")
    }

    @Test func dictationNeedsNoSpaceNextToSpacesLineBreaksOrSigns() {
        #expect(NoteDictation.insertion(of: "y pan", characterBefore: " ", characterAfter: " ") == "y pan")
        #expect(NoteDictation.insertion(of: "Pan", characterBefore: "\n", characterAfter: "\n") == "Pan")
        #expect(NoteDictation.insertion(of: "Dónde", characterBefore: "¿", characterAfter: "?") == "Dónde")
        #expect(NoteDictation.insertion(of: "sin azúcar", characterBefore: "(", characterAfter: ")") == "sin azúcar")
        #expect(NoteDictation.insertion(of: "y pan", characterBefore: "e", characterAfter: ".") == " y pan")
    }

    @Test func emptyDictationInsertsNothing() {
        #expect(NoteDictation.insertion(of: "  \n", characterBefore: "a", characterAfter: "b") == "")
    }
}
