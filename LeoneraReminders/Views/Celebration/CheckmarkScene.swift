import SpriteKit
import UIKit

/// A big check mark draws itself in a green disc that pops in, with two rings and a ring of sparkles around it,
/// and fades away a moment later.
final class CheckmarkScene: ParticleCelebrationScene {
    private let impact = UIImpactFeedbackGenerator(style: .rigid)
    private var marks: [CheckMark] = []

    /// How long a check mark stays before fading.
    private static let holdTime: CGFloat = 0.95
    private static let fadeTime: CGFloat = 0.3
    /// How fast a check mark fades once a new one replaces it.
    private static let replacedFadeTime: CGFloat = 0.14

    override func start() {
        impact.prepare()
        // A new check mark replaces the one on screen, which fades quickly.
        for mark in marks where mark.fadeStart == nil && CGFloat(mark.age) < Self.holdTime {
            mark.fadeStart = CGFloat(mark.age)
        }

        let unit = self.unit
        let radius = CelebrationTextures.discRadius * 1.16 * unit
        let side = CelebrationTextures.discSide * radius / CelebrationTextures.discRadius
        let center = CGPoint(x: size.width / 2, y: size.height * 0.55)

        let disc = SKSpriteNode(texture: CelebrationTextures.disc, size: CGSize(width: side, height: side))
        disc.position = center
        disc.zPosition = 5
        disc.alpha = 0
        let check = SKShapeNode()
        check.strokeColor = .white
        check.fillColor = .clear
        check.lineWidth = radius * 0.17
        check.lineCap = .round
        check.lineJoin = .round
        check.isAntialiased = true
        disc.addChild(check)
        addChild(disc)

        let ringColor = darkAppearance ? CelebrationPalette.checkRingDark : CelebrationPalette.checkRing
        let rings = (0..<2).map { _ -> SKShapeNode in
            let ring = SKShapeNode(circleOfRadius: radius)
            ring.strokeColor = ringColor
            ring.fillColor = .clear
            ring.isAntialiased = true
            ring.position = center
            ring.zPosition = 4
            ring.isHidden = true
            addChild(ring)
            return ring
        }
        marks.append(CheckMark(disc: disc, check: check, rings: rings, radius: radius))
    }

    override func advance(dt: CGFloat) {
        for mark in marks {
            mark.age += Double(dt)
            animate(mark)
        }
        for mark in marks where mark.isDone {
            mark.disc.removeFromParent()
            for ring in mark.rings {
                ring.removeFromParent()
            }
        }
        marks.removeAll { $0.isDone }
    }

    override var isPlaying: Bool {
        !marks.isEmpty
    }

    private func animate(_ mark: CheckMark) {
        let time = CGFloat(mark.age)

        // The disc pops in with a little spring.
        var scale: CGFloat = 1
        var opacity = min(1, time / (reducedMotion ? 0.18 : 0.08))
        if !reducedMotion {
            if time < 0.2 {
                scale = Easing.mix(0.3, 1.12, Easing.outCubic(time / 0.2))
            } else if time < 0.32 {
                scale = Easing.mix(1.12, 0.96, Easing.inOutSine((time - 0.2) / 0.12))
            } else if time < 0.44 {
                scale = Easing.mix(0.96, 1, Easing.inOutSine((time - 0.32) / 0.12))
            }
        }

        // The check mark draws itself.
        let progress = Easing.inOutCubic(Easing.clamp((time - 0.1) / 0.28))
        if progress > 0, progress != mark.progress {
            mark.progress = progress
            mark.check.path = Self.checkPath(radius: mark.radius, progress: progress)
            if progress >= 1 {
                impact.impactOccurred(intensity: 0.8)
            }
        }

        // Rings spread out and sparkles fly off once it is drawn.
        if !reducedMotion {
            updateRing(mark.rings[0], time: time, start: 0.2, duration: 0.55, growth: 1.3, opacity: 0.6, width: 5)
            updateRing(mark.rings[1], time: time, start: 0.3, duration: 0.5, growth: 0.8, opacity: 0.45, width: 3)
            if !mark.didSparkle, time >= 0.36 {
                mark.didSparkle = true
                sparkle(around: mark)
            }
        }

        // It fades after a moment, or quickly once a new one replaces it.
        let fadeStart = mark.fadeStart ?? Self.holdTime
        let fadeTime = mark.fadeStart == nil ? Self.fadeTime : Self.replacedFadeTime
        if time > fadeStart {
            let fading = Easing.clamp((time - fadeStart) / fadeTime)
            opacity *= 1 - Easing.inCubic(fading)
            scale *= 1 - 0.12 * fading
            if fading >= 1 { mark.isDone = true }
        }
        mark.disc.setScale(scale)
        mark.disc.alpha = opacity
    }

    private func updateRing(_ ring: SKShapeNode, time: CGFloat, start: CGFloat, duration: CGFloat, growth: CGFloat, opacity: CGFloat, width: CGFloat) {
        let progress = (time - start) / duration
        guard progress >= 0, progress <= 1 else {
            ring.isHidden = true
            return
        }
        ring.isHidden = false
        let scale = 1 + growth * Easing.outCubic(progress)
        ring.setScale(scale)
        // The line is scaled with the ring, so it is set thinner to look the width wanted.
        ring.lineWidth = width * unit * (1 - 0.7 * progress) / scale
        ring.alpha = opacity * (1 - progress)
    }

    private func sparkle(around mark: CheckMark) {
        let unit = self.unit
        let center = mark.disc.position
        let count = 14
        for index in 0..<count {
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi + CGFloat.random(in: -0.15...0.15)
            let distance = CGFloat.random(in: 45...95) * unit
            let drag: CGFloat = 5
            let side = CGFloat.random(in: 12...20) * unit
            let sprite = SKSpriteNode(texture: CelebrationTextures.sparkle, size: CGSize(width: side, height: side))
            sprite.color = CelebrationPalette.sparkles.randomElement() ?? CelebrationPalette.checkRing
            sprite.colorBlendFactor = 1
            sprite.zPosition = 6
            let start = CGPoint(x: center.x + cos(angle) * mark.radius * 1.02, y: center.y + sin(angle) * mark.radius * 1.02)
            let speck = CelebrationParticle(
                node: sprite,
                position: start,
                velocity: CGVector(dx: cos(angle) * distance * drag, dy: sin(angle) * distance * drag),
                lifetime: Double.random(in: 0.45...0.7)
            )
            speck.drag = drag
            speck.fadeOut = 0.3
            speck.spin = CGFloat.random(in: -3...3)
            add(speck)
        }
    }

    /// The check mark drawn up to `progress` (0 to 1) of its length, around the middle of a disc of `radius`.
    private static func checkPath(radius: CGFloat, progress: CGFloat) -> CGPath {
        let points = [CGPoint(x: -0.4, y: 0.02), CGPoint(x: -0.12, y: -0.27), CGPoint(x: 0.42, y: 0.3)]
            .map { CGPoint(x: $0.x * radius, y: $0.y * radius) }
        let first = hypot(points[1].x - points[0].x, points[1].y - points[0].y)
        let second = hypot(points[2].x - points[1].x, points[2].y - points[1].y)
        let length = (first + second) * progress
        let path = CGMutablePath()
        path.move(to: points[0])
        if length <= first {
            path.addLine(to: point(from: points[0], to: points[1], fraction: length / first))
        } else {
            path.addLine(to: points[1])
            path.addLine(to: point(from: points[1], to: points[2], fraction: (length - first) / second))
        }
        return path
    }

    private static func point(from start: CGPoint, to end: CGPoint, fraction: CGFloat) -> CGPoint {
        CGPoint(x: Easing.mix(start.x, end.x, fraction), y: Easing.mix(start.y, end.y, fraction))
    }
}

/// One check mark on screen.
private final class CheckMark {
    let disc: SKSpriteNode
    let check: SKShapeNode
    let rings: [SKShapeNode]
    let radius: CGFloat
    var age: TimeInterval = 0
    /// How much of the check mark is drawn.
    var progress: CGFloat = 0
    var didSparkle = false
    /// Age at which it started fading because a new one replaced it.
    var fadeStart: CGFloat?
    var isDone = false

    init(disc: SKSpriteNode, check: SKShapeNode, rings: [SKShapeNode], radius: CGFloat) {
        self.disc = disc
        self.check = check
        self.rings = rings
        self.radius = radius
    }
}
