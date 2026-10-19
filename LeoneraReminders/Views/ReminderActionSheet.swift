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

    /// The sheet's only detent, fitted to the content so it opens at the needed height without scrolling.
    /// It is both the detent set and the selection, so the sheet always sits on it and never falls back
    /// to full screen when the measured height changes.
    @State private var detent: PresentationDetent

    /// Last measured content height, persisted so the sheet opens straight at its final height
    /// (even on a cold launch from the alarm's "Abrir app" button).
    private static let contentHeightKey = "reminderActionSheet.contentHeight"

    /// Used until the content has been measured once; close to the usual height, never full screen.
    private static let estimatedContentHeight: CGFloat = 460

    init(reminderID: UUID, onEdit: @escaping () -> Void) {
        self.reminderID = reminderID
        self.onEdit = onEdit
        let stored = CGFloat(UserDefaults.standard.double(forKey: Self.contentHeightKey))
        _detent = State(initialValue: Self.fittedDetent(contentHeight: stored > 0 ? stored : Self.estimatedContentHeight))
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
        .presentationDetents([detent], selection: $detent)
    }

    /// Contenido más la barra de navegación y el tirador de la hoja.
    private static func fittedDetent(contentHeight: CGFloat) -> PresentationDetent {
        .height(contentHeight + 72)
    }

    private func contentSizeChanged(_ size: CGSize) {
        // Before the sheet has its width the text wraps into a much taller column; that height is not real.
        guard size.width > 0, size.height > 0 else { return }
        let fitted = Self.fittedDetent(contentHeight: size.height)
        guard fitted != detent else { return }
        detent = fitted
        UserDefaults.standard.set(Double(size.height), forKey: Self.contentHeightKey)
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
            // Rounded so sub-point differences between layout passes do not resize the sheet.
            .onGeometryChange(for: CGSize.self, of: {
                CGSize(width: $0.size.width.rounded(.up), height: $0.size.height.rounded(.up))
            }) { contentSizeChanged($0) }
        }
    }
}
