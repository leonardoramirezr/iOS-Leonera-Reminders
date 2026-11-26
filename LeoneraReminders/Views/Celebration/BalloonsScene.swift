import SpriteKit
import UIKit

/// Balloons of every color float up from the bottom of the screen and away, swaying on their strings.
final class BalloonsScene: ParticleCelebrationScene {
    private let impact = UIImpactFeedbackGenerator(style: .soft)

    override func start() {
        impact.prepare()
        impact.impactOccurred(intensity: 0.7)
        let unit = self.unit
        let count = pieceCount(10, reduced: 4, minimum: 3)
        // One lane each, shuffled, so they spread over the whole width without a fixed order.
        let lanes = (0..<count).map { (CGFloat($0) + CGFloat.random(in: 0.15...0.85)) / CGFloat(count) }.shuffled()
        let margin = 28 * unit
        let textures = CelebrationTextures.balloons.shuffled()
        let stringColor = darkAppearance ? UIColor(white: 0.8, alpha: 1) : UIColor(white: 0.55, alpha: 1)
        for index in 0..<count {
            let width = CGFloat.random(in: 56...86) * unit
            let height = CelebrationTextures.balloonSize.height * width / CelebrationTextures.balloonSize.width
            // The bigger ones look closer: they rise faster and pass in front.
            let depth = (width / unit - 56) / 30
            let riseSpeed = size.height * (0.5 + 0.3 * depth + CGFloat.random(in: -0.04...0.04)) * (reducedMotion ? 0.8 : 1)
            let stringLength = CGFloat.random(in: 70...105) * unit

            let sprite = SKSpriteNode(texture: textures[index % textures.count], size: CGSize(width: width, height: height))
            sprite.zPosition = depth
            let string = SKSpriteNode(texture: CelebrationTextures.balloonString, size: CGSize(width: 12 * unit, height: stringLength))
            string.anchorPoint = CGPoint(x: 0.5, y: 1)
            string.position = CGPoint(x: 0, y: -height / 2 + 1)
            string.color = stringColor
            string.colorBlendFactor = 1
            string.alpha = 0.85
            // Behind its balloon, so it hangs from the knot.
            string.zPosition = -0.01
            sprite.addChild(string)

            let balloon = Balloon(
                node: sprite,
                position: CGPoint(
                    x: margin + lanes[index] * (size.width - margin * 2),
                    y: -height / 2 - CGFloat.random(in: 0...40) * unit
                ),
                velocity: CGVector(dx: 0, dy: riseSpeed * 0.55),
                delay: Double(index) * 0.05 + Double.random(in: 0...0.3),
                lifetime: 8,
                string: string,
                unit: unit
            )
            // Lifted up to `riseSpeed`, which the air keeps it from passing.
            balloon.drag = 1.8
            balloon.acceleration = CGVector(dx: 0, dy: riseSpeed * 1.8)
            balloon.swayAmplitude = CGFloat.random(in: 10...22) * unit
            balloon.swayRate = CGFloat.random(in: 1.6...2.6)
            balloon.swayPhase = CGFloat.random(in: 0...(2 * .pi))
            balloon.exitMargin = height / 2 + stringLength
            add(balloon)
        }
    }

    override func render(_ particle: CelebrationParticle) {
        super.render(particle)
        guard let balloon = particle as? Balloon else { return }
        // It leans toward where it sways, and its string trails behind.
        let lean = cos(balloon.swayRate * CGFloat(balloon.age) + balloon.swayPhase) * balloon.swayAmplitude / (16 * balloon.unit)
        balloon.node.zRotation = -0.13 * lean
        balloon.string.zRotation = 0.07 * lean
    }
}

private final class Balloon: CelebrationParticle {
    let string: SKSpriteNode
    /// The scene's design unit when it was let go.
    let unit: CGFloat

    init(node: SKNode, position: CGPoint, velocity: CGVector, delay: TimeInterval, lifetime: TimeInterval, string: SKSpriteNode, unit: CGFloat) {
        self.string = string
        self.unit = unit
        super.init(node: node, position: position, velocity: velocity, delay: delay, lifetime: lifetime)
    }
}
