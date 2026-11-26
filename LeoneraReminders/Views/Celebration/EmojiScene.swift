import SpriteKit
import UIKit

/// Party emojis rain down over the whole screen, turning and swaying as they fall.
final class EmojiScene: ParticleCelebrationScene {
    private let impact = UIImpactFeedbackGenerator(style: .light)

    override func start() {
        impact.prepare()
        impact.impactOccurred(intensity: 0.7)
        let unit = self.unit
        let count = pieceCount(28, reduced: 10, minimum: 6)
        // One lane each, shuffled, so they spread over the whole width without a fixed order.
        let lanes = (0..<count).map { (CGFloat($0) + CGFloat.random(in: 0.1...0.9)) / CGFloat(count) }.shuffled()
        let margin = 22 * unit
        let textures = CelebrationTextures.emojis.shuffled()
        for index in 0..<count {
            let side = CGFloat.random(in: 30...46) * unit
            let textureSide = side * CelebrationTextures.emojiPadding
            let sprite = SKSpriteNode(texture: textures[index % textures.count], size: CGSize(width: textureSide, height: textureSide))
            sprite.zPosition = CGFloat.random(in: 0...1)
            let emoji = CelebrationParticle(
                node: sprite,
                position: CGPoint(
                    x: margin + lanes[index] * (size.width - margin * 2),
                    y: size.height + side / 2 + CGFloat.random(in: 0...60) * unit
                ),
                velocity: CGVector(dx: 0, dy: -CGFloat.random(in: 60...220) * unit),
                delay: Double.random(in: 0...0.85),
                lifetime: 4
            )
            // Gravity against the air: they fall at most about 0.87 screens per second.
            emoji.acceleration = CGVector(dx: 0, dy: -1.3 * size.height)
            emoji.drag = 1.5
            emoji.rotation = CGFloat.random(in: -0.4...0.4)
            emoji.spin = CGFloat.random(in: -1.6...1.6)
            emoji.swayAmplitude = CGFloat.random(in: 4...14) * unit
            emoji.swayRate = CGFloat.random(in: 2...3.5)
            emoji.swayPhase = CGFloat.random(in: 0...(2 * .pi))
            emoji.exitMargin = side
            add(emoji)
        }
    }
}
