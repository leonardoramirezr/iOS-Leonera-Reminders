import Foundation

/// How dictated text joins a note at the cursor: separated by a space from the words around it, but not after a
/// line break or an opening sign («¿», «(»…) nor before a closing one or punctuation («.», «,», «)»…).
enum NoteDictation {
    /// Characters after which the dictated text starts without a space.
    private static let opening: Set<Character> = ["(", "[", "{", "¿", "¡", "«", "“", "‘", "\"", "'"]
    /// Characters before which the dictated text ends without a space.
    private static let closing: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]", "}", "»", "”", "’", "…", "\"", "'"]

    /// The text to insert at the cursor for `dictated`, given the characters right before and after the cursor
    /// (`nil` at the start or the end of the note). Empty when nothing was dictated.
    static func insertion(of dictated: String, characterBefore: Character?, characterAfter: Character?) -> String {
        let text = dictated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        var insertion = text
        if let before = characterBefore, !before.isWhitespace, !opening.contains(before) {
            insertion = " " + insertion
        }
        if let after = characterAfter, !after.isWhitespace, !closing.contains(after) {
            insertion += " "
        }
        return insertion
    }
}
