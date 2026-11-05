import Foundation

/// A link that opens Leonera on a specific screen, such as the lock screen widgets.
enum DeepLink: Equatable, Sendable {
    /// Opens voice capture, which starts recording right away.
    case voiceRecording
    /// Opens the reminder list (the app's home screen), closing whatever was presented on top of it.
    case home

    /// The link the «Grabar recordatorio» lock screen widget opens. The widget (`LeoneraWidgets`) repeats this
    /// string, so keep both in sync.
    static let voiceRecordingURL = URL(string: "leonera://voice-recording")!

    /// The link the «Abrir Leonera» lock screen widget opens. The widget (`LeoneraWidgets`) repeats this string,
    /// so keep both in sync.
    static let homeURL = URL(string: "leonera://home")!

    /// The link a URL received by the app stands for, or `nil` if the app does not handle it.
    init?(url: URL) {
        guard url.scheme == "leonera" else { return nil }
        switch url.host() {
        case "voice-recording": self = .voiceRecording
        case "home": self = .home
        default: return nil
        }
    }
}
