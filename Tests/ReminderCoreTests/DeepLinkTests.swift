import Foundation
import Testing
@testable import ReminderCore

struct DeepLinkTests {
    @Test func theWidgetLinkOpensVoiceRecording() {
        #expect(DeepLink(url: DeepLink.voiceRecordingURL) == .voiceRecording)
    }

    @Test func otherLinksAreNotHandled() throws {
        #expect(try DeepLink(url: #require(URL(string: "leonera://reminders"))) == nil)
        #expect(try DeepLink(url: #require(URL(string: "https://example.com/voice-recording"))) == nil)
        #expect(try DeepLink(url: #require(URL(string: "other://voice-recording"))) == nil)
    }
}
