import SwiftUI
import UIKit

/// The fireworks that celebrate completing a reminder.
///
/// They are drawn in their own transparent window above the app, so they keep playing while the sheet that
/// completed the reminder slides away, and touches go straight through to the app underneath.
@MainActor
enum Celebration {
    private static var window: UIWindow?
    private static var simulation: FireworksSimulation?
    private static let burstFeedback = UIImpactFeedbackGenerator(style: .rigid)

    /// Plays a new fireworks show. Completing another reminder while one is playing adds more rockets to it.
    /// Nothing happens if it is turned off in Settings or Reduce Motion is on.
    static func celebrateCompletion() {
        guard SettingsStore.shared.settings.celebratesCompletion, !UIAccessibility.isReduceMotionEnabled else { return }
        let budget = ProcessInfo.processInfo.isLowPowerModeEnabled ? 0.6 : 1
        burstFeedback.prepare()

        if let simulation {
            simulation.enqueueShow(budget: budget)
            return
        }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        let simulation = FireworksSimulation()
        simulation.onBurst = { intensity in
            Task { @MainActor in burstFeedback.impactOccurred(intensity: intensity) }
        }
        simulation.enqueueShow(budget: budget)

        let host = UIHostingController(rootView: FireworksView(simulation: simulation) { finish() })
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false

        let window = UIWindow(windowScene: scene)
        // Above the app's own window and the sheets it presents.
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = false
        window.rootViewController = host
        // Shown without becoming the key window, so it never takes the keyboard or focus from the app.
        window.isHidden = false

        self.window = window
        self.simulation = simulation
    }

    private static func finish() {
        // A show added right before the last one ended keeps the window.
        guard simulation?.isFinished ?? true else { return }
        window?.isHidden = true
        window = nil
        simulation = nil
    }
}
