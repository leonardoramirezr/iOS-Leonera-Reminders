import SpriteKit
import UIKit

/// A fountain of spinning gold coins, each with an embossed check mark and a glint, that clink as they come out.
final class CoinsScene: ParticleCelebrationScene {
    private let impact = UIImpactFeedbackGenerator(style: .rigid)

    /// How long a glint shines.
    private static let glintDuration: TimeInterval = 0.32

    override func start() {
        impact.prepare()
        let unit = self.unit
        let count = pieceCount(30, reduced: 12, minimum: 6)
        let gravity = 2.4 * size.height
        let spread: TimeInterval = reducedMotion ? 0.4 : 0.55
        for index in 0..<count {
            let delay = Double(index) * spread / Double(count) + Double.random(in: 0...0.03)
            if index % 5 == 0 {
                schedule(after: delay) { [weak self] in
                    self?.impact.impactOccurred(intensity: CGFloat.random(in: 0.45...0.7))
                }
            }
            // Thrown just hard enough to reach its own height before gravity brings it down.
            let apex = size.height * (reducedMotion ? CGFloat.random(in: 0.35...0.6) : CGFloat.random(in: 0.42...0.8))
            let launch = (2 * gravity * (apex + 20 * unit)).squareRoot()
            let diameter = CGFloat.random(in: 32...44) * unit

            let sprite = SKSpriteNode(texture: CelebrationTextures.coin, size: CGSize(width: diameter, height: diameter))
            sprite.zPosition = CGFloat.random(in: 0...1)
            let shade = SKSpriteNode(texture: CelebrationTextures.coinShade, size: sprite.size)
            shade.alpha = 0
            sprite.addChild(shade)
            let glint = SKSpriteNode(texture: CelebrationTextures.sparkle, size: CGSize(width: diameter * 0.95, height: diameter * 0.95))
            glint.blendMode = darkAppearance ? .add : .alpha
            glint.zPosition = 2
            glint.isHidden = true
            addChild(glint)

            let coin = Coin(
                node: sprite,
                position: CGPoint(x: size.width / 2 + CGFloat.random(in: -14...14) * unit, y: -20 * unit),
                velocity: CGVector(dx: CGFloat.random(in: -0.38...0.38) * size.width, dy: launch),
                delay: delay,
                lifetime: 3,
                shade: shade,
                glint: glint,
                glintTime: Double.random(in: 0.25...0.85),
                diameter: diameter
            )
            coin.acceleration = CGVector(dx: 0, dy: -gravity)
            coin.exitMargin = diameter
            coin.flipPhase = CGFloat.random(in: 0...(2 * .pi))
            coin.flipRate = CGFloat.random(in: 9...18) * (Bool.random() ? 1 : -1)
            coin.rotation = CGFloat.random(in: -0.35...0.35)
            coin.spin = CGFloat.random(in: -1.2...1.2)
            add(coin)
        }
    }

    override func render(_ particle: CelebrationParticle) {
        super.render(particle)
        guard let coin = particle as? Coin else { return }
        // Seen from the side, the coin is a thin, darker edge (both faces look the same).
        let facing = abs(cos(coin.flipPhase))
        coin.node.xScale = max(facing, 0.12) * coin.scale
        coin.shade.alpha = 0.55 * pow(1 - facing, 1.3)

        let time = coin.age - coin.glintTime
        guard time >= 0, time <= Self.glintDuration else {
            coin.glint.isHidden = true
            return
        }
        let strength = sin(.pi * CGFloat(time / Self.glintDuration))
        coin.glint.isHidden = false
        coin.glint.position = CGPoint(
            x: coin.node.position.x - coin.diameter * 0.2 * coin.node.xScale,
            y: coin.node.position.y + coin.diameter * 0.2
        )
        coin.glint.setScale(0.3 + 0.8 * strength)
        coin.glint.alpha = strength
        coin.glint.zRotation = CGFloat(time) * 4
    }

    override func didRemove(_ particle: CelebrationParticle) {
        (particle as? Coin)?.glint.removeFromParent()
    }
}

private final class Coin: CelebrationParticle {
    /// Darkens the coin while it shows its edge.
    let shade: SKSpriteNode
    /// A sparkle that shines on it once; it is a node of the scene, so it does not turn with the coin.
    let glint: SKSpriteNode
    /// Age at which the glint shines.
    let glintTime: TimeInterval
    let diameter: CGFloat

    init(
        node: SKNode,
        position: CGPoint,
        velocity: CGVector,
        delay: TimeInterval,
        lifetime: TimeInterval,
        shade: SKSpriteNode,
        glint: SKSpriteNode,
        glintTime: TimeInterval,
        diameter: CGFloat
    ) {
        self.shade = shade
        self.glint = glint
        self.glintTime = glintTime
        self.diameter = diameter
        super.init(node: node, position: position, velocity: velocity, delay: delay, lifetime: lifetime)
    }
}
