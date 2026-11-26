import SpriteKit
import UIKit

/// Textures of the animations made of pieces, drawn in code once and shared by every animation. The white ones
/// take the color of each sprite.
enum CelebrationTextures {
    // MARK: - Lights

    /// A soft round light.
    static let glow: SKTexture = texture(size: CGSize(width: 64, height: 64)) { context, size in
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let light = gradient(white: [1, 0.72, 0.22, 0], locations: [0, 0.3, 0.62, 1])
        context.drawRadialGradient(light, startCenter: center, startRadius: 0, endCenter: center, endRadius: size.width / 2, options: [])
    }

    /// A four-pointed sparkle with a faint halo.
    static let sparkle: SKTexture = texture(size: CGSize(width: 64, height: 64)) { context, size in
        let width = size.width
        let middle = width / 2
        let pinch = width * 0.08
        let center = CGPoint(x: middle, y: middle)
        let halo = gradient(white: [0.5, 0.12, 0], locations: [0, 0.35, 1])
        context.drawRadialGradient(halo, startCenter: center, startRadius: 0, endCenter: center, endRadius: middle, options: [])
        let path = CGMutablePath()
        path.move(to: CGPoint(x: middle, y: 0))
        path.addQuadCurve(to: CGPoint(x: width, y: middle), control: CGPoint(x: middle + pinch, y: middle - pinch))
        path.addQuadCurve(to: CGPoint(x: middle, y: width), control: CGPoint(x: middle + pinch, y: middle + pinch))
        path.addQuadCurve(to: CGPoint(x: 0, y: middle), control: CGPoint(x: middle - pinch, y: middle + pinch))
        path.addQuadCurve(to: CGPoint(x: middle, y: 0), control: CGPoint(x: middle - pinch, y: middle - pinch))
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(UIColor.white.cgColor)
        context.fillPath()
    }

    // MARK: - Confetti

    static let confettiRectangle: SKTexture = texture(size: CGSize(width: 20, height: 12)) { context, size in
        context.addPath(UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 2).cgPath)
        context.setFillColor(UIColor.white.cgColor)
        context.fillPath()
    }

    static let confettiCircle: SKTexture = texture(size: CGSize(width: 16, height: 16)) { context, size in
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5))
    }

    /// A curly strip.
    static let confettiSquiggle: SKTexture = texture(size: CGSize(width: 32, height: 13)) { context, size in
        let path = CGMutablePath()
        let steps = 16
        for step in 0...steps {
            let fraction = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(
                x: 2 + (size.width - 4) * fraction,
                y: size.height / 2 + sin(fraction * 2 * .pi) * size.height * 0.28
            )
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        context.addPath(path)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(size.height * 0.36)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }

    // MARK: - Coins

    /// A gold coin with an embossed check mark.
    static let coin: SKTexture = texture(size: CGSize(width: 64, height: 64)) { context, size in
        let width = size.width
        let radius = width / 2
        let center = CGPoint(x: radius, y: radius)
        // The face, lit from the upper left and deeper toward the rim.
        context.saveGState()
        context.addEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5))
        context.clip()
        let face = gradient([0xFFF3B0, 0xFFD54A, 0xF2B42A, 0xD8961C], locations: [0, 0.45, 0.8, 1])
        context.drawRadialGradient(
            face,
            startCenter: CGPoint(x: width * 0.38, y: width * 0.32),
            startRadius: 0,
            endCenter: center,
            endRadius: radius * 1.05,
            options: [.drawsAfterEndLocation]
        )
        context.restoreGState()
        // The rim.
        context.setLineWidth(width * 0.07)
        context.setStrokeColor(CelebrationPalette.color(0xC8841A).cgColor)
        context.strokeEllipse(in: circle(center: center, radius: radius - width * 0.035 - 0.5))
        // An embossed inner ring: shadow on the lower right, light on the upper left.
        context.setLineWidth(width * 0.022)
        context.setStrokeColor(UIColor(red: 176 / 255, green: 110 / 255, blue: 10 / 255, alpha: 0.55).cgColor)
        context.strokeEllipse(in: circle(center: CGPoint(x: center.x + width * 0.008, y: center.y + width * 0.008), radius: radius * 0.7))
        context.setStrokeColor(UIColor(red: 1, green: 246 / 255, blue: 205 / 255, alpha: 0.9).cgColor)
        context.strokeEllipse(in: circle(center: CGPoint(x: center.x - width * 0.004, y: center.y - width * 0.004), radius: radius * 0.7))
        // The embossed check mark, the same way.
        let check = [CGPoint(x: 0.35, y: 0.52), CGPoint(x: 0.46, y: 0.63), CGPoint(x: 0.66, y: 0.40)]
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(width * 0.085)
        let strokes: [(offset: CGFloat, color: Int)] = [(width * 0.012, 0xB5730F), (-width * 0.008, 0xFFF4C4), (0, 0xF2BC38)]
        for stroke in strokes {
            context.addLines(between: check.map { CGPoint(x: $0.x * width + stroke.offset, y: $0.y * width + stroke.offset) })
            context.setStrokeColor(CelebrationPalette.color(stroke.color).cgColor)
            context.strokePath()
        }
        // A shine on the upper left.
        context.saveGState()
        context.translateBy(x: width * 0.34, y: width * 0.27)
        context.rotate(by: -0.5)
        context.scaleBy(x: 1, y: 0.5)
        let shine = gradient(white: [0.75, 0], locations: [0, 1])
        context.drawRadialGradient(shine, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: width * 0.2, options: [])
        context.restoreGState()
    }

    /// The coin's outline in dark gold, laid over it while it shows its edge.
    static let coinShade: SKTexture = texture(size: CGSize(width: 64, height: 64)) { context, size in
        context.setFillColor(CelebrationPalette.color(0x6B4300).cgColor)
        context.fillEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5))
    }

    // MARK: - Balloons

    /// Size of a balloon texture, in points: the body and the knot under it.
    static let balloonSize = CGSize(width: 64, height: 64 * 1.2 + balloonKnot)
    private static let balloonKnot: CGFloat = 7

    /// One balloon per color of `CelebrationPalette.balloons`.
    static let balloons: [SKTexture] = CelebrationPalette.balloons.map(balloon)

    /// A thin wavy string; its top end goes on the knot.
    static let balloonString: SKTexture = texture(size: CGSize(width: 12, height: 100)) { context, size in
        let middle = size.width / 2
        let height = size.height
        let path = CGMutablePath()
        path.move(to: CGPoint(x: middle, y: 0))
        path.addCurve(
            to: CGPoint(x: middle, y: height * 0.62),
            control1: CGPoint(x: middle + 5, y: height * 0.25),
            control2: CGPoint(x: middle - 5, y: height * 0.5)
        )
        path.addCurve(
            to: CGPoint(x: middle + 1, y: height),
            control1: CGPoint(x: middle + 4, y: height * 0.78),
            control2: CGPoint(x: middle - 3, y: height * 0.9)
        )
        context.addPath(path)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(1.3)
        context.setLineCap(.round)
        context.strokePath()
    }

    private static func balloon(_ color: UIColor) -> SKTexture {
        texture(size: balloonSize) { context, size in
            let width = size.width
            let height = width * 1.2
            // The knot.
            context.move(to: CGPoint(x: width * 0.5, y: height - 2))
            context.addLine(to: CGPoint(x: width * 0.5 + 5, y: height + balloonKnot - 0.5))
            context.addLine(to: CGPoint(x: width * 0.5 - 5, y: height + balloonKnot - 0.5))
            context.closePath()
            context.setFillColor(color.darkened(0.25).cgColor)
            context.fillPath()
            // The body, a little narrower at the bottom, lit from the upper left.
            let body = CGMutablePath()
            body.move(to: CGPoint(x: width * 0.5, y: 0.5))
            body.addCurve(
                to: CGPoint(x: width - 0.5, y: height * 0.45),
                control1: CGPoint(x: width * 0.8, y: 0.5),
                control2: CGPoint(x: width - 0.5, y: height * 0.22)
            )
            body.addCurve(
                to: CGPoint(x: width * 0.5, y: height),
                control1: CGPoint(x: width - 0.5, y: height * 0.7),
                control2: CGPoint(x: width * 0.68, y: height * 0.93)
            )
            body.addCurve(
                to: CGPoint(x: 0.5, y: height * 0.45),
                control1: CGPoint(x: width * 0.32, y: height * 0.93),
                control2: CGPoint(x: 0.5, y: height * 0.7)
            )
            body.addCurve(
                to: CGPoint(x: width * 0.5, y: 0.5),
                control1: CGPoint(x: 0.5, y: height * 0.22),
                control2: CGPoint(x: width * 0.2, y: 0.5)
            )
            body.closeSubpath()
            context.saveGState()
            context.addPath(body)
            context.clip()
            let shading = gradient([color.lightened(0.45), color, color.darkened(0.35)], locations: [0, 0.35, 1])
            context.drawRadialGradient(
                shading,
                startCenter: CGPoint(x: width * 0.36, y: height * 0.3),
                startRadius: 0,
                endCenter: CGPoint(x: width * 0.45, y: height * 0.45),
                endRadius: height * 0.75,
                options: [.drawsAfterEndLocation]
            )
            context.restoreGState()
            // A glossy highlight.
            context.saveGState()
            context.translateBy(x: width * 0.31, y: height * 0.25)
            context.rotate(by: -0.45)
            context.scaleBy(x: 0.7, y: 1.25)
            let shine = gradient(white: [0.8, 0], locations: [0, 1])
            context.drawRadialGradient(shine, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: width * 0.16, options: [])
            context.restoreGState()
        }
    }

    // MARK: - Stars

    /// One star per color of `CelebrationPalette.stars`.
    static let stars: [SKTexture] = CelebrationPalette.stars.map(star)

    private static func star(_ color: UIColor) -> SKTexture {
        texture(size: CGSize(width: 64, height: 64)) { context, size in
            let width = size.width
            let center = CGPoint(x: width / 2, y: width / 2 + width * 0.03)
            let outer = width * 0.45
            let inner = outer * 0.5
            let path = CGMutablePath()
            for index in 0..<10 {
                let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / 5
                let radius = index.isMultiple(of: 2) ? outer : inner
                let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            // The outline rounds the tips and keeps the star visible over the light appearance.
            context.addPath(path)
            context.setLineJoin(.round)
            context.setLineWidth(width * 0.07)
            context.setStrokeColor(color.darkened(0.25).cgColor)
            context.strokePath()
            context.saveGState()
            context.addPath(path)
            context.clip()
            let fill = gradient([color.lightened(0.8), color, color.darkened(0.15)], locations: [0, 0.5, 1])
            context.drawRadialGradient(
                fill,
                startCenter: CGPoint(x: center.x - width * 0.08, y: center.y - width * 0.1),
                startRadius: 0,
                endCenter: center,
                endRadius: outer,
                options: [.drawsAfterEndLocation]
            )
            context.restoreGState()
        }
    }

    // MARK: - Hearts

    /// One heart per color of `CelebrationPalette.hearts`.
    static let hearts: [SKTexture] = CelebrationPalette.hearts.map(heart)

    private static func heart(_ color: UIColor) -> SKTexture {
        texture(size: CGSize(width: 64, height: 64)) { context, size in
            let side = size.width
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * side, y: y * side)
            }
            let path = CGMutablePath()
            path.move(to: point(0.5, 0.88))
            path.addCurve(to: point(0.04, 0.31), control1: point(0.14, 0.64), control2: point(0.04, 0.44))
            path.addCurve(to: point(0.29, 0.07), control1: point(0.04, 0.16), control2: point(0.16, 0.07))
            path.addCurve(to: point(0.5, 0.21), control1: point(0.39, 0.07), control2: point(0.46, 0.13))
            path.addCurve(to: point(0.71, 0.07), control1: point(0.54, 0.13), control2: point(0.61, 0.07))
            path.addCurve(to: point(0.96, 0.31), control1: point(0.84, 0.07), control2: point(0.96, 0.16))
            path.addCurve(to: point(0.5, 0.88), control1: point(0.96, 0.44), control2: point(0.86, 0.64))
            path.closeSubpath()
            context.saveGState()
            context.addPath(path)
            context.clip()
            let fill = gradient([color.lightened(0.4), color, color.darkened(0.25)], locations: [0, 0.45, 1])
            context.drawRadialGradient(
                fill,
                startCenter: point(0.34, 0.26),
                startRadius: 0,
                endCenter: point(0.5, 0.45),
                endRadius: side * 0.6,
                options: [.drawsAfterEndLocation]
            )
            context.restoreGState()
            // A small highlight on the left lobe.
            context.saveGState()
            context.translateBy(x: side * 0.28, y: side * 0.24)
            context.rotate(by: -0.6)
            context.scaleBy(x: 1, y: 0.55)
            let shine = gradient(white: [0.75, 0], locations: [0, 1])
            context.drawRadialGradient(shine, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: side * 0.1, options: [])
            context.restoreGState()
        }
    }

    // MARK: - Check mark

    /// Radius of the disc in `disc`, whose texture leaves room around it for the shadow.
    static let discRadius: CGFloat = 50
    /// Width and height of the `disc` texture.
    static let discSide: CGFloat = 140

    /// The green disc behind the check mark, with a soft shadow and a gloss on its top half.
    static let disc: SKTexture = texture(size: CGSize(width: discSide, height: discSide)) { context, size in
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = discRadius
        let shadowCenter = CGPoint(x: center.x, y: center.y + 5)
        let shadow = gradient([UIColor(white: 0, alpha: 0.26), UIColor(white: 0, alpha: 0)], locations: [0, 1])
        context.drawRadialGradient(
            shadow,
            startCenter: shadowCenter,
            startRadius: radius * 0.8,
            endCenter: shadowCenter,
            endRadius: radius * 1.32,
            options: [.drawsBeforeStartLocation]
        )
        context.saveGState()
        context.addEllipse(in: circle(center: center, radius: radius))
        context.clip()
        let fill = gradient([0x5EDC7A, 0x26B54A], locations: [0, 1])
        context.drawLinearGradient(fill, start: CGPoint(x: center.x, y: center.y - radius), end: CGPoint(x: center.x, y: center.y + radius), options: [])
        context.addEllipse(in: CGRect(x: center.x - radius * 0.85, y: center.y - radius, width: radius * 1.7, height: radius * 1.1))
        context.clip()
        let gloss = gradient(white: [0.22, 0], locations: [0, 1])
        context.drawLinearGradient(gloss, start: CGPoint(x: center.x, y: center.y - radius), end: center, options: [])
        context.restoreGState()
    }

    // MARK: - Emojis

    /// The texture is this many times as big as the emoji in it, so its corners are not cut off as it turns.
    static let emojiPadding: CGFloat = emojiSide / emojiFontSize
    private static let emojiSide: CGFloat = 72
    private static let emojiFontSize: CGFloat = 56

    /// The party emojis that rain down.
    static let emojis: [SKTexture] = ["🎉", "🥳", "🎊", "👏", "🙌", "🏆", "💪", "🤩", "💯", "✅"].map(emoji)

    private static func emoji(_ text: String) -> SKTexture {
        texture(size: CGSize(width: emojiSide, height: emojiSide)) { _, size in
            let string = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: emojiFontSize)])
            let bounds = string.size()
            string.draw(at: CGPoint(x: (size.width - bounds.width) / 2, y: (size.height - bounds.height) / 2))
        }
    }

    // MARK: - Drawing

    private static func texture(size: CGSize, draw: (CGContext, CGSize) -> Void) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            draw(rendererContext.cgContext, size)
        }
        return SKTexture(image: image)
    }

    private static func gradient(_ colors: [UIColor], locations: [CGFloat]) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: locations)!
    }

    private static func gradient(_ colors: [Int], locations: [CGFloat]) -> CGGradient {
        gradient(colors.map(CelebrationPalette.color), locations: locations)
    }

    /// White at each opacity of `alphas`.
    private static func gradient(white alphas: [CGFloat], locations: [CGFloat]) -> CGGradient {
        gradient(alphas.map { UIColor(white: 1, alpha: $0) }, locations: locations)
    }

    private static func circle(center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
