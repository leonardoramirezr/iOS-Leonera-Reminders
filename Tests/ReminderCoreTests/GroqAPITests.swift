import Foundation
import Testing
@testable import ReminderCore

struct GroqAPITests {
    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func textOnlyMessagesSendContentAsAString() throws {
        let request = GroqAPI.ChatRequest(model: "openai/gpt-oss-120b", messages: [.system("Reglas"), .user("Nota:\nComprar pan")])
        let body = try json(request)
        #expect(body["model"] as? String == "openai/gpt-oss-120b")
        #expect((body["response_format"] as? [String: Any])?["type"] as? String == "json_object")
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["system", "user"])
        #expect(messages[1]["content"] as? String == "Nota:\nComprar pan")
    }

    @Test func plainTextRequestsSendNoResponseFormat() throws {
        let request = GroqAPI.ChatRequest(model: "openai/gpt-oss-120b", messages: [.user("hola")], responseFormat: nil)
        let body = try json(request)
        #expect(body["response_format"] == nil)
        #expect(body["model"] as? String == "openai/gpt-oss-120b")
    }

    @Test func reasoningIsRemovedFromReplies() {
        #expect(GroqAPI.removingReasoning(from: "<think>Primero…</think>\nHola.") == "\nHola.")
        #expect(GroqAPI.removingReasoning(from: "<think>a</think>Uno <think>b</think>dos") == "Uno dos")
        #expect(GroqAPI.removingReasoning(from: "Texto <think>sin cerrar") == "Texto ")
        #expect(GroqAPI.removingReasoning(from: "Sin razonamiento") == "Sin razonamiento")
    }

    @Test func imagesAreSentAsDataURLParts() throws {
        let image = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let request = GroqAPI.ChatRequest(model: "qwen/qwen3.8-27b", messages: [.user("Indicaciones", images: [image, image])])
        let messages = try #require(try json(request)["messages"] as? [[String: Any]])
        let parts = try #require(messages[0]["content"] as? [[String: Any]])
        #expect(parts.map { $0["type"] as? String } == ["text", "image_url", "image_url"])
        #expect(parts[0]["text"] as? String == "Indicaciones")
        #expect((parts[1]["image_url"] as? [String: Any])?["url"] as? String == "data:image/jpeg;base64,/9j/4A==")
    }

    @Test func chatResponseContent() throws {
        let ok = #"{"choices":[{"message":{"role":"assistant","content":"{\"reminders\":[]}"},"finish_reason":"stop"}]}"#
        #expect(try JSONDecoder().decode(GroqAPI.ChatResponse.self, from: Data(ok.utf8)).content() == #"{"reminders":[]}"#)

        let cut = #"{"choices":[{"message":{"content":"{\"remi"},"finish_reason":"length"}]}"#
        #expect(throws: GroqAPI.APIError.truncated) {
            try JSONDecoder().decode(GroqAPI.ChatResponse.self, from: Data(cut.utf8)).content()
        }
        let empty = #"{"choices":[{"message":{"content":null},"finish_reason":"stop"}]}"#
        #expect(throws: GroqAPI.APIError.emptyResponse) {
            try JSONDecoder().decode(GroqAPI.ChatResponse.self, from: Data(empty.utf8)).content()
        }
    }

    @Test func transcriptionFormHasTheFieldsAndTheFile() throws {
        let audio = Data("AUDIO".utf8)
        let form = GroqAPI.transcriptionForm(audio: audio, fileName: "dictado.m4a", model: "whisper-large-v3-turbo", language: "es")
        let body = try #require(String(data: form.body, encoding: .utf8))
        let b = form.boundary
        #expect(form.contentType == "multipart/form-data; boundary=\(b)")
        #expect(body.hasPrefix("--\(b)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-large-v3-turbo\r\n"))
        #expect(body.contains("name=\"language\"\r\n\r\nes\r\n"))
        #expect(body.contains("name=\"response_format\"\r\n\r\njson\r\n"))
        #expect(body.contains("Content-Disposition: form-data; name=\"file\"; filename=\"dictado.m4a\"\r\nContent-Type: audio/mp4\r\n\r\nAUDIO\r\n"))
        #expect(body.hasSuffix("--\(b)--\r\n"))

        let automatic = GroqAPI.transcriptionForm(audio: audio, fileName: "a.wav", model: "whisper-large-v3", language: " ")
        let automaticBody = try #require(String(data: automatic.body, encoding: .utf8))
        #expect(!automaticBody.contains("name=\"language\""))
        #expect(automaticBody.contains("Content-Type: audio/wav"))
    }

    @Test func errorsReadTheAPIMessage() {
        let body = Data(#"{"error":{"message":"The model `x` does not exist","type":"invalid_request_error","code":"model_not_found"}}"#.utf8)
        let error = GroqAPI.error(status: 404, body: body)
        #expect(error == .http(status: 404, message: "The model `x` does not exist", code: "model_not_found"))
        #expect(error.errorDescription?.hasPrefix("El modelo no existe") == true)
        #expect(error.errorDescription?.hasSuffix("The model `x` does not exist") == true)

        #expect(GroqAPI.error(status: 401, body: Data()).errorDescription == "Groq rechazó la clave de API. Revísala en Configuración → Asistente.")
        #expect(GroqAPI.error(status: 503, body: Data("<html>".utf8)) == .http(status: 503, message: nil, code: nil))
        #expect(GroqAPI.error(status: 429, body: Data()).errorDescription?.contains("límite") == true)
    }

    @Test func modelListKeepsActiveModelsAndClassifiesThem() throws {
        let body = #"""
        {"object":"list","data":[
          {"id":"whisper-large-v3-turbo","object":"model","active":true},
          {"id":"openai/gpt-oss-120b","object":"model","active":true,"context_window":131072},
          {"id":"canopylabs/orpheus-v1-english","active":true},
          {"id":"meta-llama/llama-prompt-guard-2-86m","active":true},
          {"id":"old-model","active":false},
          {"id":"minimaxai/minimax-m2.7"}
        ]}
        """#
        let list = try JSONDecoder().decode(GroqAPI.ModelList.self, from: Data(body.utf8))
        #expect(list.activeIDs == [
            "canopylabs/orpheus-v1-english", "meta-llama/llama-prompt-guard-2-86m", "minimaxai/minimax-m2.7",
            "openai/gpt-oss-120b", "whisper-large-v3-turbo",
        ])
        #expect(list.activeIDs.map(GroqModelCatalog.kind(of:)) == [.unsupported, .unsupported, .chat, .chat, .transcription])

        var settings = AssistantSettings.default
        settings.availableModels = list.activeIDs + ["whisper-large-v3", "openai/gpt-oss-safeguard-20b"]
        #expect(settings.otherAvailableModels(for: .transcription) == [])
        #expect(settings.otherAvailableModels(for: .text) == ["minimaxai/minimax-m2.7"])
        #expect(settings.otherAvailableModels(for: .vision) == ["minimaxai/minimax-m2.7", "openai/gpt-oss-120b"])
        #expect(settings.otherAvailableModels(for: .correction) == ["minimaxai/minimax-m2.7"])
    }
}

struct AssistantSettingsTests {
    @Test func defaultsAndRoundTrip() throws {
        #expect(AppSettings.default.assistant == .default)
        #expect(AssistantSettings.default.transcriptionModel == "whisper-large-v3-turbo")
        #expect(AssistantSettings.default.transcriptionLanguage == "es")
        for role in AssistantModelRole.allCases {
            #expect(AssistantSettings.suggestedModels(for: role).contains(AssistantSettings.default.model(for: role)))
        }

        var settings = AppSettings.default
        settings.assistant.setModel("  qwen/qwen3.8-27b ", for: .text)
        settings.assistant.setModel("", for: .vision)
        settings.assistant.setModel("openai/gpt-oss-20b", for: .correction)
        settings.assistant.correctsDictation = true
        settings.assistant.transcriptionLanguage = ""
        settings.assistant.availableModels = ["a", "b"]
        #expect(settings.assistant.textModel == "qwen/qwen3.8-27b")
        #expect(settings.assistant.visionModel == AssistantSettings.default.visionModel)
        #expect(settings.assistant.model(for: .correction) == "openai/gpt-oss-20b")
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.assistant == settings.assistant)
        #expect(decoded == settings)
    }

    @Test func olderSettingsAndBlankModelsFallBackToDefaults() throws {
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"stopAction":"snooze"}"#.utf8))
        #expect(legacy.assistant == .default)

        let partial = #"{"assistant":{"textModel":"openai/gpt-oss-20b","visionModel":"  ","transcriptionLanguage":""}}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(partial.utf8))
        #expect(decoded.assistant.textModel == "openai/gpt-oss-20b")
        #expect(decoded.assistant.visionModel == AssistantSettings.default.visionModel)
        #expect(decoded.assistant.transcriptionModel == AssistantSettings.default.transcriptionModel)
        #expect(decoded.assistant.transcriptionLanguage == "")
        #expect(decoded.assistant.availableModels.isEmpty)
        // Settings saved before the dictation correction existed: off, with the default model.
        #expect(decoded.assistant.correctionModel == AssistantSettings.default.correctionModel)
        #expect(!decoded.assistant.correctsDictation)
    }

    @Test func dictationCorrectionIsOffByDefault() {
        #expect(!AssistantSettings.default.correctsDictation)
        #expect(AssistantSettings.default.correctionModel == "openai/gpt-oss-120b")
        #expect(GroqModelCatalog.kind(of: "openai/gpt-oss-20b").serves(.correction))
        #expect(!GroqModelCatalog.kind(of: "whisper-large-v3").serves(.correction))
    }
}
