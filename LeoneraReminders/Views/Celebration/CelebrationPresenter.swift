import SpriteKit
import UIKit

/// Plays the animation chosen in Settings over the whole app when a reminder is completed.
///
/// The animation runs in its own window above everything else, so it is also seen over a sheet that closes at
/// that moment (like the "Desliza para completar" sheet). The window lets every touch through to the app, which
/// keeps working while the animation plays; only the fireworks can take the touches, as `FireworksInteraction`
/// decides.
@MainActor
final class CelebrationPresenter {
    static let shared = CelebrationPresenter()

    private var window: UIWindow?
    private var controller: CelebrationViewController?
    private var show: Show?

    private init() {}

    /// Plays the animation chosen in Settings; called right after a reminder is completed.
    func celebrateCompletion() {
        play(SettingsStore.shared.settings.completionAnimation)
    }

    /// Plays `animation`, also as a preview in Settings. Calling it again while it plays layers a new one over it;
    /// a different animation replaces it.
    func play(_ animation: CompletionAnimation) {
        guard animation != .off else { return }
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        let reducedMotion = UIAccessibility.isReduceMotionEnabled
        // The app's own window, which reflects a color scheme chosen in the app and not only the system's.
        let style = (windowScene.keyWindow ?? windowScene.windows.first)?.traitCollection.userInterfaceStyle
            ?? windowScene.traitCollection.userInterfaceStyle
        let darkAppearance = style == .dark
        let interaction = animation.alwaysAllowsInteraction
            ? FireworksInteraction.allowsApp
            : SettingsStore.shared.settings.fireworksInteraction

        if let show, show.animation == animation {
            setInteraction(interaction)
            show.celebrate(reducedMotion: reducedMotion, darkAppearance: darkAppearance)
            return
        }
        // Another animation was playing (a preview in Settings): the new one replaces it.
        tearDown()
        let bounds = windowScene.coordinateSpace.bounds
        guard let show = Show(animation, size: bounds.size) else { return }

        let window = CelebrationWindow(windowScene: windowScene)
        window.frame = bounds
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        // VoiceOver never lands on the animation.
        window.accessibilityElementsHidden = true
        let controller = CelebrationViewController()
        window.rootViewController = controller
        // The window receives every tap on it, so the tap works whichever view it lands on.
        let tap = UITapGestureRecognizer(target: controller, action: #selector(CelebrationViewController.handleTap))
        window.addGestureRecognizer(tap)
        self.window = window
        self.controller = controller
        self.show = show
        setInteraction(interaction)
        window.isHidden = false

        let scene = show.scene
        show.setOnFinished { [weak self, weak scene] in
            // Only the scene still on screen frees the window.
            guard let self, let scene, self.show?.scene === scene else { return }
            self.tearDown()
        }
        controller.onTap = { [weak self] in self?.show?.skip() }
        controller.present(
            scene,
            framesPerSecond: windowScene.screen.maximumFramesPerSecond,
            drawsInAnyOrder: animation == .fireworks
        )
        show.celebrate(reducedMotion: reducedMotion, darkAppearance: darkAppearance)
    }

    /// Lets the touches reach the app, takes them all, or takes them all and lets a tap end the show.
    private func setInteraction(_ interaction: FireworksInteraction) {
        guard let window, let controller else { return }
        window.isUserInteractionEnabled = interaction != .allowsApp
        controller.interaction = interaction
    }

    /// Frees the window and the scene once the animation is over; the next one creates new ones.
    private func tearDown() {
        controller?.skView.presentScene(nil)
        window?.isHidden = true
        window = nil
        controller = nil
        show = nil
    }
}

/// The scene playing in the window: the fireworks, or one of the animations made of pieces.
@MainActor
private enum Show {
    case fireworks(FireworksScene)
    case pieces(ParticleCelebrationScene, CompletionAnimation)

    init?(_ animation: CompletionAnimation, size: CGSize) {
        switch animation {
        case .fireworks: self = .fireworks(FireworksScene(size: size))
        case .confetti: self = .pieces(ConfettiScene(size: size), animation)
        case .coins: self = .pieces(CoinsScene(size: size), animation)
        case .balloons: self = .pieces(BalloonsScene(size: size), animation)
        case .stars: self = .pieces(StarsScene(size: size), animation)
        case .checkmark: self = .pieces(CheckmarkScene(size: size), animation)
        case .hearts: self = .pieces(HeartsScene(size: size), animation)
        case .glow: self = .pieces(GlowScene(size: size), animation)
        case .emoji: self = .pieces(EmojiScene(size: size), animation)
        case .off: return nil
        }
    }

    var animation: CompletionAnimation {
        switch self {
        case .fireworks: CompletionAnimation.fireworks
        case .pieces(_, let animation): animation
        }
    }

    var scene: SKScene {
        switch self {
        case .fireworks(let scene): scene
        case .pieces(let scene, _): scene
        }
    }

    func celebrate(reducedMotion: Bool, darkAppearance: Bool) {
        switch self {
        case .fireworks(let scene): scene.celebrate(reducedMotion: reducedMotion, darkAppearance: darkAppearance)
        case .pieces(let scene, _): scene.celebrate(reducedMotion: reducedMotion, darkAppearance: darkAppearance)
        }
    }

    func skip() {
        switch self {
        case .fireworks(let scene): scene.skip()
        case .pieces(let scene, _): scene.skip()
        }
    }

    func setOnFinished(_ handler: @escaping () -> Void) {
        switch self {
        case .fireworks(let scene): scene.onFinished = handler
        case .pieces(let scene, _): scene.onFinished = handler
        }
    }
}

/// The window of the animation. It never becomes the key window, so the app keeps its own.
private final class CelebrationWindow: UIWindow {
    override var canBecomeKey: Bool {
        false
    }
}

private final class CelebrationViewController: UIViewController {
    let skView = SKView()
    /// Decides what a tap does on the fireworks.
    var interaction: FireworksInteraction = .allowsApp
    /// Called when the fireworks are tapped while `interaction` is `.tapToFinish`.
    var onTap: (() -> Void)?

    override func loadView() {
        skView.allowsTransparency = true
        skView.isOpaque = false
        skView.backgroundColor = .clear
        // The view only draws; the window takes the touches when it takes any.
        skView.isUserInteractionEnabled = false
        skView.accessibilityElementsHidden = true
        view = skView
    }

    /// Target of the tap gesture on the window.
    @objc func handleTap() {
        guard interaction == .tapToFinish else { return }
        onTap?()
    }

    /// With `drawsInAnyOrder`, SpriteKit batches the sprites freely, which suits the fireworks: their additive
    /// stars look the same in any order. The other animations draw their pieces in order (a coin's shade over the
    /// coin, the closer balloons in front).
    func present(_ scene: SKScene, framesPerSecond: Int, drawsInAnyOrder: Bool) {
        loadViewIfNeeded()
        skView.ignoresSiblingOrder = drawsInAnyOrder
        // 120 Hz on ProMotion screens (allowed by `CADisableMinimumFrameDurationOnPhone`).
        skView.preferredFramesPerSecond = framesPerSecond
        skView.presentScene(scene)
    }
}
