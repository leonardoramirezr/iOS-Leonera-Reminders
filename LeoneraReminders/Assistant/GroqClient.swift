import Foundation

/// Hace las peticiones a la API de Groq (los formatos están en `GroqAPI`).
struct GroqClient: Sendable {
    let apiKey: String
    var session: URLSession = .shared

    /// Voz a texto con Whisper.
    func transcribe(audio: Data, fileName: String, model: String, language: String) async throws -> String {
        let form = GroqAPI.transcriptionForm(audio: audio, fileName: fileName, model: model, language: language)
        var request = makeRequest(GroqAPI.transcriptionPath, method: "POST", timeout: 120)
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.body
        let data = try await send(request)
        guard let response = try? JSONDecoder().decode(GroqAPI.TranscriptionResponse.self, from: data) else {
            throw GroqAPI.APIError.invalidResponse
        }
        return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Respuesta del modelo de chat, en modo JSON salvo que `responseFormat` sea `nil` (texto libre).
    func complete(
        model: String,
        messages: [GroqAPI.ChatMessage],
        responseFormat: GroqAPI.ChatRequest.ResponseFormat? = .jsonObject
    ) async throws -> String {
        var request = makeRequest(GroqAPI.chatPath, method: "POST", timeout: 120)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GroqAPI.ChatRequest(model: model, messages: messages, responseFormat: responseFormat)
        )
        let data = try await send(request)
        guard let response = try? JSONDecoder().decode(GroqAPI.ChatResponse.self, from: data) else {
            throw GroqAPI.APIError.invalidResponse
        }
        return try response.content()
    }

    /// Ids de los modelos activos de la cuenta.
    func listModels() async throws -> [String] {
        let data = try await send(makeRequest(GroqAPI.modelsPath, method: "GET", timeout: 30))
        guard let list = try? JSONDecoder().decode(GroqAPI.ModelList.self, from: data) else {
            throw GroqAPI.APIError.invalidResponse
        }
        return list.activeIDs
    }

    private func makeRequest(_ path: String, method: String, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: URL(string: GroqAPI.baseURL + path)!, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GroqAPI.APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw GroqAPI.error(status: http.statusCode, body: data)
        }
        return data
    }
}
