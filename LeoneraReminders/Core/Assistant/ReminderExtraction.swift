import Foundation

/// Convierte una nota en lenguaje natural (dictada, escrita o en fotos) en recordatorios con ayuda de un LLM:
/// arma las instrucciones y lee la respuesta JSON, que se muestra para revisarla antes de guardar.
///
/// La respuesta esperada es `{"reminders": [{"title": "…", "due": "AAAA-MM-DDTHH:MM", "repeat": null | {…}}]}`;
/// la lectura es tolerante (bloques de código, texto alrededor, claves en español, números como texto…).
enum ReminderExtraction {
    /// Un recordatorio propuesto por el LLM, con avisos sobre lo que no se entendió.
    struct Draft: Identifiable, Hashable, Sendable {
        enum Note: Hashable, Sendable {
            case missingDate
            case unrecognizedDate(String)
            case unrecognizedRepeat(String?)

            var message: String {
                switch self {
                case .missingDate: "No se indicó la fecha: revisa la fecha y hora."
                case .unrecognizedDate(let text): "No se entendió la fecha «\(text)»: revisa la fecha y hora."
                case .unrecognizedRepeat(let text?): "No se entendió la repetición «\(text)»: revísala."
                case .unrecognizedRepeat(nil): "No se entendió la repetición: revísala."
                }
            }

            var isAboutDate: Bool {
                switch self {
                case .missingDate, .unrecognizedDate: true
                case .unrecognizedRepeat: false
                }
            }
        }

        var reminder: Reminder
        var notes: [Note]

        var id: UUID { reminder.id }

        init(reminder: Reminder, notes: [Note] = []) {
            self.reminder = reminder
            self.notes = notes
        }
    }

    enum ExtractionError: Error, Equatable, LocalizedError {
        case invalidJSON

        var errorDescription: String? {
            switch self {
            case .invalidJSON: "El modelo no devolvió recordatorios en el formato esperado. Intenta de nuevo o elige otro modelo."
            }
        }
    }

    // MARK: - Instrucciones

    /// Instrucciones del sistema: la fecha actual (con los próximos días ya calculados, para que el modelo no
    /// tenga que hacer cuentas de calendario), el formato JSON y cómo completar lo que no se dice.
    static func systemPrompt(now: Date, calendar: Calendar, withImages: Bool) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: now)
        let today = "\(SpanishNames.weekdays[parts.weekday ?? 1]) \(parts.day ?? 1) de \(SpanishNames.months[parts.month ?? 1]) de \(parts.year ?? 2000)"
        let time = TimeOfDay(of: now, calendar: calendar).label
        let zone = calendar.timeZone
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let example = isoDay(tomorrow, calendar: calendar) + "T09:00"
        let source = withImages
            ? "fotos (listas, notas a mano, citas, recibos, invitaciones o capturas de pantalla) y las indicaciones opcionales del usuario"
            : "notas dictadas o escritas"

        return """
        Conviertes \(source) en recordatorios para una app de alarmas: cada recordatorio suena en su fecha y hora.

        Ahora es \(today), \(time) (hora local; zona horaria \(zone.identifier), \(utcOffset(of: zone, at: now))).
        Próximos días:
        \(upcomingDays(from: now, calendar: calendar).joined(separator: "\n"))

        Responde sólo con un objeto JSON, sin texto antes ni después, con esta forma:
        {"reminders":[{"title":"Llamar al dentista","due":"\(example)","repeat":null}]}

        Cada recordatorio:
        - "title": lo que hay que hacer, corto y claro, en el idioma de la nota y empezando con mayúscula. Conserva los datos útiles (nombres, cantidades, lugares), pero no pongas la fecha, la hora ni la repetición.
        - "due": fecha y hora local en que debe sonar por primera vez, con el formato AAAA-MM-DDTHH:MM (24 horas, sin zona horaria). Debe ser posterior a ahora.
        - "repeat": null si no se repite. Si se repite, un objeto:
          {"frequency":"weekly","interval":1,"weekdays":["monday","thursday"],"day_of_month":null,"last_day_of_month":false,"month":null}
          - "frequency": "hourly", "daily", "weekly", "monthly" o "yearly".
          - "interval": cada cuántas unidades (2 = cada 2 horas, días, semanas, meses o años). Quincenal = "weekly" con interval 2.
          - "weekdays" (sólo weekly): monday, tuesday, wednesday, thursday, friday, saturday, sunday. Entre semana = monday a friday; fines de semana = saturday y sunday.
          - "day_of_month" (monthly y yearly): día del mes. "last_day_of_month": true para el último día de cada mes.
          - "week_of_month" (monthly, con un solo día en "weekdays"): para "el primer lunes", "el último domingo", etc.: 1 a 4 = primero a cuarto; -1 = último, -2 = penúltimo, -3 = antepenúltimo. Si no, null.
          - "month" (yearly): mes del 1 al 12.
          - La hora de la repetición es la de "due", y "due" es la primera vez que toca según la repetición.

        Reglas:
        - Haz un recordatorio por cada cosa distinta que haya que recordar. Si algo debe sonar en momentos distintos que no siguen una repetición, haz uno por cada momento.
        - Si no se dice la hora: en la mañana = 09:00, al mediodía = 12:00, en la tarde = 16:00, en la noche = 20:00; sin ninguna pista, 09:00.
        - Si no se dice el día: hoy si esa hora todavía no pasa; si ya pasó, mañana.
        - "En 10 minutos", "en 2 horas", etc. cuentan desde ahora.
        - "El lunes", "el viernes", etc. es el próximo día con ese nombre; si es hoy y la hora ya pasó, el de la semana siguiente.
        - "Un día antes", "una hora antes", etc. se cuentan desde la fecha del evento que se menciona.
        \(withImages ? "- Las indicaciones del usuario mandan sobre lo que se ve en las fotos. Sin indicaciones, crea un recordatorio por cada tarea, cita o fecha límite que aparezca (p. ej. un recibo con fecha de pago: «Pagar …» ese día).\n" : "")- Si no hay nada que recordar, responde {"reminders":[]}.
        """
    }

    /// Mensaje del usuario con la nota (o las indicaciones, si hay fotos).
    static func userPrompt(text: String, withImages: Bool) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if withImages {
            return trimmed.isEmpty
                ? "Sin indicaciones: crea los recordatorios a partir de las fotos."
                : "Indicaciones:\n\(trimmed)"
        }
        return "Nota:\n\(trimmed)"
    }

    /// "- hoy miércoles 14 de octubre = 2026-10-14", "- mañana jueves …", "- viernes …" (dos semanas).
    static func upcomingDays(from now: Date, count: Int = 14, calendar: Calendar) -> [String] {
        let start = calendar.startOfDay(for: now)
        return (0..<count).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let parts = calendar.dateComponents([.month, .day, .weekday], from: day)
            guard let month = parts.month, let dayOfMonth = parts.day, let weekday = parts.weekday else { return nil }
            let prefix = offset == 0 ? "hoy " : offset == 1 ? "mañana " : ""
            return "- \(prefix)\(SpanishNames.weekdays[weekday]) \(dayOfMonth) de \(SpanishNames.months[month]) = \(isoDay(day, calendar: calendar))"
        }
    }

    /// "2026-10-14"
    static func isoDay(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 1, parts.day ?? 1)
    }

    static func utcOffset(of zone: TimeZone, at date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        let minutes = abs(seconds) / 60
        return "UTC" + (seconds < 0 ? "−" : "+") + String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    // MARK: - Lectura de la respuesta

    /// Lee la respuesta del LLM. Los recordatorios sin título se omiten; los que traen una fecha que no se entiende
    /// quedan en la siguiente hora en punto con un aviso, para corregirlos al revisar. Los repetitivos con una fecha
    /// que ya pasó avanzan a su siguiente ocurrencia; los demás se dejan así (la revisión los marca en rojo).
    static func parse(_ content: String, now: Date = Date(), calendar: Calendar = .current) throws -> [Draft] {
        guard let json = jsonText(in: content),
              let payload = try? JSONDecoder().decode(Payload.self, from: Data(json.utf8))
        else { throw ExtractionError.invalidJSON }
        return payload.items.compactMap { draft(from: $0, now: now, calendar: calendar) }
    }

    /// El JSON dentro de la respuesta: sin razonamiento (`<think>…</think>`), bloques de código ni texto alrededor.
    static func jsonText(in content: String) -> String? {
        let text = GroqAPI.removingReasoning(from: content)
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let end = text.lastIndex(where: { $0 == "}" || $0 == "]" }),
              start < end
        else { return nil }
        return String(text[start...end])
    }

    private static func draft(from item: Item, now: Date, calendar: Calendar) -> Draft? {
        let title = (item.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        var notes: [Draft.Note] = []

        var due: Date
        let dueText = (item.due ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = parseDue(dueText, calendar: calendar) {
            due = calendar.dateInterval(of: .minute, for: parsed)?.start ?? parsed
        } else {
            due = Reminder.defaultDueDate(now: now, calendar: calendar)
            notes.append(dueText.isEmpty ? .missingDate : .unrecognizedDate(dueText))
        }

        var rule: RepeatRule?
        switch item.repeat {
        case .noRepeat:
            rule = nil
        case .rule(let spec) where spec.meansNoRepeat:
            rule = nil
        case .rule(let spec):
            rule = spec.rule(dueDate: due, calendar: calendar)
            if rule == nil { notes.append(.unrecognizedRepeat(nil)) }
        case .text(let text):
            switch DueRepeatParser.parse(text, dueDate: due, calendar: calendar) {
            case .none: rule = nil
            case .rule(let parsed): rule = parsed
            case .unrecognized: notes.append(.unrecognizedRepeat(text))
            }
        }

        var reminder = Reminder(title: title, dueDate: due, repeatRule: rule, createdAt: now)
        reminder.alignDueDateToRepeatRule(calendar: calendar)
        reminder.advancePastDueRepetition(now: now, calendar: calendar)
        return Draft(reminder: reminder, notes: notes)
    }

    /// "2026-10-15T09:00" (el formato pedido), con segundos o zona horaria, con espacio, o sólo la fecha (a las 9:00).
    static func parseDue(_ text: String, calendar: Calendar) -> Date? {
        guard !text.isEmpty else { return nil }
        if text.count == 10, let day = ReminderCSVImporter.parseDate(text, calendar: calendar) {
            return TimeOfDay(hour: 9).applied(to: day, calendar: calendar)
        }
        return ReminderCSVImporter.parseDate(text, calendar: calendar)
    }

    /// Nombre del día (inglés o español, completo o abreviado) o número ISO (1 = lunes … 7 = domingo),
    /// a la numeración de `Calendar` (1 = domingo).
    static func weekday(from text: String) -> Int? {
        let word = DueRepeatParser.normalize(text).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if let number = Int(word) { return (1...7).contains(number) ? number % 7 + 1 : nil }
        if let day = DueRepeatParser.weekdayNames[word] { return day }
        // Abreviaturas ("lun", "mié", "sa"): el único día cuyo nombre empieza así.
        guard word.count >= 2 else { return nil }
        let matches = Set(DueRepeatParser.weekdayNames.filter { $0.key.hasPrefix(word) }.values)
        return matches.count == 1 ? matches.first : nil
    }

    // MARK: - Formato JSON tolerante

    fileprivate struct Payload: Decodable {
        var items: [Item]

        init(from decoder: any Decoder) throws {
            if let list = try? decoder.singleValueContainer().decode([Lossy<Item>].self) {
                items = list.compactMap(\.value)
                return
            }
            let c = try decoder.container(keyedBy: AnyKey.self)
            for key in ["reminders", "recordatorios", "items"] {
                if let list = try? c.decode([Lossy<Item>].self, forKey: AnyKey(key)) {
                    items = list.compactMap(\.value)
                    return
                }
            }
            // Un solo recordatorio suelto.
            let single = try Item(from: decoder)
            guard single.title != nil else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Sin recordatorios"))
            }
            items = [single]
        }
    }

    fileprivate struct Item: Decodable {
        enum Repeat {
            case noRepeat
            case rule(RepeatSpec)
            /// Texto libre ("Todos los lunes 9:00"), que se interpreta como la columna «Repetir» del CSV.
            case text(String)
        }

        var title: String?
        var due: String?
        var `repeat`: Repeat

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            title = c.flexibleString("title", "titulo", "name", "text", "reminder")
            due = c.flexibleString("due", "due_date", "dueDate", "date", "datetime", "fecha", "when")
            `repeat` = .noRepeat
            for key in ["repeat", "repetir", "recurrence", "repetition"].map(AnyKey.init(_:)) where c.contains(key) {
                if (try? c.decodeNil(forKey: key)) == true {
                    `repeat` = .noRepeat
                } else if let spec = try? c.decode(RepeatSpec.self, forKey: key) {
                    `repeat` = .rule(spec)
                } else if let text = c.flexibleString(key.stringValue) {
                    `repeat` = RepeatSpec(frequencyText: text).map(Repeat.rule) ?? .text(text)
                }
                break
            }
        }
    }

    fileprivate struct RepeatSpec: Decodable {
        var frequency: String?
        var interval: Int?
        var weekdays: [String]?
        var dayOfMonth: Int?
        var lastDayOfMonth: Bool?
        var weekOfMonth: Int?
        var month: Int?

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            frequency = c.flexibleString("frequency", "freq", "every", "unit", "frecuencia")
            interval = c.flexibleInt("interval", "every_n", "cada")
            weekdays = c.flexibleStrings("weekdays", "days", "days_of_week", "dias")
            dayOfMonth = c.flexibleInt("day_of_month", "dayOfMonth", "day", "monthday", "dia")
            lastDayOfMonth = c.flexibleBool("last_day_of_month", "lastDayOfMonth", "last_day")
            weekOfMonth = c.flexibleInt("week_of_month", "weekOfMonth", "weekday_ordinal", "ordinal")
            month = c.flexibleInt("month", "mes")
        }

        /// `{}`, `{"frequency": null}` o `{"frequency": "none"}`.
        var meansNoRepeat: Bool {
            guard let frequency else { return true }
            let word = DueRepeatParser.normalize(frequency).trimmingCharacters(in: .whitespacesAndNewlines)
            return word.isEmpty || DueRepeatParser.noneWords.contains(word)
        }

        /// Sólo la frecuencia como texto ("daily", "weekly", "mensual"); `nil` si no es una palabra conocida.
        init?(frequencyText: String) {
            guard Self.frequency(from: frequencyText) != nil else { return nil }
            frequency = frequencyText
        }

        /// Frecuencia, intervalo implícito ("biweekly" = cada 2 semanas) y días implícitos ("weekdays").
        static func frequency(from text: String) -> (frequency: RepeatRule.Frequency, interval: Int, weekdays: Set<Int>?)? {
            let word = DueRepeatParser.normalize(text).trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "_", with: " ")
            if let adverb = DueRepeatParser.adverbs[word] { return (adverb.0, adverb.1, nil) }
            if let group = DueRepeatParser.weekdayGroups[word] { return (.weekly, 1, group) }
            if let unit = DueRepeatParser.units[word] {
                switch unit {
                case .hour: return (.hourly, 1, nil)
                case .day: return (.daily, 1, nil)
                case .week: return (.weekly, 1, nil)
                case .month: return (.monthly, 1, nil)
                case .year: return (.yearly, 1, nil)
                case .minute: break
                }
            }
            return switch word {
            case "cada hora", "horario": (.hourly, 1, nil)
            case "diaria", "dias", "everyday", "every day", "cada dia", "todos los dias": (.daily, 1, nil)
            case "semanalmente", "cada semana": (.weekly, 1, nil)
            case "cada mes": (.monthly, 1, nil)
            case "annual", "cada ano": (.yearly, 1, nil)
            default: nil
            }
        }

        /// La regla, con la hora (y el día de la semana o del mes que falten) de `dueDate`. Sólo llena los campos
        /// que usa cada frecuencia, como `DueRepeatParser`, para que las reglas iguales se comparen iguales.
        func rule(dueDate: Date, calendar: Calendar) -> RepeatRule? {
            guard let frequency, let parsed = Self.frequency(from: frequency) else { return nil }
            let due = calendar.dateComponents([.hour, .minute, .weekday, .day, .month], from: dueDate)
            let hour = due.hour ?? 9, minute = due.minute ?? 0
            let interval = min(max(1, interval ?? parsed.interval), 99)
            let day = dayOfMonth.flatMap { (1...31).contains($0) ? $0 : nil }
            switch parsed.frequency {
            case .hourly:
                return RepeatRule(frequency: .hourly, interval: interval, hour: hour, minute: minute)
            case .daily:
                return RepeatRule(frequency: .daily, interval: interval, hour: hour, minute: minute)
            case .weekly:
                let named = Set((weekdays ?? []).compactMap(ReminderExtraction.weekday(from:)))
                let days = !named.isEmpty ? named : parsed.weekdays ?? [due.weekday ?? 1]
                return RepeatRule(frequency: .weekly, interval: interval, hour: hour, minute: minute, weekdays: days)
            case .monthly:
                let named = (weekdays ?? []).compactMap(ReminderExtraction.weekday(from:))
                if let ordinal = weekOfMonth, RepeatRule.weekdayOrdinals.contains(ordinal),
                   let weekday = named.first ?? due.weekday {
                    return RepeatRule(frequency: .monthly, interval: interval, hour: hour, minute: minute,
                                      weekdayOrdinal: ordinal, ordinalWeekday: weekday)
                }
                let last = lastDayOfMonth == true
                return RepeatRule(frequency: .monthly, interval: interval, hour: hour, minute: minute,
                                  dayOfMonth: last ? 31 : day ?? due.day ?? 1, lastDayOfMonth: last)
            case .yearly:
                return RepeatRule(frequency: .yearly, interval: interval, hour: hour, minute: minute,
                                  dayOfMonth: day ?? due.day ?? 1,
                                  month: month.flatMap { (1...12).contains($0) ? $0 : nil } ?? due.month ?? 1)
            }
        }
    }

    /// Un texto o un número, como texto.
    fileprivate struct Scalar: Decodable {
        var text: String

        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let value = try? c.decode(String.self) { text = value }
            else if let value = try? c.decode(Int.self) { text = String(value) }
            else { text = String(try c.decode(Double.self)) }
        }
    }

    /// Un elemento que, si no se puede leer, se omite sin invalidar la lista.
    fileprivate struct Lossy<Value: Decodable>: Decodable {
        var value: Value?

        init(from decoder: any Decoder) throws {
            value = try? Value(from: decoder)
        }
    }

    fileprivate struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

private extension KeyedDecodingContainer where Key == ReminderExtraction.AnyKey {
    /// El primer valor presente entre `keys`, como texto (también acepta números).
    func flexibleString(_ keys: String...) -> String? {
        for key in keys.map(Key.init(_:)) where contains(key) {
            if let value = try? decode(String.self, forKey: key) { return value }
            if let value = try? decode(Int.self, forKey: key) { return String(value) }
            if let value = try? decode(Double.self, forKey: key) { return String(value) }
        }
        return nil
    }

    /// Número entero, aunque venga como texto ("2") o con decimales (2.0).
    func flexibleInt(_ keys: String...) -> Int? {
        for key in keys.map(Key.init(_:)) where contains(key) {
            if let value = try? decode(Int.self, forKey: key) { return value }
            if let value = try? decode(Double.self, forKey: key), value.isFinite { return Int(value) }
            if let text = try? decode(String.self, forKey: key),
               let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) { return value }
        }
        return nil
    }

    func flexibleBool(_ keys: String...) -> Bool? {
        for key in keys.map(Key.init(_:)) where contains(key) {
            if let value = try? decode(Bool.self, forKey: key) { return value }
            if let text = try? decode(String.self, forKey: key) {
                switch DueRepeatParser.normalize(text) {
                case "true", "si", "yes": return true
                case "false", "no": return false
                default: continue
                }
            }
        }
        return nil
    }

    /// Lista de textos o números (mezclados o no), o un texto separado por comas ("monday, friday").
    func flexibleStrings(_ keys: String...) -> [String]? {
        for key in keys.map(Key.init(_:)) where contains(key) {
            if let values = try? decode([ReminderExtraction.Lossy<ReminderExtraction.Scalar>].self, forKey: key) {
                return values.compactMap(\.value?.text)
            }
            if let text = try? decode(String.self, forKey: key) {
                return text.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " }).map(String.init)
            }
        }
        return nil
    }
}
