import SpriteKit
import UIKit

/// Golden stars burst from the middle of the screen with a flash and a shower of glitter, then spin, twinkle and
/// drift down as they fade.
final class StarsScene: ParticleCelebrationScene {
    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let twinkle = UIImpactFeedbackGenerator(style: .light)

    override func start() {
        impact.prepare()
        twinkle.prepare()
        impact.impactOccurred(intensity: 0.85)
        schedule(after: 0.22) { [weak self] in self?.twinkle.impactOccurred(intensity: 0.4) }
        schedule(after: 0.4) { [weak self] in self?.twinkle.impactOccurred(intensity: 0.3) }

        let unit = self.unit
        let center = CGPoint(x: size.width / 2, y: size.height * 0.56)
        // Light adds up over the dark appearance; over the light one it is laid on top.
        let blend: SKBlendMode = darkAppearance ? .add : .alpha

        let flash = SKSpriteNode(texture: CelebrationTextures.glow, size: CGSize(width: 220 * unit, height: 220 * unit))
        flash.color = CelebrationPalette.starGlow
        flash.colorBlendFactor = 1
        flash.blendMode = blend
        flash.zPosition = -1
        let burst = StarPiece(node: flash, position: center, lifetime: 0.7, kind: .flash)
        burst.opacity = darkAppearance ? 0.6 : 0.45
        add(burst)

        let count = pieceCount(24, reduced: 10, minimum: 6)
        for index in 0..<count {
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi + CGFloat.random(in: -0.14...0.14)
            let distance = CGFloat.random(in: 0.24...0.52) * size.width * (reducedMotion ? 0.7 : 1)
            let drag: CGFloat = 3.4
            // With this drag, a star thrown at `distance * drag` stops about `distance` away.
            let launchSpeed = distance * drag
            let side = CGFloat.random(in: 20...40) * unit
            let sprite = SKSpriteNode(texture: CelebrationTextures.stars.randomElement(), size: CGSize(width: side, height: side))
            sprite.zPosition = CGFloat.random(in: 0...1)
            let glow = SKSpriteNode(texture: CelebrationTextures.glow, size: CGSize(width: side * 2.6, height: side * 2.6))
            glow.color = CelebrationPalette.starGlow
            glow.colorBlendFactor = 1
            glow.blendMode = blend
            glow.zPosition = -0.5
            glow.isHidden = true
            addChild(glow)

            let star = StarPiece(
                node: sprite,
                position: center,
                velocity: CGVector(dx: cos(angle) * launchSpeed, dy: sin(angle) * launchSpeed * 1.25),
                delay: Double.random(in: 0...0.04),
                lifetime: Double.random(in: 1.3...1.9),
                kind: .star
            )
            star.drag = drag
            star.acceleration = CGVector(dx: 0, dy: -150 * unit)
            star.rotation = CGFloat.random(in: 0...(2 * .pi))
            star.spin = CGFloat.random(in: -4...4)
            star.spinDrag = 1.2
            star.fadeOut = 0.55
            star.twinkleRate = CGFloat.random(in: 9...15)
            star.twinklePhase = CGFloat.random(in: 0...(2 * .pi))
            star.glow = glow
            star.glowOpacity = darkAppearance ? 0.55 : 0.28
            add(star)
        }

        let glitterCount = reducedMotion ? 0 : pieceCount(36, reduced: 0)
        // Pale glitter would not show over the light appearance.
        let glitterColors = darkAppearance ? CelebrationPalette.stars + [CelebrationPalette.paleGold] : CelebrationPalette.stars
        for _ in 0..<glitterCount {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 0.15...0.6) * size.width
            let drag: CGFloat = 2.6
            let side = CGFloat.random(in: 3...5.5) * unit * 3
            let sprite = SKSpriteNode(texture: CelebrationTextures.glow, size: CGSize(width: side, height: side))
            sprite.color = glitterColors.randomElement() ?? CelebrationPalette.starGlow
            sprite.colorBlendFactor = 1
            sprite.blendMode = blend
            sprite.zPosition = CGFloat.random(in: 0...1)
            let speck = StarPiece(
                node: sprite,
                position: center,
                velocity: CGVector(dx: cos(angle) * distance * drag, dy: sin(angle) * distance * drag * 1.2),
                delay: Double.random(in: 0...0.06),
                lifetime: Double.random(in: 0.6...1.2),
                kind: .glitter
            )
            speck.drag = drag
            speck.acceleration = CGVector(dx: 0, dy: -220 * unit)
            speck.fadeOut = 0.4
            speck.twinkleRate = CGFloat.random(in: 14...22)
            speck.twinklePhase = CGFloat.random(in: 0...(2 * .pi))
            add(speck)
        }
    }

    override func render(_ particle: CelebrationParticle) {
        super.render(particle)
        guard let piece = particle as? StarPiece else { return }
        let node = piece.node
        let age = CGFloat(piece.age)
        switch piece.kind {
        case .flash:
            let progress = piece.progress
            node.setScale(0.5 + 0.7 * Easing.outCubic(progress))
            node.alpha = piece.opacity * (1 - progress)
        case .star:
            let pop = Easing.pop(age, start: 0.2, overshoot: 1.15, rise: 0.16, settle: 0.3)
            node.setScale(pop * (1 + 0.12 * sin(piece.twinkleRate * age + piece.twinklePhase)))
            if let glow = piece.glow {
                glow.isHidden = false
                glow.position = node.position
                glow.setScale(pop)
                glow.alpha = piece.glowOpacity * piece.fade * (0.75 + 0.25 * sin(piece.twinkleRate * 0.7 * age))
            }
        case .glitter:
            // Glitter blinks.
            let isLit = sin(piece.twinkleRate * age + piece.twinklePhase) > -0.2
            node.alpha = piece.fade * (isLit ? 1 : 0.15)
        }
    }

    override func didRemove(_ particle: CelebrationParticle) {
        (particle as? StarPiece)?.glow?.removeFromParent()
    }
}

private final class StarPiece: CelebrationParticle {
    enum Kind {
        /// The flash where the stars burst out.
        case flash
        case star
        case glitter
    }

    let kind: Kind
    var twinkleRate: CGFloat = 0
    var twinklePhase: CGFloat = 0
    /// The light around a star; it is a node of the scene, so it does not spin with the star.
    var glow: SKSpriteNode?
    var glowOpacity: CGFloat = 0

    init(node: SKNode, position: CGPoint, velocity: CGVector = .zero, delay: TimeInterval = 0, lifetime: TimeInterval, kind: Kind) {
        self.kind = kind
        super.init(node: node, position: position, velocity: velocity, delay: delay, lifetime: lifetime)
    }
}
