import SpriteKit
import UIKit

/// Hearts pop up from the bottom of the screen and float away, swaying and growing, to a heartbeat.
final class HeartsScene: ParticleCelebrationScene {
    private let impact = UIImpactFeedbackGenerator(style: .medium)

    override func start() {
        impact.prepare()
        // Lub-dub.
        impact.impactOccurred(intensity: 0.8)
        schedule(after: 0.14) { [weak self] in
            self?.impact.impactOccurred(intensity: 0.55)
        }

        let unit = self.unit
        let count = pieceCount(18, reduced: 7, minimum: 5)
        for index in 0..<count {
            let side = CGFloat.random(in: 30...50) * unit
            let sprite = SKSpriteNode(texture: CelebrationTextures.hearts.randomElement(), size: CGSize(width: side, height: side))
            sprite.zPosition = CGFloat.random(in: 0...1)
            let heart = CelebrationParticle(
                node: sprite,
                position: CGPoint(x: size.width * (0.5 + CGFloat.random(in: -0.24...0.24)), y: -16 * unit),
                velocity: CGVector(dx: CGFloat.random(in: -0.1...0.1) * size.width, dy: size.height * CGFloat.random(in: 0.85...1.25)),
                delay: Double(index) * 0.7 / Double(count) + Double.random(in: 0...0.04),
                lifetime: Double.random(in: 1.5...2.1)
            )
            // They slow down as they rise, about two thirds of the way up.
            heart.drag = 1.5
            heart.swayAmplitude = CGFloat.random(in: 10...24) * unit
            heart.swayRate = CGFloat.random(in: 2.6...4.2)
            heart.swayPhase = CGFloat.random(in: 0...(2 * .pi))
            heart.fadeOut = 0.7
            add(heart)
        }
    }

    override func render(_ particle: CelebrationParticle) {
        super.render(particle)
        let age = CGFloat(particle.age)
        let pop = Easing.pop(age, start: 0.25, overshoot: 1.18, rise: 0.16, settle: 0.3)
        particle.node.setScale(pop * (1 + 0.25 * particle.progress))
        // It leans toward where it sways.
        particle.node.zRotation = -0.22 * cos(particle.swayRate * age + particle.swayPhase)
    }
}
