import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ReminderListView: View {
    @Environment(ReminderStore.self) private var store
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(AlarmSyncService.self) private var alarms
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var editing: EditorTarget?
    @State private var assistant: AssistantSource?
    @State private var acting: ReminderSheetID?
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var importPreview: ImportPreview?
    @State private var importError: String?
    @State private var exportFile: CSVDocument?
    @State private var exportFileName = ""
    @State private var exportError: String?
    @State private var showCompleted = false
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var completedTrigger = 0

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                list(now: context.date)
            }
            .navigationTitle("Recordatorios")
            .toolbar { toolbar }
            .overlay {
                if store.reminders.isEmpty {
                    ContentUnavailableView {
                        Label("Sin recordatorios", systemImage: "alarm")
                    } description: {
                        Text("Créalo a mano, con la voz o con una foto, o importa un CSV exportado de Due.")
                    } actions: {
                        Button("Importar CSV…") { showImporter = true }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    if let change = store.undoable {
                        UndoToast(change: change)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    // Mientras se busca, el campo de búsqueda ocupa el lugar de la barra.
                    if isSearching {
                        SearchBar(text: $searchText) {
                            searchText = ""
                            isSearching = false
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        AddReminderBar(
                            onSearch: { isSearching = true },
                            onPhoto: { assistant = .photo },
                            onVoice: { assistant = .voice },
                            onManual: { editing = .new }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .animation(.snappy, value: store.undoable?.id)
            .animation(.snappy, value: isSearching)
        }
        .sensoryFeedback(.success, trigger: completedTrigger)
        .sheet(item: $editing) { target in
            ReminderEditorView(target: target, existing: target.reminderID.flatMap(store.reminder(id:)))
        }
        .sheet(item: $assistant) { source in
            switch source {
            case .voice: VoiceCaptureView()
            case .photo: PhotoCaptureView()
            }
        }
        .sheet(item: $acting) { sheet in
            ReminderActionSheet(reminderID: sheet.id) {
                acting = nil
                editing = .edit(sheet.id)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $importPreview) { preview in
            ImportPreviewView(preview: preview)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text]
        ) { result in
            handleImport(result)
        }
        .alert("No se pudo importar", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .fileExporter(
            isPresented: Binding(
                get: { exportFile != nil },
                set: { if !$0 { exportFile = nil } }
            ),
            document: exportFile,
            contentType: .commaSeparatedText,
            defaultFilename: exportFileName
        ) { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
        .alert("No se pudo exportar", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        // The alarm asked to complete or snooze. The sheet waits until the scene is active: presenting it
        // while the system was still bringing the app to the foreground (or on a cold launch, before the
        // window was on screen) made the screen flash black before the sheet rose.
        .onChange(of: scenePhase == .active ? store.pendingOptionsReminderID : nil, initial: true) { _, id in
            guard let id else { return }
            // Se vibra aquí (y no al tocar el botón) porque es cuando la app ya está al frente.
            Haptics.success()
            store.pendingOptionsReminderID = nil
            editing = nil
            assistant = nil
            acting = ReminderSheetID(id: id)
        }
    }

    // MARK: - Lista

    private func list(now: Date) -> some View {
        let grouped = sections(now: now)
        let completed = filtered.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        return List {
            statusSection

            ForEach(grouped) { section in
                Section {
                    ForEach(section.reminders) { reminder in
                        row(reminder, now: now)
                    }
                } header: {
                    Text(section.title)
                        .foregroundStyle(section.isOverdue ? Color.red : Color.secondary)
                }
            }

            if !completed.isEmpty {
                Section {
                    Button {
                        withAnimation { showCompleted.toggle() }
                    } label: {
                        Label(
                            showCompleted ? "Ocultar completados" : "Mostrar completados (\(completed.count))",
                            systemImage: showCompleted ? "chevron.up" : "chevron.down"
                        )
                    }
                    if showCompleted {
                        ForEach(completed) { reminder in
                            row(reminder, now: now)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Borde cuyas acciones completan: deslizar de derecha a izquierda muestra las del borde final.
    private var completeEdge: HorizontalEdge {
        settingsStore.settings.swipeCompleteDirection == .rightToLeft ? .trailing : .leading
    }

    private func row(_ reminder: Reminder, now: Date) -> some View {
        // Un botón (y no `onTapGesture`) para que el toque no compita con el gesto de deslizar.
        Button { editing = .edit(reminder.id) } label: {
            ReminderRow(
                reminder: reminder,
                now: now,
                isRinging: reminder.scheduledAlarms.contains { alarms.alertingAlarmIDs.contains($0.id) },
                onToggle: {
                    // Completar siempre pide deslizar; reabrir un completado es inofensivo.
                    if reminder.isCompleted {
                        store.markIncomplete(id: reminder.id)
                    } else {
                        acting = ReminderSheetID(id: reminder.id)
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .swipeActions(edge: completeEdge) {
            if !reminder.isCompleted {
                // Si al completarlo sale de su sección, la fila se desliza fuera como al eliminar
                // en lugar de regresar a su lugar y luego desaparecer de golpe.
                Button(role: leavesSectionWhenCompleted(reminder) ? .destructive : nil) {
                    complete(reminder)
                } label: {
                    Label("Completar", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: completeEdge == .trailing ? .leading : .trailing) {
            Button(role: .destructive) { store.delete(ids: [reminder.id]) } label: {
                Label("Eliminar", systemImage: "trash")
            }
            if !reminder.isCompleted {
                Button { acting = ReminderSheetID(id: reminder.id) } label: {
                    Label("Posponer", systemImage: "zzz")
                }
                .tint(.indigo)
            }
        }
        .contextMenu { menuItems(for: reminder) }
    }

    @ViewBuilder
    private func menuItems(for reminder: Reminder) -> some View {
        if reminder.isCompleted {
            Button { store.markIncomplete(id: reminder.id) } label: {
                Label("Marcar como pendiente", systemImage: "arrow.uturn.backward")
            }
        } else {
            Button { acting = ReminderSheetID(id: reminder.id) } label: {
                Label("Completar…", systemImage: "checkmark")
            }
            Menu {
                ForEach(settingsStore.settings.sortedSnoozeOptions) { option in
                    Button("Recordar en \(option.longLabel)") { store.snooze(id: reminder.id, by: option) }
                }
            } label: {
                Label("Posponer", systemImage: "zzz")
            }
        }
        Button { editing = .edit(reminder.id) } label: {
            Label("Editar", systemImage: "pencil")
        }
        Button(role: .destructive) { store.delete(ids: [reminder.id]) } label: {
            Label("Eliminar", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if !settingsStore.settings.ignoresSilentMode {
            if !alarms.notificationsAuthorized {
                Section {
                    Label("Las notificaciones están desactivadas", systemImage: "bell.slash")
                        .foregroundStyle(.red)
                    Text("Sin este permiso los recordatorios no sonarán. Actívalo en Configuración o activa «Sonar aunque esté en silencio».")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Abrir Configuración") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            }
        } else {
            alarmStatus
        }
        if alarms.limitReached {
            Section {
                Label("Se alcanzó el máximo de avisos que permite iOS; los más lejanos se programarán cuando se liberen.",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote)
            }
        }
        if let error = store.lastError {
            Section {
                Label(error, systemImage: "exclamationmark.triangle").font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var alarmStatus: some View {
        switch alarms.authorizationState {
        case .denied:
            Section {
                Label("Las alarmas están desactivadas", systemImage: "alarm.waves.left.and.right")
                    .foregroundStyle(.red)
                Text("Sin este permiso los recordatorios no sonarán. Actívalo en Configuración.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Abrir Configuración") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        case .notDetermined:
            Section {
                Button {
                    Task { await alarms.requestAuthorization() }
                } label: {
                    Label("Permitir alarmas", systemImage: "alarm")
                }
            } footer: {
                Text("Leonera usa alarmas para que cada recordatorio suene a su hora, aun en silencio.")
            }
        default:
            EmptyView()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button { showImporter = true } label: {
                    Label("Importar CSV…", systemImage: "square.and.arrow.down")
                }
                if !store.reminders.isEmpty {
                    Button { startExport() } label: {
                        Label("Exportar CSV…", systemImage: "square.and.arrow.up")
                    }
                }
                Button { showSettings = true } label: {
                    Label("Configuración", systemImage: "gear")
                }
                if store.reminders.contains(where: \.isCompleted) {
                    Button(role: .destructive) { store.deleteCompleted() } label: {
                        Label("Eliminar completados", systemImage: "trash")
                    }
                }
            } label: {
                Label("Más", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: - Datos

    private var filtered: [Reminder] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.reminders }
        return store.reminders.filter { $0.title.localizedStandardContains(query) }
    }

    private struct ReminderSection: Identifiable {
        let id: String
        let title: String
        let reminders: [Reminder]
        var isOverdue = false
    }

    private func sections(now: Date) -> [ReminderSection] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let dayAfter = calendar.date(byAdding: .day, value: 2, to: today) ?? now
        let nextWeek = calendar.date(byAdding: .day, value: 8, to: today) ?? now

        var overdue: [Reminder] = [], todays: [Reminder] = [], tomorrows: [Reminder] = []
        var week: [Reminder] = [], later: [Reminder] = []
        for reminder in filtered.filter({ !$0.isCompleted }).sorted(by: { $0.dueDate < $1.dueDate }) {
            let date = reminder.dueDate
            if date <= now { overdue.append(reminder) }
            else if date < tomorrow { todays.append(reminder) }
            else if date < dayAfter { tomorrows.append(reminder) }
            else if date < nextWeek { week.append(reminder) }
            else { later.append(reminder) }
        }
        return [
            ReminderSection(id: "overdue", title: "Vencidos", reminders: overdue, isOverdue: true),
            ReminderSection(id: "today", title: "Hoy", reminders: todays),
            ReminderSection(id: "tomorrow", title: "Mañana", reminders: tomorrows),
            ReminderSection(id: "week", title: "Próximos 7 días", reminders: week),
            ReminderSection(id: "later", title: "Más adelante", reminders: later),
        ].filter { !$0.reminders.isEmpty }
    }

    /// Sólo desde el deslizamiento de la fila (que ya es un gesto deliberado).
    private func complete(_ reminder: Reminder) {
        withAnimation { store.complete(id: reminder.id) }
        completedTrigger += 1
    }

    /// Los que no se repiten (o ya no tienen otra fecha) pasan a «Completados».
    private func leavesSectionWhenCompleted(_ reminder: Reminder) -> Bool {
        var completed = reminder
        completed.complete()
        return completed.isCompleted
    }

    /// Todos los recordatorios (también los completados), en el formato que «Importar CSV…» vuelve a leer.
    private func startExport() {
        exportFileName = ReminderCSVExporter.fileName()
        exportFile = CSVDocument(data: ReminderCSVExporter.data(for: store.reminders.sorted { $0.dueDate < $1.dueDate }))
    }

    private func handleImport(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                guard let text = ReminderCSVImporter.decodeText(data) else {
                    importError = "No se pudo leer el archivo como texto."
                    return
                }
                let parsed = try ReminderCSVImporter.parse(text)
                importPreview = ImportPreview(fileName: url.lastPathComponent, result: parsed)
            } catch {
                importError = error.localizedDescription
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}

/// Aviso con «Deshacer» que se queda unos segundos después de completar, modificar, posponer o eliminar.
struct UndoToast: View {
    let change: ReminderStore.UndoableChange

    @Environment(ReminderStore.self) private var store

    /// Tiempo que se muestra el aviso.
    static let duration: Duration = .seconds(10)

    var body: some View {
        HStack(spacing: 12) {
            Text(change.message)
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button {
                withAnimation { store.undo() }
            } label: {
                Label("Deshacer", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("z", modifiers: .command)
            Button {
                store.discardUndo(id: change.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Cerrar")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: .capsule)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .task(id: change.id) {
            try? await Task.sleep(for: Self.duration)
            guard !Task.isCancelled else { return }
            store.discardUndo(id: change.id)
        }
    }
}

struct ReminderRow: View {
    let reminder: Reminder
    let now: Date
    let isRinging: Bool
    let onToggle: () -> Void

    private var isOverdue: Bool { reminder.isOverdue(now: now) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(reminder.isCompleted ? Color.green : (isOverdue ? Color.red : Color.secondary))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(reminder.isCompleted ? "Marcar como pendiente" : "Completar")

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .strikethrough(reminder.isCompleted)
                    .foregroundStyle(reminder.isCompleted ? Color.secondary : Color.primary)

                if let completedAt = reminder.completedAt {
                    Label("Completado \(DateText.relative(completedAt, now: now))", systemImage: "checkmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Label(DateText.relative(reminder.dueDate, now: now), systemImage: alarmSymbol)
                        .font(.subheadline)
                        .foregroundStyle(isOverdue ? Color.red : Color.secondary)
                    if isOverdue, let next = reminder.scheduledAlarms.first(where: { $0.fireDate > now }) {
                        Label("Vuelve a sonar \(DateText.time(next.fireDate))", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                            .foregroundStyle(Color.brand)
                    }
                }
                if let rule = reminder.repeatRule {
                    Label(rule.summary(), systemImage: "repeat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if isRinging {
                Image(systemName: "alarm.waves.left.and.right.fill")
                    .foregroundStyle(Color.brand)
                    .symbolEffect(.wiggle, options: .repeating)
                    .accessibilityLabel("Sonando")
            }
        }
        .padding(.vertical, 2)
    }

    private var alarmSymbol: String {
        if reminder.isCompleted { return "checkmark" }
        return reminder.scheduledAlarms.isEmpty ? "bell.slash" : "alarm"
    }
}
