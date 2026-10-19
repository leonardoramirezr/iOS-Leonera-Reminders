import UIKit

enum Haptics {
    /// La misma vibración que al marcar un recordatorio como completado. Se lanza directo (y no con
    /// `.sensoryFeedback`) para que suene aunque la vista se cierre en ese mismo momento.
    @MainActor
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
