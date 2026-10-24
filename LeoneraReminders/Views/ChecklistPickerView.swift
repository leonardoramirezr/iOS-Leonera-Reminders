import SwiftUI

/// Pending reminders that have a checklist, to pick the one a plain reminder is added to.
struct ChecklistPickerView: View {
    /// Called with the id of the reminder picked; the presenter does the move and closes this sheet.
    let onSelect: (UUID) -> Void

    @Environment(ReminderStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var checklists: [Reminder] {
        store.reminders
            .filter { $0.checklist != nil && !$0.isCompleted }
            .sorted { $0.dueDate < $1.dueDate }
    }

    var body: some View {
        NavigationStack {
            List(checklists) { reminder in
                Button {
                    onSelect(reminder.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reminder.title)
                            .foregroundStyle(.primary)
                        Text(DateText.relative(reminder.dueDate))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if checklists.isEmpty {
                    ContentUnavailableView(
                        "Sin listas con casillas",
                        systemImage: "checklist",
                        description: Text("Crea un recordatorio con casillas y podrás agregarle este.")
                    )
                }
            }
            .navigationTitle("Agregar a…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }
}
