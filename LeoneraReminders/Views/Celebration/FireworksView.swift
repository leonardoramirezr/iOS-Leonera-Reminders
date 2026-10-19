import SwiftUI

/// Draws a `FireworksSimulation` frame by frame. It never takes touches.
struct FireworksView: View {
    let simulation: FireworksSimulation
    /// Called once, on the main queue, when the show is over.
    let onFinished: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(simulation: FireworksSimulation, onFinished: @escaping () -> Void) {
        self.simulation = simulation
        self.onFinished = onFinished
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                simulation.advance(to: timeline.date, size: size)
                FireworksRenderer(simulation: simulation, isDark: colorScheme == .dark).draw(in: &context, size: size)
                if simulation.takeFinish() {
                    DispatchQueue.main.async { onFinished() }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FireworksRenderer {
    let simulation: FireworksSimulation
    let isDark: Bool

    /// Night-blue dimming at the top and bottom of the screen at its strongest. It is stronger in light mode,
    /// so the sparks still stand out over a white list.
    private var dimming: (top: Double, bottom: Double) {
        isDark ? (0.55, 0.25) : (0.8, 0.45)
    }

    private static let night = FireworkColor(red: 0.02, green: 0.03, blue: 0.1)

    func draw(in context: inout GraphicsContext, size: CGSize) {
        if simulation.dimming > 0 {
            let strength = simulation.dimming * simulation.dimming * (3 - 2 * simulation.dimming)
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: [
                        Self.night.color(opacity: dimming.top * strength),
                        Self.night.color(opacity: dimming.bottom * strength),
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
        }

        // Light adds up where sparks overlap, the way real fireworks glow.
        context.blendMode = .plusLighter

        for flash in simulation.flashes { draw(flash, in: &context) }
        for spark in simulation.sparks { draw(spark, in: &context) }
        for rocket in simulation.rockets where rocket.hasLaunched(at: simulation.time) {
            draw(rocket, in: &context, size: size)
        }
    }

    private func draw(_ flash: BurstFlash, in context: inout GraphicsContext) {
        let progress = flash.age / flash.lifetime
        let fade = (1 - progress) * (1 - progress)
        let radius = flash.radius * (0.6 + 0.4 * progress)
        context.fill(
            circle(at: flash.position, radius: radius),
            with: .radialGradient(
                Gradient(colors: [flash.color.color(opacity: 0.45 * fade), flash.color.color(opacity: 0)]),
                center: flash.position,
                startRadius: 0,
                endRadius: CGFloat(radius)
            )
        )
    }

    private func draw(_ spark: Spark, in context: inout GraphicsContext) {
        let life = spark.lifeFraction
        // Full brightness for most of its life, then a smooth fade.
        var alpha = life < 0.55 ? 1 : 1 - pow((life - 0.55) / 0.45, 2)
        if life > spark.flickerFrom, sin(spark.age * spark.flickerRate + spark.flickerPhase) < -0.15 {
            alpha *= 0.12
        }
        guard alpha > 0.01 else { return }

        let burning = spark.color.mixed(with: spark.endColor, by: life)
        let color = spark.age < spark.hotDuration
            ? FireworkColor.white.mixed(with: burning, by: spark.age / spark.hotDuration)
            : burning
        let radius = spark.size * (1 - 0.45 * life) / 2
        let position = spark.position

        if !spark.history.isEmpty {
            // Long trail: the newer half brighter than the older half.
            let points = spark.history + [position]
            let middle = points.count / 2
            var older = Path(), newer = Path()
            older.addLines(Array(points[...middle]))
            newer.addLines(Array(points[middle...]))
            context.stroke(older, with: .color(color.color(opacity: alpha * 0.18)),
                           style: StrokeStyle(lineWidth: CGFloat(radius * 1.1), lineCap: .round, lineJoin: .round))
            context.stroke(newer, with: .color(color.color(opacity: alpha * 0.42)),
                           style: StrokeStyle(lineWidth: CGFloat(radius * 1.6), lineCap: .round, lineJoin: .round))
        }

        if spark.streak > 0 {
            // Motion streak, tapered in two steps. It shortens by itself as drag slows the spark down.
            let length = CGFloat(spark.streak)
            let middle = CGPoint(x: position.x - spark.velocity.dx * length * 0.5,
                                 y: position.y - spark.velocity.dy * length * 0.5)
            let tail = CGPoint(x: position.x - spark.velocity.dx * length,
                               y: position.y - spark.velocity.dy * length)
            var near = Path(), far = Path()
            near.move(to: position)
            near.addLine(to: middle)
            far.move(to: middle)
            far.addLine(to: tail)
            context.stroke(far, with: .color(color.color(opacity: alpha * 0.22)),
                           style: StrokeStyle(lineWidth: CGFloat(radius * 1.1), lineCap: .round))
            context.stroke(near, with: .color(color.color(opacity: alpha * 0.55)),
                           style: StrokeStyle(lineWidth: CGFloat(radius * 1.7), lineCap: .round))
        }

        // Soft glow around stars (not around tiny embers), brighter right after the burst.
        if spark.size > 1.6 {
            let glow = 0.1 + (life < 0.3 ? 0.18 * (1 - life / 0.3) : 0)
            context.fill(circle(at: position, radius: radius * 3.4), with: .color(color.color(opacity: alpha * glow)))
        }

        context.fill(circle(at: position, radius: radius), with: .color(color.color(opacity: alpha)))
    }

    private func draw(_ rocket: Rocket, in context: inout GraphicsContext, size: CGSize) {
        let head = rocket.position(at: simulation.time, in: size)
        let behind = rocket.position(at: max(simulation.time - 0.05, rocket.launchTime), in: size)

        var streak = Path()
        streak.move(to: head)
        streak.addLine(to: behind)
        context.stroke(streak, with: .color(FireworkColor.warmWhite.color(opacity: 0.6)),
                       style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

        context.fill(
            circle(at: head, radius: 7),
            with: .radialGradient(
                Gradient(colors: [FireworkColor.warmWhite.color(opacity: 0.55), FireworkColor.warmWhite.color(opacity: 0)]),
                center: head,
                startRadius: 0,
                endRadius: 7
            )
        )
        context.fill(circle(at: head, radius: 1.8), with: .color(.white))
    }

    private func circle(at center: CGPoint, radius: Double) -> Path {
        let radius = CGFloat(radius)
        return Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}

private extension FireworkColor {
    func color(opacity: Double) -> Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}
