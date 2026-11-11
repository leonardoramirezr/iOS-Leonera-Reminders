import Foundation

/// Corrects text dictated into a note with an LLM: the speech to text model writes what it hears, without much care
/// for punctuation, signs or accents, and this fixes them without changing what was said.
enum DictationCorrection {
    static let systemPrompt = """
    Eres un corrector de textos dictados por voz. Recibirás la transcripción literal de un audio. Corrige la puntuación, los signos (incluidos los de apertura ¿ y ¡), los acentos, las mayúsculas y la ortografía, y ajusta lo mínimo necesario para que el texto tenga sentido y se lea con naturalidad. Conserva el idioma, el significado, el tono y las palabras de quien habla: no añadas información, no resumas y no respondas a lo que dice el texto. Cuando el texto exprese una hora como «cinco y media», «seis y media» u «ocho y media», escríbela en formato numérico: 5:30, 6:30 u 8:30. Devuelve únicamente el texto corregido, sin comillas ni comentarios.
    """

    /// The prompt, then the transcript exactly as it came from the speech to text model.
    static func messages(for transcript: String) -> [GroqAPI.ChatMessage] {
        [.system(systemPrompt), .user(transcript)]
    }

    /// Quotes a model may wrap the whole text in even though the prompt asks it not to.
    private static let quotePairs: [(open: Character, close: Character)] = [("\"", "\""), ("«", "»"), ("“", "”")]

    /// The corrected text in the model's reply: without its reasoning, the blank space around it or quotes around
    /// the whole text. `nil` when nothing is left.
    static func correctedText(from content: String) -> String? {
        var text = GroqAPI.removingReasoning(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count >= 2, let pair = quotePairs.first(where: { text.first == $0.open && text.last == $0.close }) {
            let inner = text.dropFirst().dropLast()
            // Only a pair around the whole text: «"Sí" y "no"» keeps its quotes.
            if !inner.contains(pair.open), !inner.contains(pair.close) {
                text = String(inner).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text.isEmpty ? nil : text
    }
}
