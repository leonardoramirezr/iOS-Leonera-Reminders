import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(AlarmSyncService.self) private var alarms
    @Environment(GroqKeyStore.self) private var groqKey
    @Environment(CalendarEventSource.self) private var calendarEvents
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var editingCell: GridCellPosition?
    @State private var addingSnooze = false

    private var settings: Binding<AppSettings> {
        Binding(get: { settingsStore.settings }, set: { settingsStore.settings = $0 })
    }

    private var defaultSnoozeLabel: String { settingsStore.settings.defaultSnooze.shortLabel }

    var body: some View {
        NavigationStack {
            Form {
                assistantSection
                calendarSection
                soundSection
                alarmSection
                followUpSection
                snoozeSection
                gridSection
                listSection
                permissionSection
                aboutSection
            }
            .navigationTitle("Configuración")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
            .sheet(item: $editingCell) { position in
                GridCellEditor(
                    position: position,
                    cell: settingsStore.settings.quickAdjustGrid.rows[position.row][position.column]
                ) { newCell in
                    settings.wrappedValue.quickAdjustGrid.setCell(newCell, column: position.column)
                }
            }
            .sheet(isPresented: $addingSnooze) {
                TimeAmountEditor(title: "Nueva opción", initial: .minutes(15), units: [.minute, .hour, .day]) { amount in
                    settings.wrappedValue.snoozeOptions.append(amount)
                }
            }
        }
    }

    // MARK: - Secciones

    private var assistantSection: some View {
        Section {
            NavigationLink {
                AssistantSettingsView()
            } label: {
                LabeledContent {
                    Text(groqKey.hasKey ? "Configurado" : "Sin clave")
                } label: {
                    Label("Voz y fotos con Groq", systemImage: "sparkles")
                }
            }
        } header: {
            Text("Asistente")
        } footer: {
            Text("Crea recordatorios dictando o con una foto: Groq convierte la voz en texto y un modelo de lenguaje la convierte en recordatorios, que revisas antes de guardar.")
        }
    }

    private var calendarSection: some View {
        Section {
            NavigationLink {
                CalendarSettingsView()
            } label: {
                LabeledContent {
                    Text(calendarStatus)
                } label: {
                    Label("Calendario de Apple", systemImage: "calendar")
                }
            }
        } header: {
            Text("Eventos")
        } footer: {
            Text("Suena una alarma 5 minutos y 1 minuto antes de cada evento de los calendarios que elijas.")
        }
    }

    private var calendarStatus: String {
        let count = settingsStore.settings.calendarAlarms.calendarIDs.count
        guard count > 0 else { return "Desactivado" }
        guard calendarEvents.hasAccess else { return "Sin acceso" }
        return count == 1 ? "1 calendario" : "\(count) calendarios"
    }

    private var alarmSection: some View {
        Section {
            Picker("Al detener", selection: settings.stopAction) {
                Text("Posponer \(defaultSnoozeLabel)").tag(AlarmAction.snooze)
                Text("Posponer y abrir la app").tag(AlarmAction.snoozeOptions)
            }
            Picker("Segundo botón", selection: settings.secondaryAction) {
                Text("Abrir app").tag(AlarmAction.snoozeOptions)
                Text("Posponer \(defaultSnoozeLabel)").tag(AlarmAction.snooze)
                Text("Ninguno").tag(AlarmAction.none)
            }
        } header: {
            Text("Botones de la alarma")
        } footer: {
            Text("Ningún botón de la alarma completa el recordatorio: para completarlo hay que deslizar «Desliza para completar» en la app. «Abrir app» pospone \(defaultSnoozeLabel) (por si no terminas) y abre la app para completar o elegir otro tiempo.")
        }
    }

    private var soundSection: some View {
        Section {
            NavigationLink {
                SoundPickerView(selection: settings.sound)
            } label: {
                LabeledContent("Sonido", value: settingsStore.settings.sound.label)
            }
            Toggle("Sonar aunque esté en silencio", isOn: settings.ignoresSilentMode)
        } header: {
            Text("Sonido")
        } footer: {
            Text(settingsStore.settings.ignoresSilentMode
                ? "Los recordatorios llegan como alarmas: suenan aunque el iPhone esté en silencio o en un modo de Concentración."
                : "Los recordatorios llegan como notificaciones: respetan el modo silencio (sólo vibran) y la Concentración. iOS guarda hasta 64 pendientes, así que se programan las más próximas.")
        }
    }

    private var followUpSection: some View {
        Section {
            Toggle("Volver a sonar si no la atiendo", isOn: settings.followUp.isEnabled)
            if settingsStore.settings.followUp.isEnabled {
                Picker("Cada", selection: settings.followUp.interval) {
                    ForEach(FollowUpSettings.intervalOptions) { option in
                        Text(option.longLabel).tag(option)
                    }
                }
                Picker("Hasta", selection: settings.followUp.count) {
                    ForEach(FollowUpSettings.countOptions, id: \.self) { count in
                        Text("\(count) veces").tag(count)
                    }
                }
            }
        } header: {
            Text("Si ignoras la alarma")
        } footer: {
            Text(followUpFooter)
        }
    }

    private var followUpFooter: String {
        let followUp = settingsStore.settings.followUp
        guard followUp.isEnabled else {
            return "Si no tocas ningún botón, el recordatorio queda en «Vencidos» sin volver a sonar."
        }
        let total = TimeAmount(followUp.interval.value * followUp.count, followUp.interval.unit)
        return "Cada recordatorio deja programadas alarmas extra cada \(followUp.interval.longLabel) durante \(total.longLabel). Al completar o posponer se cancelan. Así suena aunque no abras la app."
    }

    private var snoozeSection: some View {
        Section {
            Picker("Posponer por defecto", selection: settings.defaultSnooze) {
                ForEach(settingsStore.settings.sortedSnoozeOptions) { option in
                    Text(option.longLabel).tag(option)
                }
            }
            ForEach(settingsStore.settings.sortedSnoozeOptions) { option in
                HStack {
                    Text("Recordar en \(option.longLabel)")
                    Spacer()
                    if option == settingsStore.settings.defaultSnooze {
                        Text("Por defecto").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                let options = settingsStore.settings.sortedSnoozeOptions
                let removed = Set(offsets.map { options[$0] })
                guard removed.count < options.count else { return }
                settings.wrappedValue.snoozeOptions.removeAll { removed.contains($0) }
            }
            Button {
                addingSnooze = true
            } label: {
                Label("Agregar opción", systemImage: "plus")
            }
            Button("Restaurar opciones") {
                settings.wrappedValue.snoozeOptions = AppSettings.defaultSnoozeOptions
            }
        } header: {
            Text("Posponer")
        } footer: {
            Text("Desliza para quitar una opción. Aparecen al posponer desde la app y en «Más opciones» de la alarma.")
        }
    }

    private var gridSection: some View {
        Section {
            QuickAdjustGridView(grid: settingsStore.settings.quickAdjustGrid) { row, column, _ in
                editingCell = GridCellPosition(row: row, column: column)
            }
            .padding(.vertical, 4)
            Button("Restaurar matriz") {
                settings.wrappedValue.quickAdjustGrid = .default
            }
            Picker("Sumar a un vencido", selection: settings.overdueAdditionBase) {
                Text("Desde la fecha límite").tag(OverdueAdditionBase.dueDate)
                Text("Desde ahora").tag(OverdueAdditionBase.now)
            }
        } header: {
            Text("Matriz de ajuste rápido")
        } footer: {
            Text("Toca una celda para cambiarla. La primera fila fija la hora, la segunda suma y la tercera resta. " + overdueAdditionFooter)
        }
    }

    private var overdueAdditionFooter: String {
        switch settingsStore.settings.overdueAdditionBase {
        case .dueDate:
            "Si el recordatorio ya venció, +10 min, +1 h, etc. suman a su fecha límite, aunque ya haya pasado."
        case .now:
            "Si el recordatorio ya venció, +10 min, +1 h, etc. suman desde ahora, como al posponer, y fijar una hora que ya pasó la pone al día siguiente. Restar siempre parte de la fecha límite."
        }
    }

    private var listSection: some View {
        Section {
            Picker("Completar deslizando", selection: settings.swipeCompleteDirection) {
                Text("De derecha a izquierda").tag(SwipeCompleteDirection.rightToLeft)
                Text("De izquierda a derecha").tag(SwipeCompleteDirection.leftToRight)
            }
            Toggle("Fuegos artificiales al completar", isOn: settings.celebratesCompletion)
            if settingsStore.settings.celebratesCompletion {
                Picker("Mientras se ven", selection: settings.fireworksInteraction) {
                    ForEach(FireworksInteraction.allCases) { interaction in
                        Text(interaction.label).tag(interaction)
                    }
                }
            }
        } header: {
            Text("Lista")
        } footer: {
            Text("Deslizar una fila en el sentido contrario muestra «Eliminar» y «Posponer». Al completar un recordatorio hay fuegos artificiales, nunca iguales. «Bloquear la app» impide usarla mientras se ven; «Tocar para terminar» lo impide hasta que un toque los acaba; «Permitir usar la app» no impide nada.")
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        Section("Permiso de alarmas") {
            switch alarms.authorizationState {
            case .authorized:
                Label("Permitidas", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .notDetermined:
                Button("Permitir alarmas") {
                    Task { await alarms.requestAuthorization() }
                }
            default:
                Label("Denegadas", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Button("Abrir Configuración") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            if let error = alarms.lastError {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var aboutSection: some View {
        Section("Acerca de") {
            LabeledContent("Build", value: Self.buildName)
                .textSelection(.enabled)
        }
    }

    /// The name the Build IPA workflow gives this build (`build-48-10cac63` on a branch, `0.x.0` on main).
    /// Builds made outside the workflow fall back to the version and build number.
    private static var buildName: String {
        let info = Bundle.main.infoDictionary ?? [:]
        if let name = info["LeoneraBuildName"] as? String, !name.isEmpty { return name }
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

struct GridCellPosition: Identifiable, Hashable {
    let row: Int
    let column: Int
    var id: String { "\(row)-\(column)" }
}

/// Edita una celda de la matriz: una hora (fila 1) o una cantidad (filas 2 y 3).
struct GridCellEditor: View {
    let position: GridCellPosition
    let cell: QuickAdjustGrid.Cell
    let onSave: (QuickAdjustGrid.Cell) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()
    @State private var amount = TimeAmount.minutes(10)

    var body: some View {
        NavigationStack {
            Form {
                switch cell {
                case .setTime:
                    DatePicker("Hora", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                case .add, .subtract:
                    TimeAmountFields(amount: $amount, units: TimeAmount.Unit.allCases)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        switch cell {
                        case .setTime: onSave(.setTime(TimeOfDay(of: time)))
                        case .add: onSave(.add(amount))
                        case .subtract: onSave(.subtract(amount))
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                switch cell {
                case .setTime(let value): time = value.applied(to: Date())
                case .add(let value), .subtract(let value): amount = value
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var title: String {
        switch cell {
        case .setTime: "Hora (columna \(position.column + 1))"
        case .add: "Sumar (columna \(position.column + 1))"
        case .subtract: "Restar (columna \(position.column + 1))"
        }
    }
}

/// Hoja para crear una cantidad de tiempo (p. ej. una nueva opción de posponer).
struct TimeAmountEditor: View {
    let title: String
    let units: [TimeAmount.Unit]
    let onSave: (TimeAmount) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amount: TimeAmount

    init(title: String, initial: TimeAmount, units: [TimeAmount.Unit], onSave: @escaping (TimeAmount) -> Void) {
        self.title = title
        self.units = units
        self.onSave = onSave
        _amount = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                TimeAmountFields(amount: $amount, units: units)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Agregar") {
                        onSave(amount)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct TimeAmountFields: View {
    @Binding var amount: TimeAmount
    let units: [TimeAmount.Unit]

    var body: some View {
        Stepper(value: $amount.value, in: 1...999) {
            Text(amount.longLabel)
        }
        Picker("Unidad", selection: $amount.unit) {
            ForEach(units) { unit in
                Text(unit.longName(for: amount.value).capitalized).tag(unit)
            }
        }
        .pickerStyle(.segmented)
    }
}
