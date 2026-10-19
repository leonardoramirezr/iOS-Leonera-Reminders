import SwiftUI
import UIKit

struct ReminderEditorView: View {
    @Environment(ReminderStore.self) private var store
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss

    let target: EditorTarget
    @State private var draft: Reminder
    @State private var confirmDelete = false
    @FocusState private var titleFocused: Bool

    init(target: EditorTarget, existing: Reminder?) {
        self.target = target
        _draft = State(initialValue: existing ?? Reminder(title: "", dueDate: Reminder.defaultDueDate()))
    }

    private var isNew: Bool { target.reminderID == nil }
    private var trimmedTitle: String { draft.title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Cambiar la fecha límite reprograma la ocurrencia.
    private var dueDate: Binding<Date> {
        Binding(get: { draft.dueDate }, set: { draft.reschedule(to: $0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Título", text: $draft.title, axis: .vertical)
                        .focused($titleFocused)
                }

                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DateText.relative(draft.dueDate))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(draft.dueDate <= Date() ? Color.red : Color.primary)
                        Text(DateText.full(draft.dueDate))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    DatePicker("Fecha y hora", selection: dueDate)
                    QuickAdjustGridView(grid: settingsStore.settings.quickAdjustGrid) { _, _, cell in
                        let adjusted = cell.apply(to: draft.dueDate, overdueBase: settingsStore.settings.overdueAdditionBase)
                        vibrate()
                        withAnimation(.snappy) { dueDate.wrappedValue = adjusted }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Fecha límite")
                }

                Section {
                    NavigationLink {
                        RepeatRuleEditorView(rule: $draft.repeatRule, dueDate: draft.dueDate)
                    } label: {
                        LabeledContent {
                            Text(draft.repeatRule?.summary() ?? "Nunca")
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Label("Repetir", systemImage: "repeat")
                        }
                    }
                }

                if !isNew {
                    Section {
                        if draft.isCompleted {
                            Button("Marcar como pendiente") { draft.markIncomplete() }
                        } else {
                            SlideToConfirm(title: draft.repeatRule == nil ? "Desliza para completar" : "Desliza para completar esta vez") {
                                draft.complete()
                                save(vibrating: false)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        }
                        Button("Eliminar recordatorio", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "Nuevo recordatorio" : "Editar recordatorio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        vibrate()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .confirmationDialog("¿Eliminar este recordatorio?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Eliminar", role: .destructive) {
                    store.delete(ids: [draft.id])
                    dismiss()
                }
            }
            .onAppear {
                if isNew { titleFocused = true }
            }
        }
    }

    /// La misma vibración que al completar (`SlideToConfirm` ya vibra por su cuenta).
    private func save(vibrating: Bool = true) {
        guard !trimmedTitle.isEmpty else { return }
        if vibrating { vibrate() }
        var reminder = draft
        reminder.title = trimmedTitle
        if isNew {
            store.add(reminder)
        } else {
            store.update(reminder)
        }
        dismiss()
    }

    /// Vibra igual que al marcar como completado. Se lanza directo porque Guardar y Cancelar cierran la hoja
    /// y un `.sensoryFeedback` ya no alcanzaría a sonar.
    private func vibrate() {
        Haptics.success()
    }
}
