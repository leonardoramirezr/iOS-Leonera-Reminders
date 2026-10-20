import SpriteKit
import UIKit

/// Plays the fireworks over the whole app when a reminder is completed.
///
/// The show runs in its own window above everything else, so it is also seen over a sheet that closes at
/// that moment (like the "Desliza para completar" sheet), and it never blocks touches.
@MainActor
final class FireworksPresenter {
    static let shared = FireworksPresenter()

    private var window: UIWindow?
    private var scene: FireworksScene?

    private init() {}

    func celebrate() {
        guard SettingsStore.shared.settings.celebratesCompletion else { return }
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        let reducedMotion = UIAccessibility.isReduceMotionEnabled
        // The app's own window, which reflects a color scheme chosen in the app and not only the system's.
        let style = (windowScene.keyWindow ?? windowScene.windows.first)?.traitCollection.userInterfaceStyle
            ?? windowScene.traitCollection.userInterfaceStyle
        let darkAppearance = style == .dark

        if let scene {
            scene.celebrate(reducedMotion: reducedMotion, darkAppearance: darkAppearance)
            return
        }

        let window = PassthroughWindow(windowScene: windowScene)
        window.frame = windowScene.coordinateSpace.bounds
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = false
        let controller = FireworksViewController()
        window.rootViewController = controller
        window.isHidden = false

        let scene = FireworksScene(size: window.bounds.size)
        scene.onFinished = { [weak self] in self?.tearDown() }
        controller.present(scene, framesPerSecond: windowScene.screen.maximumFramesPerSecond)
        scene.celebrate(reducedMotion: reducedMotion, darkAppearance: darkAppearance)

        self.window = window
        self.scene = scene
    }

    /// Frees the window and the scene once the show is over; the next celebration creates new ones.
    private func tearDown() {
        (window?.rootViewController as? FireworksViewController)?.skView.presentScene(nil)
        window?.isHidden = true
        window = nil
        scene = nil
    }
}

/// A window that lets every touch through to the app below it.
private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }

    override var canBecomeKey: Bool {
        false
    }
}

private final class FireworksViewController: UIViewController {
    let skView = SKView()

    override func loadView() {
        skView.allowsTransparency = true
        skView.isOpaque = false
        skView.backgroundColor = .clear
        // Additive stars look the same in any order, so SpriteKit can batch them freely.
        skView.ignoresSiblingOrder = true
        skView.isUserInteractionEnabled = false
        view = skView
    }

    func present(_ scene: SKScene, framesPerSecond: Int) {
        loadViewIfNeeded()
        // 120 Hz on ProMotion screens (allowed by `CADisableMinimumFrameDurationOnPhone`).
        skView.preferredFramesPerSecond = framesPerSecond
        skView.presentScene(scene)
    }
}
