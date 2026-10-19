import CoreGraphics
import Foundation

/// An RGB color (components in 0...1) that is cheap to blend every frame.
struct FireworkColor: Sendable {
    var red: Double
    var green: Double
    var blue: Double

    static let white = FireworkColor(red: 1, green: 1, blue: 1)
    static let warmWhite = FireworkColor(red: 1, green: 0.92, blue: 0.76)
    static let gold = FireworkColor(red: 1, green: 0.76, blue: 0.34)
    static let ember = FireworkColor(red: 0.95, green: 0.42, blue: 0.14)
    static let silver = FireworkColor(red: 0.88, green: 0.93, blue: 1)

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hue: Double, saturation: Double, brightness: Double) {
        let sector = (hue - hue.rounded(.down)) * 6
        let chroma = brightness * saturation
        let secondary = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let match = brightness - chroma
        let rgb: (red: Double, green: Double, blue: Double) = switch sector {
        case ..<1: (chroma, secondary, 0)
        case ..<2: (secondary, chroma, 0)
        case ..<3: (0, chroma, secondary)
        case ..<4: (0, secondary, chroma)
        case ..<5: (secondary, 0, chroma)
        default: (chroma, 0, secondary)
        }
        self.init(red: rgb.red + match, green: rgb.green + match, blue: rgb.blue + match)
    }

    func mixed(with other: FireworkColor, by fraction: Double) -> FireworkColor {
        let t = min(max(fraction, 0), 1)
        return FireworkColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t
        )
    }
}

/// The kinds of shells a show mixes, modeled after real aerial fireworks.
enum ShellKind: CaseIterable, Sendable {
    /// A full sphere of stars of a single color.
    case peony
    /// A sphere of stars with long streaks that change color as they burn.
    case chrysanthemum
    /// A tilted ring of stars around a small core of a second color.
    case ring
    /// Slow golden stars that droop and leave long, glittering trails.
    case willow
    /// A few heavy stars that each split into four smaller ones.
    case crossette
    /// A handful of thick golden fronds that shed sparks as they fall.
    case palm
    /// A silvery sphere whose stars strobe while they burn.
    case glitter
}

/// One burning star, rocket trail spark or ember.
struct Spark {
    var position: CGPoint
    var velocity: CGVector
    var lifetime: Double
    var age: Double = 0
    var color: FireworkColor
    /// Color the spark reaches at the end of its life.
    var endColor: FireworkColor
    /// Diameter in points at birth; it shrinks as the spark burns.
    var size: Double
    /// Air resistance, as the fraction of speed lost per second (exponential).
    var drag: Double
    /// Downward acceleration in points per second squared.
    var gravity: Double
    /// Seconds of travel drawn behind the spark as a motion streak.
    var streak: Double = 0
    /// Seconds the spark glows white-hot after it is born.
    var hotDuration: Double = 0.14
    /// Fraction of its life after which the spark starts to strobe.
    var flickerFrom: Double = .infinity
    var flickerRate: Double = 0
    var flickerPhase: Double = 0
    /// Age at which the spark splits into four (crossettes).
    var splitAge: Double?
    /// Tiny embers shed per second (palms).
    var emberRate: Double = 0
    var emberDebt: Double = 0
    /// Past positions, oldest first, for sparks that leave a long trail (willows, palms).
    var history: [CGPoint] = []
    var historyCapacity = 0
    var historyClock: Double = 0

    var lifeFraction: Double { min(age / lifetime, 1) }
}

/// A rocket climbing towards the point where its shell bursts.
struct Rocket {
    var kind: ShellKind
    var primary: FireworkColor
    var secondary: FireworkColor
    /// Size of the burst relative to a regular shell.
    var scale: Double
    /// Seconds on the simulation clock.
    var launchTime: Double
    var flightTime: Double
    /// Launch and burst points in unit coordinates (0...1 across the canvas).
    var start: CGPoint
    var apex: CGPoint
    var wobblePhase: Double
    var trailDebt: Double = 0

    func hasLaunched(at time: Double) -> Bool { time >= launchTime }

    func progress(at time: Double) -> Double {
        min(max((time - launchTime) / flightTime, 0), 1)
    }

    /// Position in points: fast at launch and slowing down near the apex, with a slight sway.
    func position(at time: Double, in size: CGSize) -> CGPoint {
        let progress = progress(at: time)
        let eased = 1 - pow(1 - progress, 2.6)
        let sway = sin(progress * .pi * 3 + wobblePhase) * 2.5 * (1 - progress)
        let x = Double(start.x + (apex.x - start.x) * CGFloat(eased)) * Double(size.width) + sway
        let y = Double(start.y + (apex.y - start.y) * CGFloat(eased)) * Double(size.height)
        return CGPoint(x: x, y: y)
    }
}

/// The light a burst throws for an instant.
struct BurstFlash {
    var position: CGPoint
    var radius: Double
    var color: FireworkColor
    var lifetime: Double
    var age: Double = 0
}

/// A small fireworks show, simulated as particles with gravity and air drag. Every show is planned at random
/// (shell kinds, colors, positions and timing), so no two celebrations look the same.
final class FireworksSimulation {
    private(set) var sparks: [Spark] = []
    private(set) var rockets: [Rocket] = []
    private(set) var flashes: [BurstFlash] = []
    /// How much the screen is dimmed behind the show, from 0 to 1.
    private(set) var dimming: Double = 0
    /// Seconds since the simulation started.
    private(set) var time: Double = 0
    private(set) var canvasSize: CGSize = .zero

    /// Called on the main queue when a shell bursts, with an intensity from 0 to 1 (for haptics).
    var onBurst: ((Double) -> Void)?

    private var lastDate: Date?
    private var hasReportedFinish = false
    private var lastSplitReport = -Double.infinity

    /// Longest step simulated in one frame, so a stalled frame does not make sparks jump.
    private static let maximumStep: Double = 1.0 / 20
    private static let rocketTrailInterval: Double = 1.0 / 110
    private static let historyInterval: Double = 1.0 / 30

    var isFinished: Bool {
        rockets.isEmpty && sparks.isEmpty && flashes.isEmpty && dimming == 0
    }

    // MARK: - Planning

    /// Adds a show that starts right away. `budget` scales the number of particles (lower in Low Power Mode).
    func enqueueShow(budget: Double = 1) {
        hasReportedFinish = false
        let count = budget < 1 ? Int.random(in: 2...3) : Int.random(in: 3...5)
        let palette = Self.randomPalette()

        // A big classic shell opens the show; the rest are all different from each other.
        let openers: [ShellKind] = [.peony, .chrysanthemum, .ring]
        let opener = openers.randomElement() ?? .peony
        var kinds = [opener]
        kinds += ShellKind.allCases.filter { $0 != opener }.shuffled().prefix(count - 1)

        // Spread the bursts across the width, in random order.
        let slots = (0..<count).map { (Double($0) + 0.5) / Double(count) }.shuffled()
        var launchTime = time + 0.04
        for (index, kind) in kinds.enumerated() {
            let apexX = 0.14 + 0.72 * slots[index] + Double.random(in: -0.04...0.04)
            let apexY = index == 0 ? Double.random(in: 0.2...0.3) : Double.random(in: 0.13...0.42)
            let startX = min(max(apexX + Double.random(in: -0.1...0.1), 0.06), 0.94)
            var colors = palette.shuffled()
            let primary = colors.removeFirst()
            let secondary = colors.first ?? .white
            rockets.append(Rocket(
                kind: kind,
                primary: primary,
                secondary: secondary,
                scale: (index == 0 ? Double.random(in: 1.0...1.15) : Double.random(in: 0.74...0.98)) * budget.squareRoot(),
                launchTime: launchTime,
                flightTime: (0.42 + 0.4 * (1 - apexY)) * Double.random(in: 0.92...1.08),
                start: CGPoint(x: startX, y: 1.03),
                apex: CGPoint(x: apexX, y: apexY),
                wobblePhase: Double.random(in: 0...(2 * .pi))
            ))
            // Now and then two rockets go up together.
            let together = index > 0 && Double.random(in: 0...1) < 0.25
            launchTime += together ? Double.random(in: 0.02...0.06)
                : index == 0 ? Double.random(in: 0.26...0.4) : Double.random(in: 0.12...0.34)
        }
    }

    /// Two or three hues that look good together: complementary, triadic, analogous or split.
    private static func randomPalette() -> [FireworkColor] {
        let base = Double.random(in: 0..<1)
        let schemes: [[Double]] = [[0, 0.5], [0, 1.0 / 3, 2.0 / 3], [0, 0.08, 0.92], [0, 0.12, 0.5]]
        let offsets = schemes.randomElement() ?? [0, 0.5]
        return offsets.map {
            FireworkColor(
                hue: base + $0 + Double.random(in: -0.02...0.02),
                saturation: Double.random(in: 0.6...0.9),
                brightness: 1
            )
        }
    }

    // MARK: - Simulation

    /// Moves the show forward to `date`. Called once per frame.
    func advance(to date: Date, size: CGSize) {
        canvasSize = size
        let step = lastDate.map { min(max(date.timeIntervalSince($0), 0), Self.maximumStep) } ?? 0
        lastDate = date
        guard step > 0, size.width > 0, size.height > 0 else { return }
        time += step
        advanceRockets(by: step)
        advanceSparks(by: step)
        advanceFlashes(by: step)
        advanceDimming(by: step)
    }

    /// `true` only the first time it is asked after the show finished.
    func takeFinish() -> Bool {
        guard isFinished, !hasReportedFinish else { return false }
        hasReportedFinish = true
        return true
    }

    private func advanceRockets(by step: Double) {
        var flying: [Rocket] = []
        for var rocket in rockets {
            guard rocket.hasLaunched(at: time) else {
                flying.append(rocket)
                continue
            }
            // Sizzling trail, emitted along the path covered during this frame.
            rocket.trailDebt += min(step, time - rocket.launchTime)
            while rocket.trailDebt >= Self.rocketTrailInterval {
                rocket.trailDebt -= Self.rocketTrailInterval
                let head = rocket.position(at: time - rocket.trailDebt, in: canvasSize)
                sparks.append(Spark(
                    position: CGPoint(x: head.x + CGFloat.random(in: -1...1), y: head.y + CGFloat.random(in: -1...1)),
                    velocity: CGVector(dx: CGFloat.random(in: -18...18), dy: CGFloat.random(in: 10...55)),
                    lifetime: .random(in: 0.22...0.5),
                    color: .warmWhite,
                    endColor: .ember,
                    size: .random(in: 1.1...1.8),
                    drag: 3,
                    gravity: 70,
                    hotDuration: 0.05,
                    flickerFrom: 0.35,
                    flickerRate: .random(in: 40...70),
                    flickerPhase: .random(in: 0...(2 * .pi))
                ))
            }
            if rocket.progress(at: time) >= 1 {
                burst(rocket)
            } else {
                flying.append(rocket)
            }
        }
        rockets = flying
    }

    private func advanceSparks(by step: Double) {
        var born: [Spark] = []
        var didSplit = false
        for index in sparks.indices {
            var spark = sparks[index]
            spark.age += step
            let damping = CGFloat(exp(-spark.drag * step))
            spark.velocity.dx *= damping
            spark.velocity.dy = spark.velocity.dy * damping + CGFloat(spark.gravity * step)
            spark.position.x += spark.velocity.dx * CGFloat(step)
            spark.position.y += spark.velocity.dy * CGFloat(step)

            if spark.historyCapacity > 0 {
                spark.historyClock += step
                if spark.historyClock >= Self.historyInterval {
                    spark.historyClock = 0
                    spark.history.append(spark.position)
                    if spark.history.count > spark.historyCapacity { spark.history.removeFirst() }
                }
            }

            if spark.emberRate > 0, spark.lifeFraction < 0.85 {
                spark.emberDebt += spark.emberRate * step
                while spark.emberDebt >= 1 {
                    spark.emberDebt -= 1
                    born.append(ember(at: spark.position, color: spark.color))
                }
            }

            if let splitAge = spark.splitAge, spark.age >= splitAge {
                born += split(spark)
                spark.age = spark.lifetime
                didSplit = true
            }
            sparks[index] = spark
        }
        sparks.removeAll { $0.age >= $0.lifetime }
        sparks += born
        // One soft tap per crossette, not one per star.
        if didSplit, time - lastSplitReport > 0.3 {
            lastSplitReport = time
            report(intensity: 0.35)
        }
    }

    private func advanceFlashes(by step: Double) {
        for index in flashes.indices { flashes[index].age += step }
        flashes.removeAll { $0.age >= $0.lifetime }
    }

    /// The screen dims while rockets fly or stars still burn, and brightens again as the last ones fade.
    private func advanceDimming(by step: Double) {
        let busy = !rockets.isEmpty || sparks.contains { $0.lifetime - $0.age > 0.5 && $0.size > 1.6 }
        let rate = busy ? 7.0 : 3.5
        dimming += ((busy ? 1 : 0) - dimming) * (1 - exp(-rate * step))
        if !busy, dimming < 0.004 { dimming = 0 }
    }

    // MARK: - Bursts

    private func burst(_ rocket: Rocket) {
        let center = rocket.position(at: rocket.launchTime + rocket.flightTime, in: canvasSize)
        // Bigger on larger screens, without overflowing an iPhone.
        let unit = min(max(Double(min(canvasSize.width, canvasSize.height)) / 390, 0.85), 1.6) * rocket.scale
        let count = { (base: Double) in max(Int((base * rocket.scale).rounded()), 6) }
        let primary = rocket.primary, secondary = rocket.secondary

        switch rocket.kind {
        case .peony:
            let twinkles = Bool.random()
            for direction in Self.sphere(count(110)) {
                sparks.append(star(at: center, direction: direction, speed: 230 * unit, lifetime: .random(in: 1.15...1.6),
                                   color: primary, endColor: primary.mixed(with: .white, by: 0.25), size: 3,
                                   drag: 2.1, gravity: 70, streak: 0.035, flickerFrom: twinkles ? 0.55 : .infinity))
            }
        case .chrysanthemum:
            for direction in Self.sphere(count(120)) {
                sparks.append(star(at: center, direction: direction, speed: 250 * unit, lifetime: .random(in: 1.35...1.8),
                                   color: primary, endColor: secondary, size: 2.4, drag: 2.2, gravity: 80, streak: 0.09))
            }
        case .ring:
            for direction in Self.ring(count(64)) {
                sparks.append(star(at: center, direction: direction, speed: 215 * unit, lifetime: .random(in: 1.25...1.55),
                                   color: primary, endColor: primary, size: 3, drag: 2, gravity: 65, streak: 0.03))
            }
            for direction in Self.sphere(count(18)) {
                sparks.append(star(at: center, direction: direction, speed: 70 * unit, lifetime: .random(in: 0.9...1.2),
                                   color: secondary, endColor: secondary, size: 2.1, drag: 2, gravity: 60, streak: 0.02))
            }
        case .willow:
            let gold = FireworkColor.gold.mixed(with: primary, by: 0.15)
            for direction in Self.sphere(count(90)) {
                var spark = star(at: center, direction: direction, speed: 195 * unit, lifetime: .random(in: 2.1...2.7),
                                 color: gold, endColor: .ember, size: 2.2, drag: 2.5, gravity: 95, flickerFrom: 0.6)
                spark.historyCapacity = 13
                sparks.append(spark)
            }
        case .crossette:
            let stars = count(18)
            let offset = Double.random(in: 0...(2 * .pi))
            for index in 0..<stars {
                let angle = offset + Double(index) / Double(stars) * 2 * .pi + Double.random(in: -0.08...0.08)
                var spark = star(at: center, direction: CGVector(dx: cos(angle), dy: sin(angle)), speed: 205 * unit,
                                 lifetime: 1, color: primary, endColor: primary, size: 3, drag: 1.6, gravity: 60,
                                 streak: 0.05)
                spark.splitAge = .random(in: 0.48...0.6)
                spark.historyCapacity = 6
                sparks.append(spark)
            }
        case .palm:
            let fronds = count(9)
            let offset = Double.random(in: 0...(2 * .pi))
            for index in 0..<fronds {
                let angle = offset + Double(index) / Double(fronds) * 2 * .pi + Double.random(in: -0.15...0.15)
                var spark = star(at: center, direction: CGVector(dx: cos(angle), dy: sin(angle) - 0.25),
                                 speed: 260 * unit, lifetime: .random(in: 1.5...1.9), color: .gold,
                                 endColor: .ember, size: 4.2, drag: 1.5, gravity: 135)
                spark.historyCapacity = 15
                spark.emberRate = 38
                sparks.append(spark)
            }
            for direction in Self.sphere(count(12)) {
                sparks.append(star(at: center, direction: direction, speed: 60 * unit, lifetime: .random(in: 0.8...1.1),
                                   color: secondary, endColor: secondary, size: 2.2, drag: 2, gravity: 60, streak: 0.02))
            }
        case .glitter:
            let tint = FireworkColor.silver.mixed(with: primary, by: 0.3)
            for direction in Self.sphere(count(100)) {
                sparks.append(star(at: center, direction: direction, speed: 215 * unit, lifetime: .random(in: 1.4...1.9),
                                   color: tint, endColor: .silver, size: 2.5, drag: 2.3, gravity: 80, streak: 0.03,
                                   flickerFrom: 0.18))
            }
        }

        flashes.append(BurstFlash(position: center, radius: 120 * unit, color: primary.mixed(with: .white, by: 0.5),
                                  lifetime: 0.4))
        report(intensity: min(0.45 + 0.45 * rocket.scale, 1))
    }

    private func star(
        at center: CGPoint,
        direction: CGVector,
        speed: Double,
        lifetime: Double,
        color: FireworkColor,
        endColor: FireworkColor,
        size: Double,
        drag: Double,
        gravity: Double,
        streak: Double = 0,
        flickerFrom: Double = .infinity
    ) -> Spark {
        let speed = speed * Double.random(in: 0.93...1.07)
        return Spark(
            position: center,
            velocity: CGVector(dx: direction.dx * CGFloat(speed), dy: direction.dy * CGFloat(speed)),
            lifetime: lifetime,
            color: color,
            endColor: endColor,
            size: size * Double.random(in: 0.85...1.15),
            drag: drag,
            gravity: gravity,
            streak: streak,
            flickerFrom: flickerFrom,
            flickerRate: .random(in: 35...60),
            flickerPhase: .random(in: 0...(2 * .pi))
        )
    }

    /// The four smaller stars a crossette star breaks into, in a cross turned at random.
    private func split(_ spark: Spark) -> [Spark] {
        flashes.append(BurstFlash(position: spark.position, radius: 22, color: spark.color.mixed(with: .white, by: 0.5),
                                  lifetime: 0.22))
        let heading = Double(atan2(spark.velocity.dy, spark.velocity.dx)) + .pi / 4 + Double.random(in: -0.3...0.3)
        let inherited = (dx: Double(spark.velocity.dx) * 0.35, dy: Double(spark.velocity.dy) * 0.35)
        return (0..<4).map { index in
            let angle = heading + Double(index) * .pi / 2
            let speed = 115 * Double.random(in: 0.9...1.1)
            return Spark(
                position: spark.position,
                velocity: CGVector(dx: inherited.dx + cos(angle) * speed, dy: inherited.dy + sin(angle) * speed),
                lifetime: .random(in: 0.7...1),
                color: spark.color.mixed(with: .white, by: 0.2),
                endColor: spark.color,
                size: 1.9,
                drag: 1.9,
                gravity: 70,
                streak: 0.045,
                hotDuration: 0.08,
                flickerFrom: 0.6,
                flickerRate: .random(in: 35...60),
                flickerPhase: .random(in: 0...(2 * .pi))
            )
        }
    }

    /// A tiny spark falling off a palm frond.
    private func ember(at position: CGPoint, color: FireworkColor) -> Spark {
        Spark(
            position: CGPoint(x: position.x + CGFloat.random(in: -1.5...1.5), y: position.y + CGFloat.random(in: -1.5...1.5)),
            velocity: CGVector(dx: CGFloat.random(in: -14...14), dy: CGFloat.random(in: -6...20)),
            lifetime: .random(in: 0.35...0.7),
            color: color.mixed(with: .white, by: 0.3),
            endColor: .ember,
            size: .random(in: 1...1.5),
            drag: 2.5,
            gravity: 90,
            hotDuration: 0.04,
            flickerFrom: 0.2,
            flickerRate: .random(in: 45...75),
            flickerPhase: .random(in: 0...(2 * .pi))
        )
    }

    private func report(intensity: Double) {
        guard let onBurst else { return }
        DispatchQueue.main.async { onBurst(intensity) }
    }

    // MARK: - Shapes

    /// Directions evenly spread over a sphere seen from the front, so the burst looks round and deep
    /// (stars bunch up towards the center the way a real 3D shell does). Turned at random every time.
    private static func sphere(_ count: Int) -> [CGVector] {
        let golden = Double.pi * (3 - 5.0.squareRoot())
        let tilt = Double.random(in: 0...(2 * .pi)), turn = Double.random(in: 0...(2 * .pi))
        let spin = Double.random(in: 0...(2 * .pi))
        return (0..<count).map { index in
            let z = 1 - (Double(index) + 0.5) / Double(count) * 2
            let radius = (1 - z * z).squareRoot()
            let angle = Double(index) * golden + spin
            return project(x: cos(angle) * radius, y: sin(angle) * radius, z: z, tilt: tilt, turn: turn)
        }
    }

    /// Directions around a circle tilted away from the viewer, so it shows as an ellipse.
    private static func ring(_ count: Int) -> [CGVector] {
        let tilt = Double.random(in: 0.7...1.25), turn = Double.random(in: 0...(2 * .pi))
        let offset = Double.random(in: 0...(2 * .pi))
        return (0..<count).map { index in
            let angle = offset + Double(index) / Double(count) * 2 * .pi
            return project(x: cos(angle), y: sin(angle), z: 0, tilt: tilt, turn: turn)
        }
    }

    /// Rotates a 3D direction around the x axis by `tilt` and around the view axis by `turn`, and drops depth.
    private static func project(x: Double, y: Double, z: Double, tilt: Double, turn: Double) -> CGVector {
        let tiltedY = y * cos(tilt) - z * sin(tilt)
        return CGVector(dx: x * cos(turn) - tiltedY * sin(turn), dy: x * sin(turn) + tiltedY * cos(turn))
    }
}
