import Foundation
import Testing
@testable import ReminderCore

struct DictationCorrectionTests {
    @Test func sendsThePromptAndTheRawTranscript() throws {
        let messages = DictationCorrection.messages(for: "a las cinco y media comprar pan")
        #expect(messages == [.system(DictationCorrection.systemPrompt), .user("a las cinco y media comprar pan")])
        #expect(DictationCorrection.systemPrompt.hasPrefix("Eres un corrector de textos dictados por voz."))
        #expect(DictationCorrection.systemPrompt.hasSuffix("Devuelve únicamente el texto corregido, sin comillas ni comentarios."))
        #expect(!DictationCorrection.systemPrompt.contains("\n"))
    }

    @Test func keepsOnlyTheCorrectedText() {
        #expect(DictationCorrection.correctedText(from: "  A las 5:30, comprar pan.\n") == "A las 5:30, comprar pan.")
        #expect(DictationCorrection.correctedText(from: "<think>Hay que poner acentos.</think>\n¿Qué día es?") == "¿Qué día es?")
        #expect(DictationCorrection.correctedText(from: "Línea uno.\nLínea dos.") == "Línea uno.\nLínea dos.")
    }

    @Test func dropsQuotesAroundTheWholeText() {
        #expect(DictationCorrection.correctedText(from: "\"Comprar pan.\"") == "Comprar pan.")
        #expect(DictationCorrection.correctedText(from: "«¡Qué bien!»") == "¡Qué bien!")
        #expect(DictationCorrection.correctedText(from: "“Llamar a Ana.”") == "Llamar a Ana.")
        #expect(DictationCorrection.correctedText(from: "\"Sí\" y \"no\"") == "\"Sí\" y \"no\"")
    }

    @Test func emptyRepliesGiveNothing() {
        #expect(DictationCorrection.correctedText(from: "  \n") == nil)
        #expect(DictationCorrection.correctedText(from: "<think>Nada que decir</think>") == nil)
        #expect(DictationCorrection.correctedText(from: "\"\"") == nil)
    }
}
