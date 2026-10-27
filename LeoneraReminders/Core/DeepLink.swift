import Foundation

/// A link that opens Leonera on a specific screen, such as the lock screen widget that starts a voice recording.
enum DeepLink: Equatable, Sendable {
    /// Opens voice capture, which starts recording right away.
    case voiceRecording

    /// The link the lock screen widget opens. The widget (`LeoneraWidgets`) repeats this string, so keep both in sync.
    static let voiceRecordingURL = URL(string: "leonera://voice-recording")!

    /// The link a URL received by the app stands for, or `nil` if the app does not handle it.
    init?(url: URL) {
        guard url.scheme == "leonera", url.host() == "voice-recording" else { return nil }
        self = .voiceRecording
    }
}
