import SpriteKit
import UIKit

/// A short fireworks show drawn entirely in code: every rocket, star and ember is simulated frame by frame
/// with random positions, colors, sizes, shapes and timing, so no two celebrations look the same.
///
/// The scene has a transparent background; it only darkens the screen with a soft night sky while the show
/// is on, so the colors also stand out over the light appearance.
final class FireworksScene: SKScene {
    /// Called once the last star has faded and the sky has cleared.
    var onFinished: (() -> Void)?

    private var stars: [Star] = []
    private var rockets: [Rocket] = []
    /// Stars created while `stars` is being iterated (embers, crossette splits, crackles).
    private var spawned: [Star] = []
    private var dotPool: [SKSpriteNode] = []
    private var tailPool: [SKSpriteNode] = []
    private let sky = SKSpriteNode(texture: FireworkTextures.sky)
    private let impact = UIImpactFeedbackGenerator(style: .soft)

    private var scheduledLaunches = 0
    private var lastUpdateTime: TimeInterval?
    private var isFinishing = false
    /// Set by `skip()`: the stars still in the air burn out faster instead of playing their full course.
    private var isSkipping = false
    /// Scales the number of stars per shell (fewer in Low Power Mode).
    private var density: CGFloat = 1
    private var lastStyle: ShellStyle?

    /// Above this many live stars, embers are skipped so a pile of celebrations never drops frames.
    private static let starBudget = 2600
    /// How much faster the remaining stars run once the show is skipped.
    private static let skipSpeed: TimeInterval = 4
    private static let skyColor = UIColor(red: 0.02, green: 0.03, blue: 0.10, alpha: 1)

    /// Points per design unit: sizes and speeds are tuned for a 390 pt wide iPhone and scale from there.
    private var unit: CGFloat {
        min(max(min(size.width, size.height) / 390, 0.8), 1.6)
    }

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        anchorPoint = .zero

        sky.anchorPoint = .zero
        sky.size = size
        sky.color = Self.skyColor
        sky.colorBlendFactor = 1
        sky.alpha = 0
        sky.zPosition = -1
        addChild(sky)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        sky.size = size
    }

    // MARK: - Choreography

    /// Adds a new show. Calling it while another one is playing layers the new rockets over it.
    func celebrate(reducedMotion: Bool, darkAppearance: Bool) {
        density = ProcessInfo.processInfo.isLowPowerModeEnabled ? 0.6 : 1
        isFinishing = false
        isSkipping = false
        sky.removeAction(forKey: "sky")
        sky.run(.fadeAlpha(to: darkAppearance ? 0.42 : 0.58, duration: 0.35), withKey: "sky")
        impact.prepare()

        let count = reducedMotion ? 2 : Int.random(in: 5...7)
        let finaleCount = reducedMotion ? 0 : 2
        // One lane per shell, shuffled, so the rockets spread over the whole width without a fixed order.
        let lanes = (0..<count)
            .map { (CGFloat($0) + .random(in: 0.2...0.8)) / CGFloat(count) }
            .shuffled()
        var delay: TimeInterval = 0
        for index in 0..<count {
            let isFinale = index >= count - finaleCount
            let isLast = index == count - 1
            let style = nextStyle(isLast: isLast && !reducedMotion)
            // The first rocket climbs faster so the celebration answers the gesture right away.
            let flightTime = index == 0 ? Double.random(in: 0.5...0.6) : .random(in: 0.7...0.95)
            let lane = lanes[index]
            let heightFraction = CGFloat.random(in: isFinale ? 0.62...0.8 : 0.55...0.78)
            schedule(after: delay) { [weak self] in
                self?.launch(style: style, lane: lane, heightFraction: heightFraction, flightTime: flightTime, isFinale: isFinale)
            }
            // The finale goes off almost at once; the rest keep a loose, uneven rhythm.
            delay += isFinale ? .random(in: 0.06...0.18) : .random(in: 0.3...0.52)
        }
    }

    /// Ends the show early: the launches still waiting are cancelled, the rockets in the air disappear, and the
    /// stars already out burn out faster. The sky then fades as usual.
    func skip() {
        guard !isSkipping else { return }
        isSkipping = true
        removeAllActions()
        scheduledLaunches = 0
        for rocket in rockets {
            recycle(dot: rocket.head)
        }
        rockets.removeAll()
    }

    private func nextStyle(isLast: Bool) -> ShellStyle {
        let candidates: [(ShellStyle, Double)] = isLast
            ? [(.chrysanthemum, 1), (.willow, 1)]
            : [(.peony, 3), (.chrysanthemum, 2), (.ring, 2), (.willow, 1.4), (.crossette, 1.6)]
        // Never the same shape twice in a row.
        let pool = candidates.filter { $0.0 != lastStyle }
        let totalWeight = pool.reduce(0.0) { $0 + $1.1 }
        var roll = Double.random(in: 0..<totalWeight)
        var style = pool[0].0
        for (candidate, weight) in pool {
            if roll < weight {
                style = candidate
                break
            }
            roll -= weight
        }
        lastStyle = style
        return style
    }

    private func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) {
        scheduledLaunches += 1
        run(.sequence([
            .wait(forDuration: delay),
            .run { [weak self] in
                self?.scheduledLaunches -= 1
                block()
            },
        ]))
    }

    private func launch(style: ShellStyle, lane: CGFloat, heightFraction: CGFloat, flightTime: TimeInterval, isFinale: Bool) {
        let shell = Shell.random(style: style, unit: unit, isFinale: isFinale, maxRadius: size.width * 0.4)
        let margin = min(size.width * 0.12, 60 * unit)
        let apex = CGPoint(
            x: margin + lane * (size.width - margin * 2),
            y: min(size.height * heightFraction, size.height - shell.radius * 0.75)
        )
        let start = CGPoint(x: apex.x + .random(in: -40...40) * unit, y: -12)
        let height = apex.y - start.y
        let duration = CGFloat(flightTime)
        // Constant deceleration that reaches the apex exactly at `flightTime`.
        let gravity = 2 * height / (duration * duration)

        let head = makeDot()
        head.size = CGSize(width: 9 * unit, height: 9 * unit)
        head.color = FireworkPalette.ember
        head.colorBlendFactor = 0.45
        head.position = start
        head.alpha = 1
        head.setScale(1)
        rockets.append(Rocket(
            head: head,
            position: start,
            velocity: CGVector(dx: (apex.x - start.x) / duration, dy: 2 * height / duration),
            gravity: gravity,
            flightTime: flightTime,
            shell: shell
        ))
    }

    // MARK: - Simulation

    override func update(_ currentTime: TimeInterval) {
        // Clamped so a hitch (or coming back from the background) never makes the stars jump.
        let elapsed = min(max(currentTime - (lastUpdateTime ?? currentTime), 0), 1.0 / 30)
        let dt = isSkipping ? elapsed * Self.skipSpeed : elapsed
        lastUpdateTime = currentTime
        if dt > 0 {
            updateRockets(dt: CGFloat(dt))
            updateStars(dt: CGFloat(dt))
            if !spawned.isEmpty {
                stars.append(contentsOf: spawned)
                spawned.removeAll(keepingCapacity: true)
            }
        }
        finishIfIdle()
    }

    private func updateRockets(dt: CGFloat) {
        var index = 0
        while index < rockets.count {
            let rocket = rockets[index]
            rocket.age += Double(dt)
            let previous = rocket.position
            rocket.velocity.dy -= rocket.gravity * dt
            rocket.position.x += rocket.velocity.dx * dt
            rocket.position.y += rocket.velocity.dy * dt
            let wobble = sin(CGFloat(rocket.age) * rocket.wobbleRate + rocket.wobblePhase) * 1.3 * unit
            rocket.head.position = CGPoint(x: rocket.position.x + wobble, y: rocket.position.y)
            rocket.head.alpha = .random(in: 0.7...1)
            emitRocketEmbers(rocket, from: previous, dt: dt)

            if rocket.age >= rocket.flightTime {
                explode(rocket.shell, at: rocket.position, drift: rocket.velocity)
                recycle(dot: rocket.head)
                rockets.swapAt(index, rockets.count - 1)
                rockets.removeLast()
            } else {
                index += 1
            }
        }
    }

    /// Sparks spread along the whole segment the rocket covered this frame, so the trail stays continuous
    /// however fast it climbs.
    private func emitRocketEmbers(_ rocket: Rocket, from previous: CGPoint, dt: CGFloat) {
        rocket.emberDebt += 150 * dt
        let count = Int(rocket.emberDebt)
        guard count > 0 else { return }
        rocket.emberDebt -= CGFloat(count)
        for _ in 0..<count {
            let t = CGFloat.random(in: 0...1)
            let point = CGPoint(
                x: previous.x + (rocket.position.x - previous.x) * t + .random(in: -1...1) * unit,
                y: previous.y + (rocket.position.y - previous.y) * t
            )
            let velocity = CGVector(dx: .random(in: -22...22) * unit, dy: .random(in: -70...(-10)) * unit)
            spawnStar(at: point, velocity: velocity, recipe: .rocketEmber, color: FireworkPalette.ember, brightness: .random(in: 0.55...0.9))
        }
    }

    private func updateStars(dt: CGFloat) {
        let unit = self.unit
        var index = 0
        while index < stars.count {
            let star = stars[index]
            star.age += Double(dt)
            let t = CGFloat(star.age / star.lifetime)

            if let splitAt = star.splitAt, star.age >= splitAt {
                split(star)
                retire(at: index)
                continue
            }
            if t >= 1 {
                if star.crackles, Bool.random() { crackle(at: star.position) }
                retire(at: index)
                continue
            }

            // Drag first, then gravity: the burst slows down evenly and only then droops.
            let damping = exp(-star.drag * dt)
            star.velocity.dx *= damping
            star.velocity.dy = star.velocity.dy * damping - star.gravity * dt
            star.position.x += star.velocity.dx * dt
            star.position.y += star.velocity.dy * dt

            var alpha: CGFloat = t < 0.6 ? 1 : pow(max(0, (1 - t) / 0.4), 1.4)
            alpha *= star.brightness * .random(in: 0.86...1)
            var blend: CGFloat = star.whiteHot ? min(1, 0.2 + t * 5) : 1
            let isStrobing = t > star.strobeFrom
            if isStrobing {
                // Glitter: the star blinks white before going out.
                let on = sin(CGFloat(star.age) * star.strobeRate + star.strobePhase) > 0.1
                alpha *= on ? 1.1 : 0.08
                blend = 0.3
            }

            let head = star.head
            head.position = star.position
            head.alpha = alpha
            head.colorBlendFactor = blend
            head.setScale(1 - 0.4 * t)

            if let tail = star.tail {
                let speed = hypot(star.velocity.dx, star.velocity.dy)
                let length = min(speed * star.tailFactor, star.maxTail)
                if length > 1, !isStrobing {
                    tail.position = star.position
                    tail.zRotation = atan2(star.velocity.dy, star.velocity.dx)
                    tail.size = CGSize(width: length, height: star.size * 0.85)
                    tail.alpha = alpha * 0.75 * min(1, length / (star.size * 2))
                    tail.colorBlendFactor = blend
                } else {
                    tail.alpha = 0
                }
            }

            if star.emberRate > 0, stars.count + spawned.count < Self.starBudget {
                star.emberDebt += star.emberRate * dt
                while star.emberDebt >= 1 {
                    star.emberDebt -= 1
                    let velocity = CGVector(
                        dx: star.velocity.dx * 0.12 + .random(in: -8...8) * unit,
                        dy: star.velocity.dy * 0.12 + .random(in: -8...4) * unit
                    )
                    spawnStar(at: star.position, velocity: velocity, recipe: .willowEmber, color: star.color, brightness: alpha * 0.8)
                }
            }
            index += 1
        }
    }

    private func retire(at index: Int) {
        let star = stars[index]
        recycle(dot: star.head)
        if let tail = star.tail { recycle(tail: tail) }
        stars.swapAt(index, stars.count - 1)
        stars.removeLast()
    }

    private func finishIfIdle() {
        guard !isFinishing, scheduledLaunches == 0, rockets.isEmpty, stars.isEmpty else { return }
        isFinishing = true
        sky.run(.sequence([
            .fadeOut(withDuration: 0.45),
            .run { [weak self] in
                // Outside SpriteKit's update pass: the handler removes the scene from its view. A show
                // added in the meantime cancels it.
                DispatchQueue.main.async {
                    guard let self, self.isFinishing else { return }
                    self.onFinished?()
                }
            },
        ]), withKey: "sky")
    }

    // MARK: - Bursts

    private func explode(_ shell: Shell, at center: CGPoint, drift: CGVector) {
        flash(at: center, shell: shell)
        impact.impactOccurred(intensity: min(1, 0.4 + shell.radius / (unit * 320)))
        // The stars keep a little of the rocket's momentum.
        let inherited = CGVector(dx: drift.dx * 0.15, dy: drift.dy * 0.15)
        let colors = shell.colors

        switch shell.style {
        case .peony:
            var recipe = StarRecipe.peony
            recipe.crackles = shell.crackles
            burst(at: center, directions: Self.sphere(count: scaled(74)), radius: shell.radius, recipe: recipe, drift: inherited, colors: colors)
            if shell.hasPistil {
                burst(at: center, directions: Self.sphere(count: scaled(28)), radius: shell.radius * 0.42, recipe: .pistil, drift: inherited, colors: [shell.secondary])
            }
        case .chrysanthemum:
            burst(at: center, directions: Self.sphere(count: scaled(96)), radius: shell.radius, recipe: .chrysanthemum, drift: inherited, colors: colors)
        case .ring:
            burst(at: center, directions: Self.ring(count: scaled(46)), radius: shell.radius, recipe: .ring, drift: inherited, colors: colors)
            if shell.hasPistil {
                burst(at: center, directions: Self.sphere(count: scaled(22)), radius: shell.radius * 0.35, recipe: .pistil, drift: inherited, colors: [shell.secondary])
            }
        case .willow:
            burst(at: center, directions: Self.sphere(count: scaled(54)), radius: shell.radius, recipe: .willow, drift: inherited, colors: [FireworkPalette.willowGold])
        case .crossette:
            burst(at: center, directions: Self.sphere(count: max(8, scaled(11))), radius: shell.radius, recipe: .crossette, drift: inherited, colors: colors)
        }
    }

    private func scaled(_ count: Int) -> Int {
        Int((CGFloat(count) * density * .random(in: 0.9...1.1)).rounded())
    }

    /// Launches one star per direction. `radius` is roughly how far the stars travel before they stop.
    private func burst(
        at center: CGPoint,
        directions: [SIMD3<Double>],
        radius: CGFloat,
        recipe: StarRecipe,
        drift: CGVector,
        colors: [UIColor]
    ) {
        for direction in directions {
            let speed = radius * recipe.drag * .random(in: 0.94...1.06)
            let velocity = CGVector(
                dx: CGFloat(direction.x) * speed + drift.dx,
                dy: CGFloat(direction.y) * speed + drift.dy
            )
            // Stars on the far side of the sphere look a little dimmer, which gives the burst depth.
            let brightness = 0.68 + 0.32 * CGFloat(direction.z + 1) / 2
            spawnStar(at: center, velocity: velocity, recipe: recipe, color: colors.randomElement() ?? .white, brightness: brightness)
        }
    }

    /// A crossette star breaks into four smaller ones flying off in a cross.
    private func split(_ star: Star) {
        let speed = hypot(star.velocity.dx, star.velocity.dy)
        let heading = atan2(star.velocity.dy, star.velocity.dx) + .random(in: -0.4...0.4)
        let childSpeed = max(speed * 1.1, 45 * unit * StarRecipe.crossetteChild.drag)
        for quarter in 0..<4 {
            let angle = heading + CGFloat(quarter) * .pi / 2
            let velocity = CGVector(dx: cos(angle) * childSpeed, dy: sin(angle) * childSpeed)
            spawnStar(at: star.position, velocity: velocity, recipe: .crossetteChild, color: star.color, brightness: star.brightness)
        }
        crackle(at: star.position)
    }

    /// A tiny white pop, like a crackling microstar.
    private func crackle(at point: CGPoint) {
        spawnStar(at: point, velocity: .zero, recipe: .crackle, color: .white, brightness: .random(in: 0.7...1))
    }

    /// A white-hot flash where the shell bursts, plus a wide, faint glow that lights up the sky around it.
    private func flash(at center: CGPoint, shell: Shell) {
        let core = SKSpriteNode(texture: FireworkTextures.dot)
        core.size = CGSize(width: shell.radius * 0.9, height: shell.radius * 0.9)
        core.color = shell.primary
        core.colorBlendFactor = 0.35
        core.blendMode = .add
        core.position = center
        core.setScale(0.3)
        addChild(core)
        let grow = SKAction.scale(to: 1, duration: 0.22)
        grow.timingMode = .easeOut
        core.run(.sequence([.group([grow, .fadeOut(withDuration: 0.3)]), .removeFromParent()]))

        let glow = SKSpriteNode(texture: FireworkTextures.dot)
        glow.size = CGSize(width: shell.radius * 3.2, height: shell.radius * 3.2)
        glow.color = shell.primary
        glow.colorBlendFactor = 1
        glow.blendMode = .add
        glow.position = center
        glow.alpha = 0.16
        addChild(glow)
        let fade = SKAction.fadeOut(withDuration: 0.9)
        fade.timingMode = .easeOut
        glow.run(.sequence([fade, .removeFromParent()]))
    }

    // MARK: - Stars and nodes

    private func spawnStar(at point: CGPoint, velocity: CGVector, recipe: StarRecipe, color: UIColor, brightness: CGFloat) {
        let unit = self.unit
        let size = recipe.size * unit * .random(in: 0.85...1.15)
        let head = makeDot()
        // The dot texture is mostly halo; its bright core is about a third of the sprite.
        head.size = CGSize(width: size * 3, height: size * 3)
        head.color = color
        head.colorBlendFactor = recipe.whiteHot ? 0.2 : 1
        head.position = point
        head.alpha = 0
        head.setScale(1)

        var tail: SKSpriteNode?
        if recipe.tailFactor > 0 {
            let node = makeTail()
            node.color = color
            node.alpha = 0
            tail = node
        }

        let lifetime = Double.random(in: recipe.lifetime)
        let star = Star(
            head: head,
            tail: tail,
            position: point,
            velocity: velocity,
            lifetime: lifetime,
            drag: recipe.drag,
            gravity: recipe.gravity * unit,
            size: size,
            color: color,
            brightness: brightness
        )
        star.tailFactor = recipe.tailFactor
        star.maxTail = recipe.maxTail * unit
        star.whiteHot = recipe.whiteHot
        star.strobeFrom = recipe.strobeFrom.map { $0 + .random(in: -0.06...0.08) } ?? 2
        // Blinks 11 to 19 times per second.
        star.strobeRate = CGFloat.random(in: 11...19) * 2 * CGFloat.pi
        star.strobePhase = CGFloat.random(in: 0...(2 * CGFloat.pi))
        star.emberRate = recipe.emberRate
        star.crackles = recipe.crackles
        if let split = recipe.splitAt { star.splitAt = .random(in: split) }
        spawned.append(star)
    }

    private func makeDot() -> SKSpriteNode {
        if let node = dotPool.popLast() {
            node.isHidden = false
            return node
        }
        let node = SKSpriteNode(texture: FireworkTextures.dot)
        node.blendMode = .add
        addChild(node)
        return node
    }

    private func makeTail() -> SKSpriteNode {
        if let node = tailPool.popLast() {
            node.isHidden = false
            return node
        }
        let node = SKSpriteNode(texture: FireworkTextures.tail)
        node.blendMode = .add
        // The tail's bright end sits on the star and the rest trails behind it.
        node.anchorPoint = CGPoint(x: 1, y: 0.5)
        addChild(node)
        return node
    }

    private func recycle(dot node: SKSpriteNode) {
        node.isHidden = true
        dotPool.append(node)
    }

    private func recycle(tail node: SKSpriteNode) {
        node.isHidden = true
        tailPool.append(node)
    }

    // MARK: - Shapes

    /// Evenly spread points on a randomly turned sphere (a Fibonacci spiral), so the burst looks round from
    /// any angle without clumps. `z` points at the viewer.
    private static func sphere(count: Int) -> [SIMD3<Double>] {
        guard count > 0 else { return [] }
        let golden = Double.pi * (3 - 5.0.squareRoot())
        let offset = Double.random(in: 0..<(2 * .pi))
        let rotation = Rotation.random()
        return (0..<count).map { index in
            let y = 1 - 2 * (Double(index) + 0.5) / Double(count)
            let radius = (1 - y * y).squareRoot()
            let angle = Double(index) * golden + offset
            return rotation.apply(SIMD3(cos(angle) * radius, y, sin(angle) * radius))
        }
    }

    /// A circle of points tilted toward the viewer at a random angle, so each ring is a different ellipse.
    private static func ring(count: Int) -> [SIMD3<Double>] {
        guard count > 0 else { return [] }
        let tilt = Double.random(in: 0.25...1.2)
        let spin = Double.random(in: 0..<(2 * .pi))
        let offset = Double.random(in: 0..<(2 * .pi))
        return (0..<count).map { index in
            let angle = Double(index) / Double(count) * 2 * .pi + offset
            let x = cos(angle)
            let y = sin(angle) * cos(tilt)
            let z = sin(angle) * sin(tilt)
            return SIMD3(x * cos(spin) - y * sin(spin), x * sin(spin) + y * cos(spin), z)
        }
    }
}

// MARK: - Model

private enum ShellStyle {
    /// A round burst of colored stars.
    case peony
    /// Long streaking stars that end in white glitter.
    case chrysanthemum
    /// A tilted ring.
    case ring
    /// Slow golden stars that droop and leave a trail of embers.
    case willow
    /// A few stars that each break into a cross of four.
    case crossette
}

private struct Shell {
    var style: ShellStyle
    var primary: UIColor
    var secondary: UIColor
    /// Colors the stars are drawn from: the primary one, sometimes mixed with the secondary one.
    var colors: [UIColor]
    var radius: CGFloat
    /// An inner core of a second color.
    var hasPistil: Bool
    var crackles: Bool

    static func random(style: ShellStyle, unit: CGFloat, isFinale: Bool, maxRadius: CGFloat) -> Shell {
        let primary = FireworkPalette.random()
        var secondary = FireworkPalette.random()
        while secondary == primary { secondary = FireworkPalette.random() }
        var radius = CGFloat.random(in: 105...145) * unit * (isFinale ? 1.18 : 1)
        switch style {
        case .ring: radius *= 0.9
        case .willow: radius *= 1.05
        case .crossette: radius *= 0.8
        case .peony, .chrysanthemum: break
        }
        let mixesColors = style != .willow && Double.random(in: 0..<1) < 0.3
        return Shell(
            style: style,
            primary: primary.jittered(),
            secondary: secondary.jittered(),
            colors: mixesColors ? [primary.jittered(), secondary.jittered()] : [primary.jittered()],
            radius: min(radius, maxRadius),
            hasPistil: Double.random(in: 0..<1) < 0.55,
            crackles: Double.random(in: 0..<1) < 0.35
        )
    }
}

/// How a kind of star moves and looks. Sizes, speeds and accelerations are in design units.
private struct StarRecipe {
    var lifetime: ClosedRange<Double>
    /// How fast the star slows down (per second).
    var drag: CGFloat
    var gravity: CGFloat
    var size: CGFloat
    /// Tail length per point per second of speed; 0 draws no tail.
    var tailFactor: CGFloat = 0
    var maxTail: CGFloat = 0
    /// Starts white and turns to its color as it cools.
    var whiteHot = true
    /// Fraction of its life after which the star blinks as glitter.
    var strobeFrom: CGFloat?
    /// Embers per second left behind.
    var emberRate: CGFloat = 0
    /// Seconds after which a crossette star splits.
    var splitAt: ClosedRange<Double>?
    var crackles = false

    static let peony = StarRecipe(lifetime: 1.3...1.75, drag: 2.6, gravity: 110, size: 3.4, tailFactor: 0.05, maxTail: 30)
    static let pistil = StarRecipe(lifetime: 0.95...1.3, drag: 2.8, gravity: 90, size: 3.0, tailFactor: 0.04, maxTail: 18)
    static let chrysanthemum = StarRecipe(
        lifetime: 1.7...2.1, drag: 2.3, gravity: 85, size: 2.8, tailFactor: 0.09, maxTail: 58, strobeFrom: 0.62
    )
    static let ring = StarRecipe(lifetime: 1.3...1.6, drag: 2.7, gravity: 80, size: 3.4, tailFactor: 0.04, maxTail: 24)
    static let willow = StarRecipe(
        lifetime: 2.3...2.8, drag: 3.0, gravity: 160, size: 2.7, tailFactor: 0.035, maxTail: 16, whiteHot: false, emberRate: 24
    )
    static let crossette = StarRecipe(
        lifetime: 1.0...1.0, drag: 1.5, gravity: 40, size: 3.8, tailFactor: 0.06, maxTail: 30, splitAt: 0.42...0.56
    )
    static let crossetteChild = StarRecipe(lifetime: 0.75...1.05, drag: 2.4, gravity: 90, size: 2.7, tailFactor: 0.06, maxTail: 24)
    static let rocketEmber = StarRecipe(lifetime: 0.25...0.5, drag: 2.0, gravity: 120, size: 1.7, whiteHot: false)
    static let willowEmber = StarRecipe(lifetime: 0.45...0.85, drag: 2.2, gravity: 55, size: 1.5, whiteHot: false)
    static let crackle = StarRecipe(lifetime: 0.08...0.16, drag: 0, gravity: 0, size: 3.2)
}

private final class Star {
    let head: SKSpriteNode
    let tail: SKSpriteNode?
    var position: CGPoint
    var velocity: CGVector
    var age: TimeInterval = 0
    let lifetime: TimeInterval
    let drag: CGFloat
    let gravity: CGFloat
    let size: CGFloat
    let color: UIColor
    let brightness: CGFloat
    var tailFactor: CGFloat = 0
    var maxTail: CGFloat = 0
    var whiteHot = true
    var strobeFrom: CGFloat = 2
    var strobeRate: CGFloat = 0
    var strobePhase: CGFloat = 0
    var emberRate: CGFloat = 0
    var emberDebt: CGFloat = 0
    var splitAt: TimeInterval?
    var crackles = false

    init(
        head: SKSpriteNode,
        tail: SKSpriteNode?,
        position: CGPoint,
        velocity: CGVector,
        lifetime: TimeInterval,
        drag: CGFloat,
        gravity: CGFloat,
        size: CGFloat,
        color: UIColor,
        brightness: CGFloat
    ) {
        self.head = head
        self.tail = tail
        self.position = position
        self.velocity = velocity
        self.lifetime = lifetime
        self.drag = drag
        self.gravity = gravity
        self.size = size
        self.color = color
        self.brightness = brightness
    }
}

private final class Rocket {
    let head: SKSpriteNode
    var position: CGPoint
    var velocity: CGVector
    let gravity: CGFloat
    let flightTime: TimeInterval
    let shell: Shell
    var age: TimeInterval = 0
    var emberDebt: CGFloat = 0
    let wobbleRate = CGFloat.random(in: 14...24)
    let wobblePhase = CGFloat.random(in: 0...(2 * .pi))

    init(head: SKSpriteNode, position: CGPoint, velocity: CGVector, gravity: CGFloat, flightTime: TimeInterval, shell: Shell) {
        self.head = head
        self.position = position
        self.velocity = velocity
        self.gravity = gravity
        self.flightTime = flightTime
        self.shell = shell
    }
}

/// A random rotation in 3D: a tilt around the x axis followed by a spin around the z axis.
private struct Rotation {
    var tilt: Double
    var spin: Double

    static func random() -> Rotation {
        Rotation(tilt: .random(in: 0..<(2 * .pi)), spin: .random(in: 0..<(2 * .pi)))
    }

    func apply(_ point: SIMD3<Double>) -> SIMD3<Double> {
        let y = point.y * cos(tilt) - point.z * sin(tilt)
        let z = point.y * sin(tilt) + point.z * cos(tilt)
        return SIMD3(point.x * cos(spin) - y * sin(spin), point.x * sin(spin) + y * cos(spin), z)
    }
}

private enum FireworkPalette {
    static let colors: [UIColor] = [
        UIColor(red: 1.00, green: 0.30, blue: 0.32, alpha: 1), // red
        UIColor(red: 1.00, green: 0.56, blue: 0.22, alpha: 1), // orange
        UIColor(red: 1.00, green: 0.84, blue: 0.36, alpha: 1), // gold
        UIColor(red: 0.42, green: 1.00, blue: 0.56, alpha: 1), // green
        UIColor(red: 0.36, green: 0.84, blue: 1.00, alpha: 1), // cyan
        UIColor(red: 0.50, green: 0.56, blue: 1.00, alpha: 1), // blue
        UIColor(red: 0.80, green: 0.46, blue: 1.00, alpha: 1), // violet
        UIColor(red: 1.00, green: 0.46, blue: 0.80, alpha: 1), // pink
        UIColor(red: 0.92, green: 0.95, blue: 1.00, alpha: 1), // silver
    ]
    static let willowGold = UIColor(red: 1.00, green: 0.70, blue: 0.30, alpha: 1)
    static let ember = UIColor(red: 1.00, green: 0.78, blue: 0.46, alpha: 1)

    static func random() -> UIColor {
        colors.randomElement() ?? .white
    }
}

private extension UIColor {
    /// The same color with a slightly different hue and brightness, so shells of the same color still vary.
    func jittered() -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        let shifted = (hue + .random(in: -0.025...0.025)).truncatingRemainder(dividingBy: 1)
        return UIColor(
            hue: shifted < 0 ? shifted + 1 : shifted,
            saturation: min(1, saturation * .random(in: 0.9...1.05)),
            brightness: min(1, brightness * .random(in: 0.92...1)),
            alpha: alpha
        )
    }
}

/// Textures drawn in code once and shared by every show.
private enum FireworkTextures {
    /// A white-hot core with a soft halo.
    static let dot: SKTexture = {
        let size = CGSize(width: 64, height: 64)
        let image = renderer(size: size).image { context in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.white.cgColor,
                    UIColor.white.withAlphaComponent(0.9).cgColor,
                    UIColor.white.withAlphaComponent(0.28).cgColor,
                    UIColor.white.withAlphaComponent(0).cgColor,
                ] as CFArray,
                locations: [0, 0.16, 0.42, 1]
            )!
            context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: size.width / 2, options: [])
        }
        return SKTexture(image: image)
    }()

    /// A tapered streak, transparent on the left and bright on the right, stretched behind a moving star.
    static let tail: SKTexture = {
        let size = CGSize(width: 128, height: 16)
        let image = renderer(size: size).image { context in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width - size.height / 2, y: size.height * 0.12))
            path.addArc(
                withCenter: CGPoint(x: size.width - size.height / 2, y: size.height / 2),
                radius: size.height * 0.38,
                startAngle: -.pi / 2,
                endAngle: .pi / 2,
                clockwise: true
            )
            path.close()
            path.addClip()
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.white.withAlphaComponent(0).cgColor,
                    UIColor.white.withAlphaComponent(0.35).cgColor,
                    UIColor.white.cgColor,
                ] as CFArray,
                locations: [0, 0.6, 1]
            )!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
        }
        return SKTexture(image: image)
    }()

    /// The night sky: darker at the top, where the shells burst, and lighter toward the bottom.
    static let sky: SKTexture = {
        let size = CGSize(width: 4, height: 256)
        let image = renderer(size: size).image { context in
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.white.cgColor,
                    UIColor.white.withAlphaComponent(0.75).cgColor,
                    UIColor.white.withAlphaComponent(0.3).cgColor,
                ] as CFArray,
                locations: [0, 0.55, 1]
            )!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        return SKTexture(image: image)
    }()

    private static func renderer(size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format)
    }
}
