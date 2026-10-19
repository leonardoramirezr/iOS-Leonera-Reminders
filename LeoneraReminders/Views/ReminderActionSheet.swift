import SwiftUI

/// Completar (deslizando) o "Recordar en…" con todas las opciones configuradas.
/// Se abre desde la lista o desde el botón «Abrir app» de la alarma.
struct ReminderActionSheet: View {
    let reminderID: UUID
    /// Abre el editor para elegir otra fecha.
    let onEdit: () -> Void

    @Environment(ReminderStore.self) private var store
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    /// Alto del contenido, para abrir la hoja justo del tamaño necesario y no tener que desplazarse.
    @State private var contentHeight: CGFloat
    @State private var detent: PresentationDetent

    /// Last measured content height, persisted so the sheet opens straight at its final height
    /// (even on a cold launch from the alarm's "Abrir app" button) instead of rising to `.large`
    /// and then shrinking once the content is measured.
    private static let contentHeightKey = "reminderActionSheet.contentHeight"

    init(reminderID: UUID, onEdit: @escaping () -> Void) {
        self.reminderID = reminderID
        self.onEdit = onEdit
        let cachedHeight = CGFloat(UserDefaults.standard.double(forKey: Self.contentHeightKey))
        _contentHeight = State(initialValue: cachedHeight)
        _detent = State(initialValue: Self.fittedDetent(for: cachedHeight) ?? .large)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let reminder = store.reminder(id: reminderID) {
                    content(for: reminder)
                } else {
                    ContentUnavailableView("El recordatorio ya no existe", systemImage: "questionmark.circle")
                }
            }
            .navigationTitle(store.reminder(id: reminderID)?.repeatRule == nil ? "Completar o posponer" : "Completar esta vez o posponer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents(fittedDetents, selection: $detent)
        .onChange(of: contentHeight) {
            UserDefaults.standard.set(Double(contentHeight), forKey: Self.contentHeightKey)
            if let fitted { detent = fitted }
        }
    }

    private var fitted: PresentationDetent? {
        Self.fittedDetent(for: contentHeight)
    }

    /// Contenido más la barra de navegación y el tirador de la hoja.
    private static func fittedDetent(for contentHeight: CGFloat) -> PresentationDetent? {
        contentHeight > 0 ? .height(contentHeight + 72) : nil
    }

    private var fittedDetents: Set<PresentationDetent> {
        fitted.map { [$0, .large] } ?? [.large]
    }

    private func content(for reminder: Reminder) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text(reminder.title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("Fecha límite: \(DateText.relative(reminder.dueDate))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                SlideToConfirm(title: "Desliza para completar") {
                    Task {
                        // Deja ver la palomita un instante antes de cerrar.
                        try? await Task.sleep(for: .milliseconds(350))
                        store.complete(id: reminder.id)
                        dismiss()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recordar en…")
                        .font(.headline)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(settingsStore.settings.sortedSnoozeOptions) { option in
                            Button {
                                Haptics.success()
                                store.snooze(id: reminder.id, by: option)
                                dismiss()
                            } label: {
                                Text(option.shortLabel)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .tint(option == settingsStore.settings.defaultSnooze ? Color.brand : Color.secondary)
                        }
                    }
                }

                Button("Elegir otra fecha…") {
                    Haptics.success()
                    onEdit()
                }
            }
            .padding()
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
        }
    }
}
