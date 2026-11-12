import SwiftUI

/// Configuración del asistente: clave de API de Groq, modelos e idioma del dictado.
struct AssistantSettingsView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(GroqKeyStore.self) private var keyStore

    @State private var newKey = ""
    @State private var isReplacingKey = false
    @State private var isLoadingModels = false
    @State private var modelsError: String?

    private var assistant: Binding<AssistantSettings> {
        Binding(get: { settingsStore.settings.assistant }, set: { settingsStore.settings.assistant = $0 })
    }

    var body: some View {
        Form {
            keySection
            modelsSection
            dictationSection
        }
        .navigationTitle("Asistente")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Secciones

    private var keySection: some View {
        Section {
            if keyStore.hasKey && !isReplacingKey {
                Label("Clave guardada", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Button("Cambiar clave") { isReplacingKey = true }
                Button("Borrar clave", role: .destructive) { keyStore.delete() }
            } else {
                SecureField("gsk_…", text: $newKey)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(saveKey)
                Button("Guardar clave", action: saveKey)
                    .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if isReplacingKey {
                    Button("Cancelar") {
                        isReplacingKey = false
                        newKey = ""
                    }
                }
            }
            if let error = keyStore.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Clave de API de Groq")
        } footer: {
            Text("Créala en [console.groq.com/keys](https://console.groq.com/keys). Se guarda en el llavero de este iPhone. El audio, el texto y las fotos con que crees recordatorios se envían a Groq.")
        }
    }

    private var modelsSection: some View {
        Section {
            ForEach(AssistantModelRole.allCases) { role in
                NavigationLink {
                    ModelPickerView(role: role)
                } label: {
                    LabeledContent(role.label, value: settingsStore.settings.assistant.model(for: role))
                }
            }
            Button {
                Task { await refreshModels() }
            } label: {
                HStack {
                    Text("Actualizar lista de modelos")
                    Spacer()
                    if isLoadingModels { ProgressView() }
                }
            }
            .disabled(!keyStore.hasKey || isLoadingModels)
            if let modelsError {
                Text(modelsError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Modelos")
        } footer: {
            Text(modelsFooter)
        }
    }

    private var modelsFooter: String {
        let count = settingsStore.settings.assistant.availableModels.count
        let available = count > 0 ? " Tu cuenta tiene \(count) modelos." : ""
        return "Groq cambia sus modelos seguido: actualiza la lista para elegir entre los de tu cuenta. El de fotos tiene que aceptar imágenes.\(available)"
    }

    private var dictationSection: some View {
        Section {
            Picker("Idioma del dictado", selection: assistant.transcriptionLanguage) {
                ForEach(AssistantSettings.transcriptionLanguages, id: \.code) { language in
                    Text(language.name).tag(language.code)
                }
            }
            Toggle("Corregir el dictado de las notas", isOn: assistant.correctsDictation)
        } footer: {
            Text("Indicar el idioma mejora la conversión de voz a texto. Al corregir, el modelo «Corregir dictado» arregla la puntuación, los signos, los acentos y la ortografía de lo que dictas en una nota antes de escribirlo; también se activa con el ícono de destellos junto al micrófono.")
        }
    }

    // MARK: - Acciones

    private func saveKey() {
        guard keyStore.save(newKey) else { return }
        newKey = ""
        isReplacingKey = false
        // También comprueba que la clave funcione.
        Task { await refreshModels() }
    }

    private func refreshModels() async {
        isLoadingModels = true
        modelsError = nil
        defer { isLoadingModels = false }
        do {
            assistant.wrappedValue.availableModels = try await ReminderAssistant.listModels()
        } catch {
            modelsError = error.localizedDescription
        }
    }
}

/// Elegir el modelo para una tarea: los recomendados, los de la cuenta o cualquier otro escribiendo su id.
struct ModelPickerView: View {
    let role: AssistantModelRole

    @Environment(SettingsStore.self) private var settingsStore
    @State private var customModel = ""

    private var assistant: AssistantSettings { settingsStore.settings.assistant }
    private var selected: String { assistant.model(for: role) }

    var body: some View {
        let suggested = AssistantSettings.suggestedModels(for: role)
        let others = assistant.otherAvailableModels(for: role)
        let available = Set(assistant.availableModels)
        List {
            Section("Recomendados") {
                ForEach(suggested, id: \.self) { model in
                    row(model, missing: !available.isEmpty && !available.contains(model))
                }
            }
            if !suggested.contains(selected) && !others.contains(selected) {
                Section("Elegido") {
                    row(selected, missing: !available.isEmpty && !available.contains(selected))
                }
            }
            if !others.isEmpty {
                Section {
                    ForEach(others, id: \.self) { model in
                        row(model, missing: false)
                    }
                } header: {
                    Text("En tu cuenta")
                } footer: {
                    if role == .vision {
                        Text("Groq no indica cuáles aceptan imágenes; si eliges uno que no, fallará al procesar fotos.")
                    }
                }
            }
            Section {
                HStack {
                    TextField("ID del modelo", text: $customModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(useCustomModel)
                    Button("Usar", action: useCustomModel)
                        .disabled(customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Otro modelo")
            } footer: {
                Text("Copia el id de console.groq.com/docs/models, p. ej. «\(AssistantSettings.default.model(for: role))».")
            }
        }
        .navigationTitle(role.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ model: String, missing: Bool) -> some View {
        Button {
            settingsStore.settings.assistant.setModel(model, for: role)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model)
                        .foregroundStyle(Color.primary)
                    if missing {
                        Text("No aparece en tu cuenta")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                if model == selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.brand)
                }
            }
        }
    }

    private func useCustomModel() {
        settingsStore.settings.assistant.setModel(customModel, for: role)
        customModel = ""
    }
}
