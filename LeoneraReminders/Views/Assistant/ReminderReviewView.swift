import SwiftUI

/// Lo que el modelo propuso y de dónde salió.
struct ReminderReview: Identifiable, Hashable {
    let id = UUID()
    var drafts: [ReminderExtraction.Draft]
    /// Texto que se mandó al modelo: el dictado (ya corregido), o las indicaciones de las fotos.
    var sourceText: String
    var photoCount = 0
}

/// What the review offers to change the dictated text, when the reminders come from the voice.
struct TranscriptActions {
    let onEdit: () -> Void
    let onRedo: () -> Void
    let onAddMore: () -> Void
}

/// Revisión antes de guardar: todos los recordatorios en una sola lista, cada uno con su título, fecha y repetición
/// editables ahí mismo, para revisarlos y corregirlos sólo desplazándose.
struct ReminderReviewView: View {
    let review: ReminderReview
    /// Si se pasa, la sección del texto muestra el dictado con botones para cambiarlo.
    let transcriptActions: TranscriptActions?
    let onSave: ([Reminder]) -> Void

    @State private var drafts: [ReminderExtraction.Draft]

    init(review: ReminderReview, transcriptActions: TranscriptActions? = nil, onSave: @escaping ([Reminder]) -> Void) {
        self.review = review
        self.transcriptActions = transcriptActions
        self.onSave = onSave
        _drafts = State(initialValue: review.drafts)
    }

    private var missingTitles: Bool {
        drafts.contains { $0.reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            Form {
                sourceSection
                if drafts.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No se encontraron recordatorios",
                            systemImage: "questionmark.bubble",
                            description: Text("Vuelve para cambiar el texto o agrega uno a mano.")
                        )
                    }
                }
                ForEach($drafts) { $draft in
                    Section {
                        ReminderDraftEditor(draft: $draft, now: context.date)
                    } header: {
                        header(for: draft)
                    }
                }
                Section {
                    Button {
                        withAnimation {
                            drafts.append(ReminderExtraction.Draft(reminder: Reminder(title: "", dueDate: Reminder.defaultDueDate())))
                        }
                    } label: {
                        Label("Agregar otro recordatorio", systemImage: "plus")
                    }
                } footer: {
                    if missingTitles {
                        Text("Cada recordatorio necesita un título; escríbelo o quita el recordatorio.")
                    }
                }
            }
        }
        .navigationTitle(drafts.count > 1 ? "Revisa \(drafts.count) recordatorios" : "Revisa el recordatorio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") { save() }
                    .disabled(drafts.isEmpty || missingTitles)
            }
        }
    }

    @ViewBuilder
    private var sourceSection: some View {
        let text = review.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let transcriptActions {
            Section {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action: transcriptActions.onRedo) {
                    Label("Volver a hacer", systemImage: "arrow.counterclockwise")
                }
                Button(action: transcriptActions.onAddMore) {
                    Label("Agregar más", systemImage: "mic.badge.plus")
                }
            } header: {
                HStack {
                    Text("Lo que dijiste")
                    Spacer()
                    Button(action: transcriptActions.onEdit) {
                        Label("Editar el texto", systemImage: "pencil")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                }
            }
        } else if !text.isEmpty || review.photoCount > 0 {
            Section {
                if review.photoCount > 0 {
                    Label(review.photoCount == 1 ? "1 foto" : "\(review.photoCount) fotos", systemImage: "photo")
                        .foregroundStyle(.secondary)
                }
                if !text.isEmpty {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Lo que se envió")
            } footer: {
                Text("Para cambiarlo, vuelve atrás y procésalo de nuevo.")
            }
        }
    }

    private func header(for draft: ReminderExtraction.Draft) -> some View {
        let index = (drafts.firstIndex { $0.id == draft.id } ?? 0) + 1
        return HStack {
            Text(drafts.count > 1 ? "Recordatorio \(index) de \(drafts.count)" : "Recordatorio")
            Spacer()
            Button(role: .destructive) {
                withAnimation { drafts.removeAll { $0.id == draft.id } }
            } label: {
                Label("Quitar", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Quitar el recordatorio \(index)")
        }
    }

    private func save() {
        let now = Date()
        onSave(drafts.map { draft in
            var reminder = draft.reminder
            reminder.title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
            reminder.createdAt = now
            return reminder
        })
    }
}

/// Versión corta del editor de un recordatorio: título, fecha límite y repetición, todo a la vista.
struct ReminderDraftEditor: View {
    @Binding var draft: ReminderExtraction.Draft
    let now: Date

    private var isPast: Bool { draft.reminder.dueDate <= now }

    var body: some View {
        TextField("Título", text: $draft.reminder.title, axis: .vertical)
            .font(.headline)

        DatePicker(selection: dueDate) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DateText.relative(draft.reminder.dueDate, now: now))
                    .foregroundStyle(isPast ? Color.red : Color.primary)
                if isPast {
                    Text("Ya pasó: sonará en cuanto lo guardes")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }

        CompactRepeatEditor(rule: repeatRule, dueDate: draft.reminder.dueDate)

        ForEach(draft.notes, id: \.self) { note in
            Label(note.message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    /// En un recordatorio nuevo la repetición suena a la misma hora que la fecha límite, así que la sigue.
    private var dueDate: Binding<Date> {
        Binding(
            get: { draft.reminder.dueDate },
            set: { date in
                draft.reminder.reschedule(to: date)
                draft.reminder.repeatRule?.time = TimeOfDay(of: date)
                draft.notes.removeAll(where: \.isAboutDate)
            }
        )
    }

    /// Al cambiar la repetición, la fecha pasa a su primera ocurrencia (p. ej. al elegir otro día de la semana).
    private var repeatRule: Binding<RepeatRule?> {
        Binding(
            get: { draft.reminder.repeatRule },
            set: { rule in
                draft.reminder.repeatRule = rule
                draft.reminder.alignDueDateToRepeatRule()
                draft.notes.removeAll { !$0.isAboutDate }
            }
        )
    }
}

/// Repetición editable en línea (sin abrir otra pantalla): frecuencia, cada cuánto y, según el caso,
/// días de la semana, día del mes o fecha del año. La hora es la de la fecha límite.
struct CompactRepeatEditor: View {
    @Binding var rule: RepeatRule?
    let dueDate: Date

    var body: some View {
        Picker(selection: frequency) {
            Text("Nunca").tag(RepeatRule.Frequency?.none)
            ForEach(RepeatRule.Frequency.allCases) { frequency in
                Text(frequency.label).tag(RepeatRule.Frequency?.some(frequency))
            }
        } label: {
            Label("Repetir", systemImage: "repeat")
        }
        .pickerStyle(.menu)

        if let current = rule {
            Stepper(value: field(\.interval), in: 1...99) {
                Text("Cada \(current.interval) \(current.unitName(for: current.interval))")
            }
            details(for: current)
            Text(current.summary())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func details(for current: RepeatRule) -> some View {
        switch current.frequency {
        case .weekly:
            WeekdayPicker(selection: field(\.weekdays))
                .padding(.vertical, 4)
        case .monthly:
            MonthlyRepeatFields(rule: nonOptionalRule, dueDate: dueDate)
                .pickerStyle(.menu)
        case .yearly:
            Picker("Mes", selection: field(\.month)) {
                ForEach(1...12, id: \.self) { month in
                    Text(SpanishNames.months[month].capitalized).tag(month)
                }
            }
            .pickerStyle(.menu)
            Picker("Día", selection: field(\.dayOfMonth)) {
                ForEach(1...RepeatRule.daysIn(year: 2028, month: current.month, calendar: .current), id: \.self) { day in
                    Text("\(day)").tag(day)
                }
            }
            .pickerStyle(.menu)
        case .hourly, .daily:
            EmptyView()
        }
    }

    /// Cambiar de frecuencia toma los días de la fecha límite (y conserva cada cuánto).
    private var frequency: Binding<RepeatRule.Frequency?> {
        Binding(
            get: { rule?.frequency },
            set: { frequency in
                guard let frequency else {
                    rule = nil
                    return
                }
                rule = RepeatRule.matching(dueDate, frequency: frequency, interval: rule?.interval ?? 1)
            }
        )
    }

    private var nonOptionalRule: Binding<RepeatRule> {
        Binding(
            get: { rule ?? RepeatRule.matching(dueDate, frequency: .monthly) },
            set: { rule = $0 }
        )
    }

    private func field<Value>(_ keyPath: WritableKeyPath<RepeatRule, Value>) -> Binding<Value> {
        Binding(
            get: { (rule ?? RepeatRule.matching(dueDate, frequency: .daily))[keyPath: keyPath] },
            set: { rule?[keyPath: keyPath] = $0 }
        )
    }
}
