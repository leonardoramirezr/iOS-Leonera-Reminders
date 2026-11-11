import Foundation

/// Para qué se usa un modelo de Groq en el asistente que crea recordatorios.
enum AssistantModelRole: String, CaseIterable, Sendable, Identifiable {
    /// Voz a texto (Whisper).
    case transcription
    /// Convierte el texto (dictado o escrito) en recordatorios.
    case text
    /// Convierte fotos (con texto opcional) en recordatorios; tiene que aceptar imágenes.
    case vision
    /// Corrects the punctuation, accents and spelling of text dictated into a note.
    case correction

    var id: String { rawValue }

    var label: String {
        switch self {
        case .transcription: "Voz a texto"
        case .text: "Texto a recordatorios"
        case .vision: "Fotos a recordatorios"
        case .correction: "Corregir dictado"
        }
    }
}

/// Modelos de Groq y opciones del asistente que crea recordatorios a partir de voz, texto o fotos.
/// La clave de API no va aquí: se guarda en el llavero.
struct AssistantSettings: Codable, Hashable, Sendable {
    var transcriptionModel: String
    var textModel: String
    var visionModel: String
    var correctionModel: String
    /// Whether text dictated into a note goes through `correctionModel` before it is written.
    var correctsDictation: Bool
    /// Idioma del dictado (código ISO 639-1); vacío para que Whisper lo detecte.
    var transcriptionLanguage: String
    /// Modelos que devolvió la API de Groq la última vez que se consultaron (para elegir en Configuración).
    var availableModels: [String]

    static let `default` = AssistantSettings(
        transcriptionModel: "whisper-large-v3-turbo",
        textModel: "openai/gpt-oss-120b",
        visionModel: "qwen/qwen3.8-27b",
        correctionModel: "openai/gpt-oss-120b",
        correctsDictation: false,
        transcriptionLanguage: "es",
        availableModels: []
    )

    /// Modelos que se ofrecen aunque no se haya consultado la API. Groq cambia su catálogo seguido, así que en
    /// Configuración se puede actualizar la lista o escribir cualquier otro.
    static func suggestedModels(for role: AssistantModelRole) -> [String] {
        switch role {
        case .transcription: ["whisper-large-v3-turbo", "whisper-large-v3"]
        case .text: ["openai/gpt-oss-120b", "openai/gpt-oss-20b", "qwen/qwen3.8-27b"]
        case .vision: ["qwen/qwen3.8-27b"]
        case .correction: ["openai/gpt-oss-120b", "openai/gpt-oss-20b", "qwen/qwen3.8-27b"]
        }
    }

    struct Language: Hashable, Sendable {
        /// Código ISO 639-1; vacío = detectar.
        let code: String
        let name: String
    }

    static let transcriptionLanguages: [Language] = [
        Language(code: "", name: "Detectar automáticamente"),
        Language(code: "es", name: "Español"),
        Language(code: "en", name: "Inglés"),
        Language(code: "pt", name: "Portugués"),
        Language(code: "fr", name: "Francés"),
    ]

    func model(for role: AssistantModelRole) -> String {
        switch role {
        case .transcription: transcriptionModel
        case .text: textModel
        case .vision: visionModel
        case .correction: correctionModel
        }
    }

    mutating func setModel(_ model: String, for role: AssistantModelRole) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch role {
        case .transcription: transcriptionModel = trimmed
        case .text: textModel = trimmed
        case .vision: visionModel = trimmed
        case .correction: correctionModel = trimmed
        }
    }

    /// Modelos de la cuenta que sirven para `role`, sin los sugeridos (que se muestran aparte).
    /// Con fotos se listan todos los de chat: la API no dice cuáles aceptan imágenes.
    func otherAvailableModels(for role: AssistantModelRole) -> [String] {
        let suggested = Set(Self.suggestedModels(for: role))
        return availableModels
            .filter { GroqModelCatalog.kind(of: $0).serves(role) && !suggested.contains($0) }
            .sorted()
    }
}

extension AssistantSettings {
    private enum CodingKeys: String, CodingKey {
        case transcriptionModel, textModel, visionModel, correctionModel, correctsDictation, transcriptionLanguage, availableModels
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AssistantSettings.default
        func model(_ key: CodingKeys, _ fallback: String) -> String {
            guard let value = (try? c.decodeIfPresent(String.self, forKey: key))?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else { return fallback }
            return value
        }
        self.init(
            transcriptionModel: model(.transcriptionModel, fallback.transcriptionModel),
            textModel: model(.textModel, fallback.textModel),
            visionModel: model(.visionModel, fallback.visionModel),
            correctionModel: model(.correctionModel, fallback.correctionModel),
            correctsDictation: (try? c.decodeIfPresent(Bool.self, forKey: .correctsDictation)) ?? fallback.correctsDictation,
            transcriptionLanguage: (try? c.decodeIfPresent(String.self, forKey: .transcriptionLanguage)) ?? fallback.transcriptionLanguage,
            availableModels: (try? c.decodeIfPresent([String].self, forKey: .availableModels)) ?? fallback.availableModels
        )
    }
}

/// Clasifica los modelos que devuelve `GET /models` de Groq por su id (la API no dice para qué sirve cada uno).
enum GroqModelCatalog {
    enum Kind: Equatable, Sendable {
        case transcription
        case chat
        /// Texto a voz, clasificadores de seguridad, etc.: no sirven aquí.
        case unsupported

        func serves(_ role: AssistantModelRole) -> Bool {
            switch (self, role) {
            case (.transcription, .transcription): true
            case (.chat, .text), (.chat, .vision), (.chat, .correction): true
            default: false
            }
        }
    }

    static func kind(of id: String) -> Kind {
        let lowered = id.lowercased()
        if lowered.contains("whisper") { return .transcription }
        let unsupported = ["tts", "orpheus", "playai", "guard"]
        if unsupported.contains(where: lowered.contains) { return .unsupported }
        return .chat
    }
}
