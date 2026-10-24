import SpriteKit
import UIKit

/// Plays the fireworks over the whole app when a reminder is completed.
///
/// The show runs in its own window above everything else, so it is also seen over a sheet that closes at
/// that moment (like the "Desliza para completar" sheet). Whether it also takes the touches meant for the app
/// depends on `FireworksInteraction`.
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
        let interaction = SettingsStore.shared.settings.fireworksInteraction

        if let scene {
            setInteraction(interaction)
            scene.celebrate(reducedMotion: reducedMotion, darkAppearance: darkAppearance)
            return
        }

        let window = FireworksWindow(windowScene: windowScene)
        window.frame = windowScene.coordinateSpace.bounds
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        let controller = FireworksViewController()
        window.rootViewController = controller
        self.window = window
        setInteraction(interaction)
        window.isHidden = false

        let scene = FireworksScene(size: window.bounds.size)
        scene.onFinished = { [weak self] in self?.tearDown() }
        controller.onTap = { [weak scene] in scene?.skip() }
        controller.present(scene, framesPerSecond: windowScene.screen.maximumFramesPerSecond)
        scene.celebrate(reducedMotion: reducedMotion, darkAppearance: darkAppearance)

        self.scene = scene
    }

    /// Lets the touches reach the app, takes them all, or takes them all and lets a tap end the show.
    private func setInteraction(_ interaction: FireworksInteraction) {
        guard let window, let controller = window.rootViewController as? FireworksViewController else { return }
        window.isUserInteractionEnabled = interaction != .allowsApp
        controller.skView.isUserInteractionEnabled = interaction == .tapToFinish
    }

    /// Frees the window and the scene once the show is over; the next celebration creates new ones.
    private func tearDown() {
        (window?.rootViewController as? FireworksViewController)?.skView.presentScene(nil)
        window?.isHidden = true
        window = nil
        scene = nil
    }
}

/// The window of the show. It never becomes the key window, so the app keeps its own.
private final class FireworksWindow: UIWindow {
    override var canBecomeKey: Bool {
        false
    }
}

private final class FireworksViewController: UIViewController {
    let skView = SKView()
    /// Called when the show is tapped; only reached while `skView` takes touches.
    var onTap: (() -> Void)?

    override func loadView() {
        skView.allowsTransparency = true
        skView.isOpaque = false
        skView.backgroundColor = .clear
        // Additive stars look the same in any order, so SpriteKit can batch them freely.
        skView.ignoresSiblingOrder = true
        skView.isUserInteractionEnabled = false
        skView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        view = skView
    }

    @objc private func handleTap() {
        onTap?()
    }

    func present(_ scene: SKScene, framesPerSecond: Int) {
        loadViewIfNeeded()
        // 120 Hz on ProMotion screens (allowed by `CADisableMinimumFrameDurationOnPhone`).
        skView.preferredFramesPerSecond = framesPerSecond
        skView.presentScene(scene)
    }
}
