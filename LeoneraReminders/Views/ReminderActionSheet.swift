import SwiftUI
import UIKit

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

    /// Height of the sheet's only detent, fitted to the content so it opens at the needed height without
    /// scrolling. The detent is both the detent set and the selection, so the sheet always sits on it.
    @State private var sheetHeight: CGFloat

    /// Last measured content height, persisted so the sheet opens straight at its final height
    /// (even on a cold launch from the alarm's "Abrir app" button).
    private static let contentHeightKey = "reminderActionSheet.contentHeight"

    /// Used until the content has been measured once; close to the usual height, never full screen.
    private static let estimatedContentHeight: CGFloat = 460

    /// Narrower than any iPhone sheet. While the sheet is still being laid out (for example while the app
    /// comes to the foreground from the alarm) the content can be measured at a much narrower width, where
    /// the text and the grid wrap into a far taller column; those heights are not real.
    private static let minimumMeasuredWidth: CGFloat = 300

    init(reminderID: UUID, onEdit: @escaping () -> Void) {
        self.reminderID = reminderID
        self.onEdit = onEdit
        let stored = CGFloat(UserDefaults.standard.double(forKey: Self.contentHeightKey))
        _sheetHeight = State(initialValue: Self.fittedHeight(contentHeight: stored > 0 ? stored : Self.estimatedContentHeight))
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
        .presentationDetents([.height(sheetHeight)], selection: .constant(.height(sheetHeight)))
        // SwiftUI only hands the detent to the sheet when it changes, so a sheet that opened full screen
        // (presented while the app was still coming to the foreground from the alarm) stayed there.
        .background(SheetHeightKeeper(height: sheetHeight))
    }

    /// Contenido más la barra de navegación y el tirador de la hoja.
    private static func fittedHeight(contentHeight: CGFloat) -> CGFloat {
        contentHeight + 72
    }

    private func contentSizeChanged(_ size: CGSize) {
        guard size.width >= Self.minimumMeasuredWidth, size.height > 0 else { return }
        let fitted = Self.fittedHeight(contentHeight: size.height)
        guard fitted != sheetHeight else { return }
        sheetHeight = fitted
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
                    // Right away: the rockets climb while the sheet closes.
                    Celebration.celebrateCompletion()
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

/// Sets the presenting sheet's detent to `height` directly on its `UISheetPresentationController`, when the
/// sheet appears and whenever the height changes, so the sheet ends at that height even if SwiftUI's
/// `presentationDetents` did not reach it (it is capped at the tallest height the sheet allows).
private struct SheetHeightKeeper: UIViewControllerRepresentable {
    let height: CGFloat

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.height = height
    }

    final class Controller: UIViewController {
        private static let detentID = UISheetPresentationController.Detent.Identifier("fittedContent")

        var height: CGFloat = 0 {
            didSet {
                guard height != oldValue else { return }
                applyHeight(animated: viewIfLoaded?.window != nil)
            }
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyHeight(animated: false)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyHeight(animated: true)
        }

        /// The sheet that presents the SwiftUI content this controller is embedded in.
        private var sheet: UISheetPresentationController? {
            var root: UIViewController = self
            while let parent = root.parent { root = parent }
            return root.sheetPresentationController
        }

        private func applyHeight(animated: Bool) {
            guard height > 0, let sheet else { return }
            let height = height
            let change = {
                sheet.detents = [.custom(identifier: Self.detentID) { min(height, $0.maximumDetentValue) }]
                sheet.selectedDetentIdentifier = Self.detentID
            }
            if animated {
                sheet.animateChanges(change)
            } else {
                change()
            }
        }
    }
}
