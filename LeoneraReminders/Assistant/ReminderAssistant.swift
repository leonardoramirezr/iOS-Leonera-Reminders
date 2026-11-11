import Foundation
import UIKit

/// Crea recordatorios con Groq usando los modelos elegidos en Configuración y la clave del llavero:
/// voz a texto (Whisper) y texto o fotos a recordatorios (LLM).
@MainActor
enum ReminderAssistant {
    /// Fotos por petición (el modelo de visión de Groq acepta hasta 3).
    static let maxImages = 3

    static func transcribe(audioAt url: URL) async throws -> String {
        let settings = SettingsStore.shared.settings.assistant
        let audio = try Data(contentsOf: url)
        return try await client().transcribe(
            audio: audio,
            fileName: url.lastPathComponent,
            model: settings.transcriptionModel,
            language: settings.transcriptionLanguage
        )
    }

    /// Recordatorios propuestos a partir de una nota (dictada o escrita) o de fotos con indicaciones opcionales.
    static func reminders(from text: String, images: [Data] = []) async throws -> [ReminderExtraction.Draft] {
        let settings = SettingsStore.shared.settings.assistant
        let withImages = !images.isEmpty
        let now = Date()
        let messages: [GroqAPI.ChatMessage] = [
            .system(ReminderExtraction.systemPrompt(now: now, calendar: .current, withImages: withImages)),
            .user(ReminderExtraction.userPrompt(text: text, withImages: withImages), images: images),
        ]
        let content = try await client().complete(model: withImages ? settings.visionModel : settings.textModel, messages: messages)
        return try ReminderExtraction.parse(content, now: Date())
    }

    /// Text dictated into a note with its punctuation, signs, accents and spelling corrected by the correction
    /// model (see `DictationCorrection`).
    static func correctDictation(_ transcript: String) async throws -> String {
        let model = SettingsStore.shared.settings.assistant.correctionModel
        let content = try await client().complete(
            model: model,
            messages: DictationCorrection.messages(for: transcript),
            responseFormat: nil
        )
        guard let corrected = DictationCorrection.correctedText(from: content) else { throw GroqAPI.APIError.emptyResponse }
        return corrected
    }

    static func listModels() async throws -> [String] {
        try await client().listModels()
    }

    private static func client() throws -> GroqClient {
        guard let key = GroqKeyStore.shared.key else { throw GroqAPI.APIError.missingKey }
        return GroqClient(apiKey: key)
    }

    /// JPEG de hasta `maxDimension` px por lado (con la orientación ya aplicada) para mandarlo al modelo.
    static func jpegForUpload(_ image: UIImage, maxDimension: CGFloat = 1600) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
