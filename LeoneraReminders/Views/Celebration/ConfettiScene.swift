import SpriteKit
import UIKit

/// Two cannons at the bottom corners shoot a burst of confetti that flutters as it falls.
final class ConfettiScene: ParticleCelebrationScene {
    private let impact = UIImpactFeedbackGenerator(style: .medium)

    private static let shadeCount = 6
    /// Each palette color in a few shades, from its edge (the darkest) to its face, so the pieces turn without
    /// new colors being made while they play.
    private static let shades: [[UIColor]] = CelebrationPalette.confetti.map { color in
        let count = ConfettiScene.shadeCount
        return (0..<count).map { level in
            color.darkened(0.42 * (1 - CGFloat(level) / CGFloat(count - 1)))
        }
    }

    override func start() {
        impact.prepare()
        let perCannon = pieceCount(90, reduced: 30, minimum: 10)
        let speedScale: CGFloat = reducedMotion ? 0.85 : 1
        // The left cannon fires a moment before the right one.
        for side in [CGFloat(-1), 1] {
            let fireTime: TimeInterval = side < 0 ? 0 : 0.08
            schedule(after: fireTime) { [weak self] in
                self?.impact.impactOccurred(intensity: side < 0 ? 0.9 : 0.75)
            }
            for _ in 0..<perCannon {
                fire(from: side, at: fireTime, speedScale: speedScale)
            }
        }
    }

    /// One piece from the left (`side` -1) or the right (`side` 1) cannon.
    private func fire(from side: CGFloat, at fireTime: TimeInterval, speedScale: CGFloat) {
        let unit = self.unit
        let angle = CGFloat.random(in: 48...82) * .pi / 180
        let launchSpeed = size.height * CGFloat.random(in: 1.6...3.3) * speedScale
        let velocity = CGVector(dx: cos(angle) * launchSpeed * -side, dy: sin(angle) * launchSpeed)

        let shape = ConfettiShape.random()
        let sprite = SKSpriteNode(texture: shape.texture)
        sprite.size = CGSize(
            width: shape.size.width * unit * CGFloat.random(in: 0.85...1.2),
            height: shape.size.height * unit * CGFloat.random(in: 0.85...1.2)
        )
        sprite.colorBlendFactor = 1
        sprite.zPosition = CGFloat.random(in: 0...1)

        let x = side < 0 ? CGFloat.random(in: -10...6) * unit : size.width + CGFloat.random(in: -6...10) * unit
        let start = CGPoint(x: x, y: CGFloat.random(in: -12...0) * unit)
        let piece = ConfettiPiece(
            node: sprite,
            position: start,
            velocity: velocity,
            delay: fireTime + Double.random(in: 0...0.12),
            lifetime: Double.random(in: 2.5...3.5),
            colorIndex: Int.random(in: 0..<CelebrationPalette.confetti.count)
        )
        // Strong air drag: the burst slows down quickly and the pieces then float down slowly.
        piece.drag = 3
        piece.acceleration = CGVector(dx: 0, dy: -0.55 * size.height)
        piece.fadeOut = 0.7
        piece.rotation = CGFloat.random(in: 0...(2 * .pi))
        piece.spin = CGFloat.random(in: -4...4)
        if shape != .circle {
            piece.flipPhase = CGFloat.random(in: 0...(2 * .pi))
            piece.flipRate = CGFloat.random(in: 6...15) * (Bool.random() ? 1 : -1)
        }
        piece.swayAmplitude = CGFloat.random(in: 5...16) * unit
        piece.swayRate = CGFloat.random(in: 2.5...5)
        piece.swayPhase = CGFloat.random(in: 0...(2 * .pi))
        add(piece)
    }

    override func render(_ particle: CelebrationParticle) {
        super.render(particle)
        guard let piece = particle as? ConfettiPiece, let sprite = piece.node as? SKSpriteNode else { return }
        // Darker while it shows its edge, and a little darker on its back.
        let turn = piece.flipRate == 0 ? 1 : cos(piece.flipPhase)
        let light = turn < 0 ? -turn * 0.8 : turn
        let level = Int((light * CGFloat(Self.shadeCount - 1)).rounded())
        sprite.color = Self.shades[piece.colorIndex][min(max(level, 0), Self.shadeCount - 1)]
    }
}

private final class ConfettiPiece: CelebrationParticle {
    let colorIndex: Int

    init(node: SKNode, position: CGPoint, velocity: CGVector, delay: TimeInterval, lifetime: TimeInterval, colorIndex: Int) {
        self.colorIndex = colorIndex
        super.init(node: node, position: position, velocity: velocity, delay: delay, lifetime: lifetime)
    }
}

private enum ConfettiShape {
    case rectangle
    case strip
    case circle
    case squiggle

    static func random() -> ConfettiShape {
        let roll = Double.random(in: 0..<1)
        if roll < 0.58 { return .rectangle }
        if roll < 0.74 { return .strip }
        if roll < 0.9 { return .circle }
        return .squiggle
    }

    /// Size in design units.
    var size: CGSize {
        switch self {
        case .rectangle: CGSize(width: 10, height: 6)
        case .strip: CGSize(width: 14, height: 4.5)
        case .circle: CGSize(width: 7.5, height: 7.5)
        case .squiggle: CGSize(width: 16, height: 6.5)
        }
    }

    var texture: SKTexture {
        switch self {
        case .rectangle, .strip: CelebrationTextures.confettiRectangle
        case .circle: CelebrationTextures.confettiCircle
        case .squiggle: CelebrationTextures.confettiSquiggle
        }
    }
}
