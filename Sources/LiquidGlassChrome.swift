// T3d Boy — "Liquid Glass" theme rendering.
//
// A parody of Apple's Liquid Glass: the controls are panes of real, transparent glass —
// you see the UI through them — that are melting, with teardrops drooling off their
// bottom edges. `GlassSkin` renders one control as glass: a translucent tinted body, a
// bright top gloss, a crisp light rim, a soft cast shadow, and drips. The whole thing is
// ONE outline (capsule + bottom teardrops) so the rim never shows an internal seam.

import Cocoa

final class GlassSkin {
    private let shadow = CALayer()        // soft cast shadow (path-based)
    private let tint = CAGradientLayer()  // translucent body fill
    private let tintMask = CAShapeLayer()
    private let gloss = CAGradientLayer()  // top specular sheen
    private let glossMask = CAShapeLayer()
    private let rim = CAShapeLayer()       // bright glass edge
    private var installed = false

    /// Attach the glass layers beneath the host's own content (label draws on top).
    func install(on host: CALayer) {
        guard !installed else { return }
        installed = true
        host.masksToBounds = false // let drips and the cast shadow spill past the bounds
        // Insert at the bottom so the control's label/text stays on top.
        for (i, l) in [shadow, tint, gloss, rim].enumerated() { host.insertSublayer(l, at: UInt32(i)) }
        tint.mask = tintMask
        gloss.mask = glossMask
        rim.fillColor = NSColor.clear.cgColor
    }

    /// `tintColor`'s alpha is applied internally. `drips` are bottom protrusions as
    /// (centre-x fraction, width, length). `lift` brightens the glass on hover/press.
    func update(bounds: CGRect, radius: CGFloat, tintColor: NSColor,
                drips: [(cx: CGFloat, w: CGFloat, len: CGFloat)], lift: CGFloat) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let maxLen = drips.map(\.len).max() ?? 0
        // All layers share one extended frame that includes the drip overhang below the
        // control, and one path built in that frame's local (y-up) coordinates.
        let frame = CGRect(x: bounds.minX, y: bounds.minY - maxLen,
                           width: bounds.width, height: bounds.height + maxLen)
        let local = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        let path = Self.glassPath(width: bounds.width, height: bounds.height,
                                  radius: radius, baseY: maxLen, drips: drips)

        CATransaction.begin(); CATransaction.setDisableActions(true)
        for l in [shadow, tint, gloss, rim] { l.frame = frame }
        tintMask.frame = local; glossMask.frame = local

        // Body: a vertical glass gradient, a touch denser up top, see-through.
        tint.colors = [
            tintColor.withAlphaComponent(min(1, 0.40 + lift)).cgColor,
            tintColor.withAlphaComponent(min(1, 0.18 + lift)).cgColor,
        ]
        tint.startPoint = CGPoint(x: 0.5, y: 1); tint.endPoint = CGPoint(x: 0.5, y: 0)
        tintMask.path = path

        // Gloss: a bright sheen across the top of the body fading out by mid-height.
        gloss.colors = [
            NSColor.white.withAlphaComponent(0.65).cgColor,
            NSColor.white.withAlphaComponent(0.12).cgColor,
            NSColor.clear.cgColor,
        ]
        gloss.locations = [0.0, 0.32, 0.6]
        gloss.startPoint = CGPoint(x: 0.5, y: 1) // top
        gloss.endPoint = CGPoint(x: 0.5, y: maxLen / frame.height) // capsule bottom
        glossMask.path = path

        // Rim: the bright glass edge.
        rim.path = path
        rim.strokeColor = NSColor.white.withAlphaComponent(0.8).cgColor
        rim.lineWidth = 1.2

        // Cast shadow: glass floats above the UI.
        shadow.shadowPath = path
        shadow.shadowColor = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.4, alpha: 1).cgColor
        shadow.shadowOpacity = 0.22
        shadow.shadowRadius = 7
        shadow.shadowOffset = CGSize(width: 0, height: -3) // y-up: downward
        CATransaction.commit()
    }

    /// One closed outline: a capsule (rounded rect) with teardrops protruding from the
    /// bottom edge, traced as a single path so fill and stroke stay seamless. y-up; the
    /// capsule sits above `baseY` and drips hang down toward y=0.
    static func glassPath(width W: CGFloat, height H: CGFloat, radius rad: CGFloat,
                          baseY: CGFloat,
                          drips: [(cx: CGFloat, w: CGFloat, len: CGFloat)]) -> CGPath {
        let r = min(rad, H / 2)
        let by = baseY, ty = baseY + H
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: ty - r))
        p.addQuadCurve(to: CGPoint(x: r, y: ty), control: CGPoint(x: 0, y: ty))         // top-left
        p.addLine(to: CGPoint(x: W - r, y: ty))
        p.addQuadCurve(to: CGPoint(x: W, y: ty - r), control: CGPoint(x: W, y: ty))     // top-right
        p.addLine(to: CGPoint(x: W, y: by + r))
        p.addQuadCurve(to: CGPoint(x: W - r, y: by), control: CGPoint(x: W, y: by))     // bottom-right
        // Bottom edge, right → left, detouring down into each hanging droplet: a thin
        // neck that pools into a fat round bulb at the bottom, the way gravity pulls a
        // real drip of liquid glass.
        for d in drips.sorted(by: { $0.cx > $1.cx }) {
            let cx = W * d.cx, nw = d.w, L = d.len
            let br = nw * 0.92                 // bulb radius (wider than the neck)
            let bulbCY = by - (L - br)         // bulb centre
            guard cx - br > r, cx + br < W - r else { continue }
            p.addLine(to: CGPoint(x: cx + nw / 2, y: by))
            // neck → right of bulb
            p.addCurve(to: CGPoint(x: cx + br, y: bulbCY),
                       control1: CGPoint(x: cx + nw / 2, y: bulbCY + br * 0.7),
                       control2: CGPoint(x: cx + br, y: bulbCY + br * 0.95))
            // around the rounded bottom of the bulb
            p.addCurve(to: CGPoint(x: cx - br, y: bulbCY),
                       control1: CGPoint(x: cx + br, y: bulbCY - br * 1.1),
                       control2: CGPoint(x: cx - br, y: bulbCY - br * 1.1))
            // left of bulb → back up the neck
            p.addCurve(to: CGPoint(x: cx - nw / 2, y: by),
                       control1: CGPoint(x: cx - br, y: bulbCY + br * 0.95),
                       control2: CGPoint(x: cx - nw / 2, y: bulbCY + br * 0.7))
        }
        p.addLine(to: CGPoint(x: r, y: by))
        p.addQuadCurve(to: CGPoint(x: 0, y: by + r), control: CGPoint(x: 0, y: by))     // bottom-left
        p.closeSubpath()
        return p
    }

    /// Drip layout for a control of the given width. Prominent controls melt more.
    static func drips(width: CGFloat, heavy: Bool)
        -> [(cx: CGFloat, w: CGFloat, len: CGFloat)] {
        guard width > 70 else { return heavy ? [(0.5, 10, 20)] : [(0.62, 8, 15)] }
        return heavy
            ? [(0.27, 9, 20), (0.5, 11, 31), (0.73, 8, 23)]
            : [(0.64, 9, 18)]
    }
}
