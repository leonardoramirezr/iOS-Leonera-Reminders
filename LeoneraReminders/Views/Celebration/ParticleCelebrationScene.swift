import SpriteKit
import UIKit

/// One moving piece of a celebration (a strip of confetti, a coin, a balloon...), simulated in scene points with
/// y pointing up. Subclasses keep the extra nodes and values that a kind of piece needs.
class CelebrationParticle {
    let node: SKNode
    var position: CGPoint
    var velocity: CGVector
    /// Constant acceleration: a negative `dy` is gravity, a positive one lifts it like a balloon.
    var acceleration = CGVector.zero
    /// How fast the velocity decays, per second, like air resistance.
    var drag: CGFloat = 0
    /// Seconds since it appeared; negative while it waits to appear.
    var age: TimeInterval
    let lifetime: TimeInterval
    var rotation: CGFloat = 0
    /// Radians per second.
    var spin: CGFloat = 0
    /// How fast the spin slows down, per second.
    var spinDrag: CGFloat = 0
    /// Turn around its own vertical axis, drawn by squashing the node horizontally. A rate of 0 never turns it.
    var flipPhase: CGFloat = 0
    var flipRate: CGFloat = 0
    /// Side-to-side drift added to its position, like a falling leaf or a rising balloon.
    var swayAmplitude: CGFloat = 0
    var swayRate: CGFloat = 0
    var swayPhase: CGFloat = 0
    var scale: CGFloat = 1
    /// Opacity before the fades.
    var opacity: CGFloat = 1
    /// Seconds over which it fades in after appearing and out before its lifetime ends.
    var fadeIn: TimeInterval = 0
    var fadeOut: TimeInterval = 0
    /// When set, it is taken away as soon as it is this far off screen and moving away from it.
    var exitMargin: CGFloat?

    init(node: SKNode, position: CGPoint, velocity: CGVector = .zero, delay: TimeInterval = 0, lifetime: TimeInterval) {
        self.node = node
        self.position = position
        self.velocity = velocity
        self.age = -delay
        self.lifetime = lifetime
    }

    /// Current side-to-side offset.
    var sway: CGFloat {
        swayAmplitude * sin(swayRate * CGFloat(age) + swayPhase)
    }

    /// Fraction of its lifetime gone by, from 0 to 1.
    var progress: CGFloat {
        CGFloat(min(max(age / lifetime, 0), 1))
    }

    /// Opacity from the fade in and the fade out, from 0 to 1.
    var fade: CGFloat {
        let shown = max(age, 0)
        var value = 1.0
        if fadeIn > 0 { value = min(value, shown / fadeIn) }
        if fadeOut > 0 { value = min(value, (lifetime - shown) / fadeOut) }
        return CGFloat(min(max(value, 0), 1))
    }
}

/// Base of the completion animations made of pieces that move with simple physics (all but the fireworks): it
/// steps every piece each frame, takes it away when it is done and reports once the scene is empty.
///
/// The background stays clear and nothing dims the app, which can be used while the animation plays.
class ParticleCelebrationScene: SKScene {
    /// Called once the last piece is gone.
    var onFinished: (() -> Void)?

    private(set) var particles: [CelebrationParticle] = []
    private(set) var reducedMotion = false
    private(set) var darkAppearance = false
    /// Scales the number of pieces (fewer in Low Power Mode).
    private(set) var density: CGFloat = 1

    private var pendingActions = 0
    private var lastUpdateTime: TimeInterval?
    private var isFinishing = false
    /// How fast time runs: faster once the animation is skipped.
    private var timeScale: CGFloat = 1

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        anchorPoint = .zero
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Points per design unit: sizes are tuned for a 390 pt wide iPhone and scale from there.
    var unit: CGFloat {
        min(max(min(size.width, size.height) / 390, 0.8), 1.6)
    }

    /// Adds a new animation. Calling it while another one is playing layers the new one over it.
    func celebrate(reducedMotion: Bool, darkAppearance: Bool) {
        self.reducedMotion = reducedMotion
        self.darkAppearance = darkAppearance
        density = ProcessInfo.processInfo.isLowPowerModeEnabled ? 0.6 : 1
        isFinishing = false
        timeScale = 1
        start()
    }

    /// Adds the pieces of one animation. Each animation overrides it.
    func start() {}

    /// Ends the animation early: what was still to come is cancelled and what is on screen plays out faster.
    func skip() {
        removeAllActions()
        pendingActions = 0
        timeScale = 3
    }

    /// Adds a piece, hidden until its delay is over.
    func add(_ particle: CelebrationParticle) {
        particle.node.isHidden = true
        addChild(particle.node)
        particles.append(particle)
    }

    /// Runs `block` after `delay`; the scene does not finish while it waits.
    func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) {
        pendingActions += 1
        run(.sequence([
            .wait(forDuration: delay),
            .run { [weak self] in
                self?.pendingActions -= 1
                block()
            },
        ]))
    }

    /// `full` pieces, or `reduced` ones with Reduce Motion, scaled by `density` and never fewer than `minimum`.
    func pieceCount(_ full: Int, reduced: Int, minimum: Int = 1) -> Int {
        max(minimum, Int((CGFloat(reducedMotion ? reduced : full) * density).rounded()))
    }

    // MARK: - Overridable steps

    /// Draws a piece where the simulation put it. Subclasses add their own touches after calling `super`.
    func render(_ particle: CelebrationParticle) {
        let node = particle.node
        node.position = CGPoint(x: particle.position.x + particle.sway, y: particle.position.y)
        node.zRotation = particle.rotation
        node.xScale = particle.scale * (particle.flipRate == 0 ? 1 : cos(particle.flipPhase))
        node.yScale = particle.scale
        node.alpha = particle.opacity * particle.fade
    }

    /// Called once a piece is taken away, for the nodes it keeps outside its own.
    func didRemove(_ particle: CelebrationParticle) {}

    /// Moves what is not a piece, like the check mark or the glow.
    func advance(dt: CGFloat) {}

    /// Whether what is not a piece is still on screen.
    var isPlaying: Bool {
        false
    }

    // MARK: - Simulation

    override func update(_ currentTime: TimeInterval) {
        // Clamped so a hitch (or coming back from the background) never makes the pieces jump.
        let elapsed = min(max(currentTime - (lastUpdateTime ?? currentTime), 0), 1.0 / 30)
        lastUpdateTime = currentTime
        let dt = CGFloat(elapsed) * timeScale
        if dt > 0 {
            step(dt: dt)
            advance(dt: dt)
        }
        finishIfIdle()
    }

    private func step(dt: CGFloat) {
        var index = 0
        while index < particles.count {
            let particle = particles[index]
            particle.age += Double(dt)
            guard particle.age >= 0 else {
                index += 1
                continue
            }
            // Drag first, then the acceleration: a burst slows down evenly and only then falls or rises.
            let damping = exp(-particle.drag * dt)
            particle.velocity.dx = particle.velocity.dx * damping + particle.acceleration.dx * dt
            particle.velocity.dy = particle.velocity.dy * damping + particle.acceleration.dy * dt
            particle.position.x += particle.velocity.dx * dt
            particle.position.y += particle.velocity.dy * dt
            if particle.spinDrag > 0 {
                particle.spin *= exp(-particle.spinDrag * dt)
            }
            particle.rotation += particle.spin * dt
            particle.flipPhase += particle.flipRate * dt
            if particle.age >= particle.lifetime || hasLeftScreen(particle) {
                particle.node.removeFromParent()
                didRemove(particle)
                particles.swapAt(index, particles.count - 1)
                particles.removeLast()
                continue
            }
            particle.node.isHidden = false
            render(particle)
            index += 1
        }
    }

    private func hasLeftScreen(_ particle: CelebrationParticle) -> Bool {
        guard let margin = particle.exitMargin else { return false }
        let point = particle.position
        if point.y < -margin, particle.velocity.dy <= 0 { return true }
        if point.y > size.height + margin, particle.velocity.dy >= 0 { return true }
        return point.x < -margin * 2 || point.x > size.width + margin * 2
    }

    private func finishIfIdle() {
        guard !isFinishing, pendingActions == 0, particles.isEmpty, !isPlaying else { return }
        isFinishing = true
        // Outside SpriteKit's update pass: the handler removes the scene from its view. An animation added in the
        // meantime cancels it.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isFinishing else { return }
            self.onFinished?()
        }
    }
}

/// Easing curves of the animations, for `t` from 0 to 1.
enum Easing {
    static func outCubic(_ t: CGFloat) -> CGFloat {
        1 - pow(1 - t, 3)
    }

    static func inCubic(_ t: CGFloat) -> CGFloat {
        t * t * t
    }

    static func inOutSine(_ t: CGFloat) -> CGFloat {
        (1 - cos(.pi * t)) / 2
    }

    static func inOutCubic(_ t: CGFloat) -> CGFloat {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// `t` kept between 0 and 1.
    static func clamp(_ t: CGFloat) -> CGFloat {
        min(max(t, 0), 1)
    }

    /// From `start` to `end` as `t` goes from 0 to 1.
    static func mix(_ start: CGFloat, _ end: CGFloat, _ t: CGFloat) -> CGFloat {
        start + (end - start) * t
    }

    /// The scale of something that pops in: it grows from `start` past its size to `overshoot` until the time
    /// `rise`, then settles at its size by the time `settle`.
    static func pop(_ time: CGFloat, start: CGFloat, overshoot: CGFloat, rise: CGFloat, settle: CGFloat) -> CGFloat {
        if time < rise { return mix(start, overshoot, outCubic(time / rise)) }
        if time < settle { return mix(overshoot, 1, inOutSine((time - rise) / (settle - rise))) }
        return 1
    }
}

/// Colors of the animations made of pieces.
enum CelebrationPalette {
    static let confetti: [UIColor] = [0xF26133, 0xFFC53D, 0x34C759, 0x32ADE6, 0x3D7BFF, 0xAF52DE, 0xFF4F8B, 0xFF3B30].map(color)
    static let balloons: [UIColor] = [0xFF3B4E, 0xFF8A2A, 0xFFD23F, 0x3CCB6C, 0x3A86FF, 0x9B5DE5, 0xFF5EAA, 0x2EC4B6].map(color)
    static let hearts: [UIColor] = [0xFF2D55, 0xFF4F7B, 0xFF6F91, 0xFF8FAB, 0xE0457B, 0xFF5A5F].map(color)
    static let stars: [UIColor] = [0xFFD23F, 0xFFC21A, 0xFFE066, 0xFFB020].map(color)
    /// Around the stars and in the flash of their burst.
    static let starGlow = color(0xFFD040)
    /// Glitter that shows over the dark appearance.
    static let paleGold = color(0xFFFAE6)
    /// The check mark's rings, over the light and the dark appearance.
    static let checkRing = color(0x34C759)
    static let checkRingDark = color(0x5EDC7A)
    static let sparkles: [UIColor] = [0x34C759, 0xFFC53D, 0xF26133, 0x32ADE6, 0xFF4F8B].map(color)
    /// The light around the edges, blended in a loop.
    static let glow: [UIColor] = [0xF26133, 0xFF4F8B, 0xAF52DE, 0x5E5CE6, 0x32ADE6, 0x34C759, 0xFFC53D].map(color)

    /// The color `fraction` of the way around the loop of `glow`.
    static func glowColor(at fraction: CGFloat) -> UIColor {
        let position = (fraction - fraction.rounded(.down)) * CGFloat(glow.count)
        let index = Int(position) % glow.count
        let next = (index + 1) % glow.count
        return glow[index].mixed(with: glow[next], by: position - position.rounded(.down))
    }

    /// A color from its hexadecimal RGB value, such as `0xF26133`.
    static func color(_ hex: Int) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension UIColor {
    /// This color moved toward `other` by `fraction`: 0 keeps it and 1 gives `other`.
    func mixed(with other: UIColor, by fraction: CGFloat) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        var otherRed: CGFloat = 0, otherGreen: CGFloat = 0, otherBlue: CGFloat = 0, otherAlpha: CGFloat = 0
        _ = getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        _ = other.getRed(&otherRed, green: &otherGreen, blue: &otherBlue, alpha: &otherAlpha)
        return UIColor(
            red: red + (otherRed - red) * fraction,
            green: green + (otherGreen - green) * fraction,
            blue: blue + (otherBlue - blue) * fraction,
            alpha: alpha + (otherAlpha - alpha) * fraction
        )
    }

    func lightened(_ fraction: CGFloat) -> UIColor {
        mixed(with: .white, by: fraction)
    }

    func darkened(_ fraction: CGFloat) -> UIColor {
        mixed(with: .black, by: fraction)
    }
}
