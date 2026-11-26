import SpriteKit
import UIKit

/// A band of colored light runs around the edges of the screen and fades, leaving the app itself untouched.
final class GlowScene: ParticleCelebrationScene {
    private let impact = UIImpactFeedbackGenerator(style: .soft)
    private var waves: [GlowWave] = []

    /// Soft lights along the edges; they overlap into one continuous band.
    private static let lightCount = 30

    override func start() {
        impact.prepare()
        impact.impactOccurred(intensity: 0.6)
        let unit = self.unit
        let offset = CGFloat.random(in: 0..<1)
        var lights: [GlowLight] = []
        for index in 0..<Self.lightCount {
            let fraction = CGFloat(index) / CGFloat(Self.lightCount)
            let sprite = SKSpriteNode(texture: CelebrationTextures.glow)
            sprite.color = CelebrationPalette.glowColor(at: fraction)
            sprite.colorBlendFactor = 1
            // Light adds up over the dark appearance; over the light one it is laid on top.
            sprite.blendMode = darkAppearance ? .add : .alpha
            sprite.zPosition = CGFloat.random(in: 0...1)
            sprite.alpha = 0
            addChild(sprite)
            lights.append(GlowLight(
                sprite: sprite,
                start: offset + fraction + CGFloat.random(in: -0.008...0.008),
                // Fractions of the way around per second; with Reduce Motion the lights stay in place.
                speed: reducedMotion ? 0 : CGFloat.random(in: 0.17...0.22),
                radius: CGFloat.random(in: 44...66) * unit,
                breathRate: CGFloat.random(in: 2...3.5),
                breathPhase: CGFloat.random(in: 0...(2 * .pi))
            ))
        }
        waves.append(GlowWave(lights: lights, opacity: darkAppearance ? 0.6 : 0.5))
    }

    override func advance(dt: CGFloat) {
        let cornerRadius = min(max(min(size.width, size.height) * 0.12, 38), 64)
        for wave in waves {
            wave.age += dt
            let time = wave.age
            let envelope: CGFloat
            if time < 0.3 {
                envelope = Easing.outCubic(time / 0.3)
            } else if time < 1.1 {
                envelope = 1
            } else {
                envelope = 1 - Easing.inOutSine(Easing.clamp((time - 1.1) / 0.8))
            }
            // A brief swell right after it appears.
            let swell = 1 + 0.3 * exp(-pow((time - 0.28) / 0.14, 2))
            for light in wave.lights {
                let radius = light.radius * (1 + 0.12 * sin(light.breathRate * time + light.breathPhase)) * swell
                let edge = Self.edgePoint(of: size, cornerRadius: cornerRadius, fraction: light.start + light.speed * time)
                // Mostly off screen, so only its inner side lights the edge; stretched along it.
                light.sprite.position = CGPoint(x: edge.position.x + edge.normal.dx * radius * 0.3, y: edge.position.y + edge.normal.dy * radius * 0.3)
                light.sprite.size = CGSize(width: radius * 4.8, height: radius * 2)
                light.sprite.zRotation = atan2(edge.normal.dy, edge.normal.dx) + .pi / 2
                light.sprite.alpha = envelope * wave.opacity
            }
            if time >= 1.9 {
                wave.isDone = true
            }
        }
        for wave in waves where wave.isDone {
            for light in wave.lights {
                light.sprite.removeFromParent()
            }
        }
        waves.removeAll { $0.isDone }
    }

    override var isPlaying: Bool {
        !waves.isEmpty
    }

    /// The point `fraction` of the way around the screen's rounded rectangle, clockwise from the middle of the top
    /// edge, and the direction out of the screen there.
    private static func edgePoint(of size: CGSize, cornerRadius radius: CGFloat, fraction: CGFloat) -> (position: CGPoint, normal: CGVector) {
        let width = size.width
        let height = size.height
        let horizontal = max(width - 2 * radius, 0)
        let vertical = max(height - 2 * radius, 0)
        let arc = CGFloat.pi * radius / 2
        let perimeter = 2 * horizontal + 2 * vertical + 4 * arc
        var distance = (fraction - fraction.rounded(.down)) * perimeter

        // The right half of the top edge.
        if distance <= horizontal / 2 { return (CGPoint(x: width / 2 + distance, y: height), CGVector(dx: 0, dy: 1)) }
        distance -= horizontal / 2
        // The top right corner.
        if distance <= arc { return corner(center: CGPoint(x: width - radius, y: height - radius), from: .pi / 2, distance: distance, radius: radius) }
        distance -= arc
        // The right edge, down.
        if distance <= vertical { return (CGPoint(x: width, y: height - radius - distance), CGVector(dx: 1, dy: 0)) }
        distance -= vertical
        // The bottom right corner.
        if distance <= arc { return corner(center: CGPoint(x: width - radius, y: radius), from: 0, distance: distance, radius: radius) }
        distance -= arc
        // The bottom edge, to the left.
        if distance <= horizontal { return (CGPoint(x: width - radius - distance, y: 0), CGVector(dx: 0, dy: -1)) }
        distance -= horizontal
        // The bottom left corner.
        if distance <= arc { return corner(center: CGPoint(x: radius, y: radius), from: -.pi / 2, distance: distance, radius: radius) }
        distance -= arc
        // The left edge, up.
        if distance <= vertical { return (CGPoint(x: 0, y: radius + distance), CGVector(dx: -1, dy: 0)) }
        distance -= vertical
        // The top left corner.
        if distance <= arc { return corner(center: CGPoint(x: radius, y: height - radius), from: .pi, distance: distance, radius: radius) }
        distance -= arc
        // The left half of the top edge, back to the middle.
        return (CGPoint(x: radius + distance, y: height), CGVector(dx: 0, dy: 1))
    }

    /// The point `distance` along a corner's arc, clockwise from the angle `start`.
    private static func corner(center: CGPoint, from start: CGFloat, distance: CGFloat, radius: CGFloat) -> (position: CGPoint, normal: CGVector) {
        let angle = start - distance / radius
        let normal = CGVector(dx: cos(angle), dy: sin(angle))
        return (CGPoint(x: center.x + normal.dx * radius, y: center.y + normal.dy * radius), normal)
    }
}

/// One run of the light around the edges.
private final class GlowWave {
    let lights: [GlowLight]
    /// Opacity of each light at its brightest.
    let opacity: CGFloat
    var age: CGFloat = 0
    var isDone = false

    init(lights: [GlowLight], opacity: CGFloat) {
        self.lights = lights
        self.opacity = opacity
    }
}

private struct GlowLight {
    let sprite: SKSpriteNode
    /// Where it starts, as a fraction of the way around the screen.
    let start: CGFloat
    let speed: CGFloat
    let radius: CGFloat
    let breathRate: CGFloat
    let breathPhase: CGFloat
}
