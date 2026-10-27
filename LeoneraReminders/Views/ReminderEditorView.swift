import SwiftUI
import UIKit

struct ReminderEditorView: View {
    @Environment(ReminderStore.self) private var store
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss

    let target: EditorTarget
    @State private var draft: Reminder
    @State private var confirmDelete = false
    @State private var choosingChecklist = false
    @State private var editMode = EditMode.inactive
    @FocusState private var titleFocused: Bool
    @FocusState private var focusedItemID: ChecklistItem.ID?

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

    /// Turning the checklist on starts it empty; turning it off drops its checkboxes.
    private var checklistEnabled: Binding<Bool> {
        Binding(get: { draft.checklist != nil }, set: { draft.checklist = $0 ? (draft.checklist ?? []) : nil })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Título", text: $draft.title, axis: .vertical)
                        .focused($titleFocused)
                }

                Section {
                    Toggle("Lista con casillas", isOn: checklistEnabled)
                    if draft.checklist != nil {
                        ForEach(checklistItems) { $item in
                            HStack(spacing: 12) {
                                Button {
                                    $item.isDone.wrappedValue.toggle()
                                } label: {
                                    Image(systemName: item.isDone ? "checkmark.square.fill" : "square")
                                        .font(.title3)
                                        .foregroundStyle(item.isDone ? Color.green : Color.secondary)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(item.isDone ? "Desmarcar casilla" : "Marcar casilla")
                                TextField("Casilla", text: $item.title)
                                    .focused($focusedItemID, equals: item.id)
                            }
                        }
                        .onDelete(perform: deleteChecklistItems)
                        .onMove(perform: moveChecklistItems)
                        Button {
                            addChecklistItem()
                        } label: {
                            Label("Agregar casilla", systemImage: "plus")
                        }
                        // Shown while reordering even with a single checkbox, so there is always a way out of edit mode.
                        if editMode.isEditing || (draft.checklist?.count ?? 0) > 1 {
                            Button {
                                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                            } label: {
                                Label(editMode.isEditing ? "Listo" : "Reordenar casillas", systemImage: "arrow.up.arrow.down")
                            }
                        }
                    }
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

                // Discreet on purpose: a secondary option, not one of the main actions of the reminder.
                if !isNew, draft.checklist == nil {
                    Section {
                        Button {
                            choosingChecklist = true
                        } label: {
                            Label("Agregar a una lista con casillas…", systemImage: "checklist")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
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
                                FireworksPresenter.shared.celebrate()
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        }
                        Button("Eliminar recordatorio", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .environment(\.editMode, $editMode)
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
            .sheet(isPresented: $choosingChecklist) {
                ChecklistPickerView { checklistID in
                    // The title is the one being edited; this reminder is removed by the move.
                    store.moveIntoChecklist(draft.id, title: trimmedTitle, checklistID: checklistID)
                    vibrate()
                    choosingChecklist = false
                    dismiss()
                }
            }
            .onAppear {
                if isNew { titleFocused = true }
            }
        }
    }

    private var checklistItems: Binding<[ChecklistItem]> {
        Binding(get: { draft.checklist ?? [] }, set: { draft.checklist = $0 })
    }

    private func addChecklistItem() {
        draft.appendChecklistItem(titled: "")
        focusedItemID = draft.checklist?.last?.id
    }

    private func deleteChecklistItems(at offsets: IndexSet) {
        draft.checklist?.remove(atOffsets: offsets)
    }

    private func moveChecklistItems(from offsets: IndexSet, to destination: Int) {
        draft.checklist?.move(fromOffsets: offsets, toOffset: destination)
    }

    /// La misma vibración que al completar (`SlideToConfirm` ya vibra por su cuenta).
    private func save(vibrating: Bool = true) {
        guard !trimmedTitle.isEmpty else { return }
        if vibrating { vibrate() }
        var reminder = draft
        reminder.title = trimmedTitle
        // Checkboxes left without a title are dropped rather than saved empty.
        reminder.checklist = reminder.checklist?.compactMap { item -> ChecklistItem? in
            var trimmed = item
            trimmed.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.title.isEmpty ? nil : trimmed
        }
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
