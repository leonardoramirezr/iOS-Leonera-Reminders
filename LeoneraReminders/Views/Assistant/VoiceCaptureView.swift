import SwiftUI

/// Creates reminders by voice. Stopping the recording turns it into text and creates the reminders right away, which
/// are reviewed on the same screen. From there the text can be edited, recorded again from scratch, or added to by
/// voice; each change creates the reminders again from the whole text.
struct VoiceCaptureView: View {
    @Environment(ReminderStore.self) private var store
    @Environment(GroqKeyStore.self) private var keyStore
    @Environment(\.dismiss) private var dismiss

    @State private var dictation = DictationSession()
    /// Text the reminders were created from: everything dictated so far, with the corrections made to it.
    @State private var transcript = ""
    @State private var isProcessing = false
    @State private var processError: String?
    @State private var processTask: Task<Void, Never>?
    @State private var review: ReminderReview?
    @State private var isEditingText = false
    @State private var editedText = ""

    private var trimmedTranscript: String { transcript.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var transcriptActions: TranscriptActions {
        TranscriptActions(onEdit: startEditing, onRedo: startOver, onAddMore: addMore)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let review {
                    ReminderReviewView(review: review, transcriptActions: transcriptActions) { reminders in
                        store.add(contentsOf: reminders)
                        close()
                    }
                    .id(review.id)
                } else {
                    captureStage
                        .navigationTitle("Nuevo con la voz")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { close() }
                }
            }
            .sheet(isPresented: $isEditingText) {
                editTextSheet
            }
        }
        .interactiveDismissDisabled(!transcript.isEmpty || isProcessing)
        .task {
            // Tocar «Voz» ya es la intención de hablar: empieza a grabar sin otro toque.
            if keyStore.hasKey { await dictation.start() }
        }
        .onDisappear {
            // Presenting the edit sheet also triggers this, and nothing needs stopping then.
            guard !isEditingText else { return }
            dictation.cancel()
            processTask?.cancel()
        }
    }

    @ViewBuilder
    private var captureStage: some View {
        if !keyStore.hasKey {
            AssistantSetupPrompt()
        } else if isProcessing {
            processingStage
        } else if processError != nil {
            processErrorStage
        } else {
            recordingStage
        }
    }

    // MARK: - Grabar

    private var recordingStage: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(statusTitle)
                .font(.title3.weight(.semibold))
            Text("Di uno o varios recordatorios, por ejemplo: «mañana a las 9 llamar al dentista y todos los lunes sacar la basura».")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            RecordButton(phase: dictation.phase, level: dictation.recorder.level, action: toggleRecording)
            if dictation.phase == .recording {
                ElapsedText(since: dictation.recorder.startedAt)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            if let error = dictation.error {
                VStack(spacing: 10) {
                    DictationErrorView(session: dictation, error: error, onText: append)
                }
                .multilineTextAlignment(.center)
            }
            Spacer()
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .onChange(of: dictation.recorder.reachedLimit) { _, reached in
            if reached { toggleRecording() }
        }
    }

    private var statusTitle: String {
        switch dictation.phase {
        case .idle: "Toca para hablar"
        case .recording: "Escuchando…"
        case .transcribing: "Convirtiendo a texto…"
        }
    }

    private func toggleRecording() {
        switch dictation.phase {
        case .idle:
            Task { await dictation.start() }
        case .recording:
            Task { if let text = await dictation.finish() { append(text) } }
        case .transcribing:
            break
        }
    }

    /// Adds dictated text to what is already there and creates the reminders from all of it.
    private func append(_ text: String) {
        transcript = trimmedTranscript.isEmpty ? text : trimmedTranscript + " " + text
        process()
    }

    private func startOver() {
        transcript = ""
        startRecording()
    }

    private func addMore() {
        startRecording()
    }

    private func startRecording() {
        review = nil
        processError = nil
        Task { await dictation.start() }
    }

    // MARK: - Editar el texto

    private func startEditing() {
        editedText = transcript
        isEditingText = true
    }

    private var editTextSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Lo que dijiste", text: $editedText, axis: .vertical)
                        .lineLimit(4...12)
                } footer: {
                    Text("Al guardar, los recordatorios se vuelven a crear con este texto.")
                }
            }
            .navigationTitle("Editar el texto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { isEditingText = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { applyEdit() }
                        .disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func applyEdit() {
        isEditingText = false
        let text = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != trimmedTranscript else { return }
        transcript = text
        process()
    }

    // MARK: - Procesar

    private var processingStage: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Creando recordatorios…")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var processErrorStage: some View {
        ContentUnavailableView {
            Label("No se pudieron crear los recordatorios", systemImage: "exclamationmark.triangle")
        } description: {
            Text(processError ?? "")
        } actions: {
            Button("Reintentar") { process() }
                .buttonStyle(.borderedProminent)
            Button("Editar el texto", action: startEditing)
            Button("Volver a grabar", action: startOver)
        }
    }

    /// Creates the reminders from the current text. The review replaces the capture screen once they are ready.
    private func process() {
        let text = trimmedTranscript
        review = nil
        processError = nil
        isProcessing = true
        processTask = Task {
            defer { isProcessing = false }
            do {
                let drafts = try await ReminderAssistant.reminders(from: text)
                guard !Task.isCancelled else { return }
                review = ReminderReview(drafts: drafts, sourceText: text)
            } catch {
                guard !Task.isCancelled else { return }
                processError = error.localizedDescription
            }
        }
    }

    private func close() {
        dictation.cancel()
        processTask?.cancel()
        dismiss()
    }
}

/// «Crear recordatorios», abajo de la pantalla; mientras el modelo responde muestra un indicador.
struct ProcessButton: View {
    let isProcessing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isProcessing {
                    ProgressView()
                        .tint(.white)
                    Text("Creando recordatorios…")
                } else {
                    Image(systemName: "sparkles")
                    Text("Crear recordatorios")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.brand)
        .disabled(isProcessing)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
