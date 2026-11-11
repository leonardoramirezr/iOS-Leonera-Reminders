import Foundation

/// Formatos de la API de Groq (compatible con la de OpenAI) que usa el asistente. Aquí sólo se arman y leen
/// los cuerpos; las peticiones las hace `GroqClient` en la app.
enum GroqAPI {
    static let baseURL = "https://api.groq.com/openai/v1/"
    static let chatPath = "chat/completions"
    static let transcriptionPath = "audio/transcriptions"
    static let modelsPath = "models"

    // MARK: - Chat

    struct ChatMessage: Encodable, Hashable, Sendable {
        enum Role: String, Encodable, Sendable {
            case system, user
        }

        enum Part: Hashable, Sendable {
            case text(String)
            /// Imagen JPEG; se manda como data URL en base64.
            case jpeg(Data)

            var text: String? {
                if case .text(let value) = self { value } else { nil }
            }
        }

        var role: Role
        var parts: [Part]

        static func system(_ text: String) -> ChatMessage {
            ChatMessage(role: .system, parts: [.text(text)])
        }

        static func user(_ text: String, images: [Data] = []) -> ChatMessage {
            ChatMessage(role: .user, parts: [.text(text)] + images.map(Part.jpeg))
        }

        private enum CodingKeys: String, CodingKey {
            case role, content
        }

        private enum PartKeys: String, CodingKey {
            case type, text
            case imageURL = "image_url"
        }

        private enum ImageKeys: String, CodingKey {
            case url
        }

        /// Sólo texto: `"content": "…"`. Con imágenes: `"content": [{"type": "text", …}, {"type": "image_url", …}]`.
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(role, forKey: .role)
            if parts.allSatisfy({ $0.text != nil }) {
                try c.encode(parts.compactMap(\.text).joined(separator: "\n\n"), forKey: .content)
                return
            }
            var list = c.nestedUnkeyedContainer(forKey: .content)
            for part in parts {
                var item = list.nestedContainer(keyedBy: PartKeys.self)
                switch part {
                case .text(let text):
                    try item.encode("text", forKey: .type)
                    try item.encode(text, forKey: .text)
                case .jpeg(let data):
                    try item.encode("image_url", forKey: .type)
                    var image = item.nestedContainer(keyedBy: ImageKeys.self, forKey: .imageURL)
                    try image.encode("data:image/jpeg;base64,\(data.base64EncodedString())", forKey: .url)
                }
            }
        }
    }

    struct ChatRequest: Encodable, Sendable {
        struct ResponseFormat: Encodable, Sendable {
            var type: String
            static let jsonObject = ResponseFormat(type: "json_object")
        }

        var model: String
        var messages: [ChatMessage]
        var temperature: Double? = 0.2
        var responseFormat: ResponseFormat? = .jsonObject

        private enum CodingKeys: String, CodingKey {
            case model, messages, temperature
            case responseFormat = "response_format"
        }
    }

    /// The reply without the reasoning that some models (such as Qwen) write before it, between
    /// `<think>` and `</think>`. An unclosed block is dropped to the end.
    static func removingReasoning(from content: String) -> String {
        var text = content
        while let open = text.range(of: "<think>") {
            let close = text.range(of: "</think>", range: open.upperBound..<text.endIndex)
            text.removeSubrange(open.lowerBound..<(close?.upperBound ?? text.endIndex))
        }
        return text
    }

    struct ChatResponse: Decodable, Sendable {
        struct Choice: Decodable, Sendable {
            struct Message: Decodable, Sendable {
                var content: String?
            }

            var message: Message
            var finishReason: String?

            private enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }

        var choices: [Choice]

        /// El texto de la respuesta; error si viene vacía o se cortó por longitud.
        func content() throws -> String {
            guard let choice = choices.first else { throw APIError.emptyResponse }
            if choice.finishReason == "length" { throw APIError.truncated }
            guard let content = choice.message.content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw APIError.emptyResponse }
            return content
        }
    }

    // MARK: - Voz a texto

    struct TranscriptionResponse: Decodable, Sendable {
        var text: String
    }

    /// Formulario `multipart/form-data` para `audio/transcriptions`.
    static func transcriptionForm(audio: Data, fileName: String, model: String, language: String) -> MultipartForm {
        var form = MultipartForm()
        form.addField("model", model)
        form.addField("response_format", "json")
        form.addField("temperature", "0")
        let language = language.trimmingCharacters(in: .whitespacesAndNewlines)
        if !language.isEmpty { form.addField("language", language) }
        form.addFile("file", fileName: fileName, mimeType: mimeType(forAudioFile: fileName), data: audio)
        return form
    }

    static func mimeType(forAudioFile fileName: String) -> String {
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "m4a", "mp4": "audio/mp4"
        case "mp3", "mpeg", "mpga": "audio/mpeg"
        case "wav": "audio/wav"
        case "ogg": "audio/ogg"
        case "webm": "audio/webm"
        case "flac": "audio/flac"
        default: "application/octet-stream"
        }
    }

    struct MultipartForm: Sendable {
        let boundary: String
        private var parts = Data()

        init(boundary: String = "LeoneraBoundary-\(UUID().uuidString)") {
            self.boundary = boundary
        }

        var contentType: String { "multipart/form-data; boundary=\(boundary)" }

        mutating func addField(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        mutating func addFile(_ name: String, fileName: String, mimeType: String, data: Data) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n")
            append("Content-Type: \(mimeType)\r\n\r\n")
            parts.append(data)
            append("\r\n")
        }

        /// El cuerpo completo, con el delimitador final.
        var body: Data {
            parts + Data("--\(boundary)--\r\n".utf8)
        }

        private mutating func append(_ text: String) {
            parts.append(Data(text.utf8))
        }
    }

    // MARK: - Modelos

    struct ModelList: Decodable, Sendable {
        struct Model: Decodable, Sendable {
            var id: String
            var active: Bool?
        }

        var data: [Model]

        /// Ids de los modelos activos, ordenados.
        var activeIDs: [String] {
            data.filter { $0.active ?? true }.map(\.id).sorted()
        }
    }

    // MARK: - Errores

    enum APIError: Error, Equatable, LocalizedError {
        case missingKey
        case http(status: Int, message: String?, code: String?)
        case emptyResponse
        case truncated
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "Falta la clave de API de Groq. Agrégala en Configuración → Asistente."
            case .emptyResponse:
                return "Groq no devolvió ningún texto. Intenta de nuevo."
            case .truncated:
                return "La respuesta de Groq se cortó antes de terminar. Intenta con una nota más corta."
            case .invalidResponse:
                return "Groq devolvió una respuesta que no se pudo leer."
            case .http(let status, let message, let code):
                let detail = message.map { "\n\n\($0)" } ?? ""
                if code == "model_not_found" || code == "model_decommissioned" {
                    return "El modelo no existe o ya no está disponible en tu cuenta. Elige otro en Configuración → Asistente.\(detail)"
                }
                if code == "json_validate_failed" {
                    return "El modelo no devolvió recordatorios en el formato esperado. Intenta de nuevo o elige otro modelo.\(detail)"
                }
                switch status {
                case 401:
                    return "Groq rechazó la clave de API. Revísala en Configuración → Asistente."
                case 413:
                    return "El audio o las fotos son demasiado grandes para Groq.\(detail)"
                case 429:
                    return "Se alcanzó el límite de uso de Groq. Espera un momento e intenta de nuevo.\(detail)"
                case 500...:
                    return "Groq no está disponible ahora (error \(status)). Intenta de nuevo en un momento."
                default:
                    return "Groq respondió con un error (\(status)).\(detail)"
                }
            }
        }
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable {
            var message: String?
            var code: String?
        }

        var error: Detail
    }

    /// Error a partir de una respuesta HTTP que no fue 2xx.
    static func error(status: Int, body: Data) -> APIError {
        let detail = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error
        let message = detail?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .http(status: status, message: message?.isEmpty == false ? message : nil, code: detail?.code)
    }
}
