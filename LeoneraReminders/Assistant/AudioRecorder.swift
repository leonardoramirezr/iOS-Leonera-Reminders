import AVFoundation
import Foundation
import Observation

/// Graba el dictado en AAC (m4a) mono a 16 kHz: es lo que usa Whisper y el archivo queda pequeño para subirlo.
@MainActor
@Observable
final class AudioRecorder {
    enum RecorderError: LocalizedError {
        case couldNotStart

        var errorDescription: String? { "El micrófono no está disponible." }
    }

    /// Duración máxima de cada grabación; al llegar se detiene sola (`reachedLimit`).
    static let maxDuration: TimeInterval = 10 * 60

    private(set) var isRecording = false
    /// Nivel de la voz de 0 a 1, para animar la interfaz.
    private(set) var level: Double = 0
    private(set) var startedAt: Date?
    /// La grabación se detuvo sola al llegar a `maxDuration`.
    private(set) var reachedLimit = false

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meterTask: Task<Void, Never>?

    func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    func start() throws {
        cancel()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory.appending(path: "dictado-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings),
              recorder.record(forDuration: Self.maxDuration)
        else {
            deactivateSession()
            throw RecorderError.couldNotStart
        }
        recorder.isMeteringEnabled = true
        self.recorder = recorder
        isRecording = true
        reachedLimit = false
        startedAt = Date()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                updateLevel()
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    /// Termina la grabación y devuelve el archivo.
    func stop() -> URL? {
        guard let recorder else { return nil }
        recorder.stop()
        finish()
        return recorder.url
    }

    /// Termina la grabación y borra el archivo.
    func cancel() {
        guard let recorder else { return }
        recorder.stop()
        recorder.deleteRecording()
        finish()
    }

    private func finish() {
        meterTask?.cancel()
        meterTask = nil
        recorder = nil
        isRecording = false
        level = 0
        startedAt = nil
        deactivateSession()
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func updateLevel() {
        guard let recorder else { return }
        guard recorder.isRecording else {
            if isRecording, !reachedLimit { reachedLimit = true }
            level = 0
            return
        }
        recorder.updateMeters()
        // De -50 dB (silencio) a 0 dB.
        let power = Double(recorder.averagePower(forChannel: 0))
        level = min(max((power + 50) / 50, 0), 1)
    }
}

/// Dictado: graba la voz y la convierte en texto con Groq. Si la transcripción falla, conserva el audio para
/// reintentar sin volver a hablar.
@MainActor
@Observable
final class DictationSession {
    enum Phase: Equatable {
        case idle, recording, transcribing
    }

    private(set) var phase: Phase = .idle
    private(set) var error: String?
    /// Hay una grabación que no se pudo convertir en texto.
    private(set) var canRetry = false
    /// Se negó el permiso del micrófono (se activa en la app Configuración).
    private(set) var needsMicrophonePermission = false
    let recorder = AudioRecorder()

    @ObservationIgnored private var failedAudio: URL?
    /// Cambia al cancelar, para descartar una transcripción que llegue tarde.
    @ObservationIgnored private var generation = 0

    func start() async {
        guard phase == .idle else { return }
        error = nil
        discardFailedAudio()
        needsMicrophonePermission = !(await recorder.requestPermission())
        guard !needsMicrophonePermission else {
            error = "Leonera no tiene permiso para usar el micrófono. Actívalo en la app Configuración."
            return
        }
        do {
            try recorder.start()
            phase = .recording
        } catch {
            self.error = "No se pudo empezar a grabar: \(error.localizedDescription)"
        }
    }

    /// Termina de grabar y devuelve el texto, o `nil` si falló (el motivo queda en `error`).
    func finish() async -> String? {
        guard phase == .recording, let url = recorder.stop() else { return nil }
        return await transcribe(url)
    }

    /// Vuelve a mandar la última grabación que falló.
    func retry() async -> String? {
        guard phase == .idle, let url = failedAudio else { return nil }
        return await transcribe(url)
    }

    func cancel() {
        generation += 1
        recorder.cancel()
        discardFailedAudio()
        phase = .idle
    }

    /// Forgets the last error, along with the recording kept to retry it.
    func dismissError() {
        guard phase == .idle else { return }
        error = nil
        needsMicrophonePermission = false
        discardFailedAudio()
    }

    private func transcribe(_ url: URL) async -> String? {
        phase = .transcribing
        error = nil
        let token = generation
        defer { if token == generation { phase = .idle } }
        do {
            let text = try await ReminderAssistant.transcribe(audioAt: url)
            guard token == generation else { return nil }
            try? FileManager.default.removeItem(at: url)
            failedAudio = nil
            canRetry = false
            guard !text.isEmpty else {
                error = "No se escuchó nada en la grabación. Intenta de nuevo."
                return nil
            }
            return text
        } catch {
            guard token == generation else { return nil }
            failedAudio = url
            canRetry = true
            self.error = error.localizedDescription
            return nil
        }
    }

    private func discardFailedAudio() {
        if let failedAudio { try? FileManager.default.removeItem(at: failedAudio) }
        failedAudio = nil
        canRetry = false
    }
}
