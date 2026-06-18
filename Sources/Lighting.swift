// T3d Boy — screen lighting effects that recreate the original Game Boy:
//   • Hardcore Lighting — the non-backlit DMG: dim the emulator in a dark room.
//   • Worm Light    — a warm '90s clip-on light shining down onto the screen,
//                     the accessory people used to actually see the thing.
// Both affect ONLY the emulator's own view (game window + library art preview),
// never the rest of the Mac display, and we only ever READ the light sensor.

import Cocoa

extension Notification.Name {
    static let screenEffectsChanged = Notification.Name("T3dBoyScreenEffectsChanged")
}

enum HardcoreLighting {
    private static let key = "hardcoreMode"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: .screenEffectsChanged, object: nil)
        }
    }

    // True ambient lux isn't exposed on Apple Silicon, so we read display
    // brightness as a proxy via private DisplayServices (READ-ONLY — never Set).
    // With macOS Auto-Brightness on, the light sensor drives this number.
    private static let getBrightness: (@convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32)? = {
        guard let h = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_NOW), let sym = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32).self)
    }()

    static func displayBrightness() -> Float? {
        guard let fn = getBrightness else { return nil }
        var b: Float = -1
        return fn(CGMainDisplayID(), &b) == 0 && b >= 0 ? b : nil
    }

    /// Whether this Mac can actually drive the effect — i.e. we can read a brightness the
    /// ambient-light sensor influences. Built-in displays (and ALS-equipped external
    /// displays like the Studio Display) report a value; a Mac mini/Studio with a plain
    /// monitor and no sensor returns nil, so the option is offered only where it works.
    static var isSupported: Bool { displayBrightness() != nil }

    // brightness proxy → dim opacity. Lower brightness (darker room) → more dim.
    // A small baseline applies even in bright light (the real DMG was never vivid).
    static let baseline: Float = 0.08
    static let ceiling: Float = 0.85
    static let darkPoint: Float = 0.20
    static let brightPoint: Float = 0.95

    static func dimOpacity(forBrightness brightness: Float?) -> Float {
        guard let b = brightness else { return baseline }
        let t = max(0, min(1, (b - darkPoint) / (brightPoint - darkPoint))) // 0 dark … 1 bright
        return baseline + (1 - t) * (ceiling - baseline)
    }

    static func currentDimOpacity() -> Float { dimOpacity(forBrightness: displayBrightness()) }
}

enum WormLight {
    private static let key = "wormLight"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: .screenEffectsChanged, object: nil)
        }
    }

    // Light-map resolution (smooth gradient, scaled up — needn't be full res).
    static let w = 160, h = 144

    // The light source position (normalised; x 0…1 left→right, y 0…1 top→bottom)
    // is user-adjustable by dragging the on-screen handle, and persisted.
    private static let srcXKey = "wormSrcX"
    private static let srcYKey = "wormSrcY"
    static let defaultX: Float = 0.62, defaultY: Float = 0.06

    static var sourceX: Float {
        UserDefaults.standard.object(forKey: srcXKey) == nil
            ? defaultX : Float(UserDefaults.standard.double(forKey: srcXKey))
    }
    static var sourceY: Float {
        UserDefaults.standard.object(forKey: srcYKey) == nil
            ? defaultY : Float(UserDefaults.standard.double(forKey: srcYKey))
    }

    static func setSource(x: Float, y: Float) {
        let cx = max(0.05, min(0.95, x))
        let cy = max(0.0, min(0.6, y))
        UserDefaults.standard.set(Double(cx), forKey: srcXKey)
        UserDefaults.standard.set(Double(cy), forKey: srcYKey)
        rebuildStrength()
        NotificationCenter.default.post(name: .screenEffectsChanged, object: nil)
    }

    // Per-pixel strength of the worm light's pool (0 = none, 1 = full): a bright
    // hotspot at the source with a soft falloff. Rebuilt when the angle changes.
    private(set) static var strength: [Float] = buildStrength(sx: sourceX, sy: sourceY)
    static func rebuildStrength() { strength = buildStrength(sx: sourceX, sy: sourceY) }

    private static func buildStrength(sx: Float, sy: Float) -> [Float] {
        var f = [Float](repeating: 0, count: w * h)
        let poolR: Float = 1.10, hotR: Float = 0.42

        // Grazing angle: the further the source sits from the screen centre, the
        // more the light rakes across the surface, so the pool stretches into an
        // ellipse along the source→centre axis (a more 3D, angled-light feel).
        // Centred = round; near an edge = a long elongated streak into the screen.
        let ax = 0.5 - sx, ay = 0.5 - sy
        let alen = (ax * ax + ay * ay).squareRoot()
        let graze = min(1, alen / 0.5)
        let major = 1 + graze * 1.2 // elongation factor along the grazing axis (tune by feel)
        let ux: Float = alen > 0.01 ? ax / alen : 0
        let uy: Float = alen > 0.01 ? ay / alen : 1

        for r in 0 ..< h {
            for c in 0 ..< w {
                let nx = Float(c) / Float(w), ny = Float(r) / Float(h) // ny=0 is the top
                let dx = nx - sx, dy = ny - sy
                let par = dx * ux + dy * uy  // distance along the grazing axis (stretched)
                let per = -dx * uy + dy * ux // perpendicular distance
                let d = ((par / major) * (par / major) + per * per).squareRoot()
                let pool = max(0, 1 - d / poolR)
                let hot = max(0, 1 - d / hotR)
                f[r * w + c] = min(1, pool * pool * 0.9 + hot * hot * 0.7)
            }
        }
        return f
    }
}

// T3d LCD Real Feel™ — recreates an old LCD's pixel persistence by blending each
// frame with the previous one. Many Game Boy games faked transparency/extra shades
// by flickering pixels on alternate frames, trusting the slow DMG screen to blend
// them; on a crisp emulated display that reads as harsh flicker, so we blend it back.
enum LCDGhosting {
    private static let key = "lcdGhosting"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true } // on by default
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: .screenEffectsChanged, object: nil)
        }
    }
}

// T3d Boy Light — mimics the Game Boy Light's electroluminescent backlight: the screen
// glows an even teal/cyan-green, the way that indigo-gold console lit its panel. We recolour
// the emulator picture to the GB Light teal (preserving each pixel's light/dark structure,
// so the image still reads) and lift its brightness a touch to read as *backlit* rather
// than reflective. Sampled from the real console's lit screen (~teal-turquoise).
enum T3dBoyLight {
    private static let key = "t3dBoyLight"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: .screenEffectsChanged, object: nil)
        }
    }

    /// The EL backlight teal — recolours the screen (hue/saturation) via a colour blend.
    static let tint = NSColor(srgbRed: 0.13, green: 0.80, blue: 0.76, alpha: 1)
    /// A soft teal lift screen-blended over the picture so it glows like a backlight.
    static let glow = NSColor(srgbRed: 0.20, green: 0.92, blue: 0.90, alpha: 0.22)
    /// The multiply colour at the screen edge — a deeper teal that darkens the corners
    /// (centre stays white = unchanged), for the EL panel's gently uneven glow.
    static let vignetteEdge = NSColor(srgbRed: 0.50, green: 0.70, blue: 0.69, alpha: 1)
}

// Screen effects layered over the host layer (emulator view or library art preview),
// shared so the in-library preview matches gameplay exactly:
//   • a multiplicative "light map" (`lightLayer`) for Hardcore dimming + the warm worm-light
//     pool — multiply can't exceed the pixel, so lights *reveal* rather than paint over;
//   • a teal recolour + glow (`tealLayer` / `glowLayer`) for T3d Boy Light's EL backlight.
final class ScreenEffects {
    private let lightLayer = CALayer()           // Hardcore dim + worm pool (multiply)
    private let glowLayer = CALayer()            // T3d Boy Light brightness lift (screen)
    private let tealLayer = CALayer()            // T3d Boy Light recolour (colour blend)
    private let vignetteLayer = CAGradientLayer() // T3d Boy Light edge darkening (multiply)
    private var lastDim: Float = 0
    private var lastWorm = false
    /// T3d Boy Light only made sense on the original Game Boy; a CGB host sets this false
    /// so the teal backlight never applies to a Game Boy Color game.
    var allowsBacklight = true

    init(host: CALayer) {
        lightLayer.magnificationFilter = .linear // smooth light, not pixel art
        lightLayer.compositingFilter = "multiplyBlendMode"
        lightLayer.isHidden = true
        host.addSublayer(lightLayer)

        // T3d Boy Light: glow (screen-blend) under the recolour (colour-blend), with a
        // subtle radial vignette (multiply) on top that dims the edges toward a deeper
        // teal — the slightly uneven look of the real EL panel.
        glowLayer.compositingFilter = "screenBlendMode"
        glowLayer.backgroundColor = T3dBoyLight.glow.cgColor
        glowLayer.isHidden = true
        host.addSublayer(glowLayer)

        tealLayer.compositingFilter = "colorBlendMode"
        tealLayer.backgroundColor = T3dBoyLight.tint.cgColor
        tealLayer.isHidden = true
        host.addSublayer(tealLayer)

        vignetteLayer.type = .radial
        vignetteLayer.colors = [NSColor.white.cgColor, T3dBoyLight.vignetteEdge.cgColor]
        vignetteLayer.locations = [0.42, 1.0]              // clean centre, darkening to the edge
        vignetteLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignetteLayer.endPoint = CGPoint(x: 1, y: 1)
        vignetteLayer.compositingFilter = "multiplyBlendMode"
        vignetteLayer.isHidden = true
        host.addSublayer(vignetteLayer)
    }

    func layout(_ bounds: CGRect) {
        lightLayer.frame = bounds
        glowLayer.frame = bounds
        tealLayer.frame = bounds
        vignetteLayer.frame = bounds
    }

    func apply(dimOpacity: Float, wormOn: Bool, animated: Bool = false) {
        lastDim = dimOpacity
        lastWorm = wormOn
        let backlight = T3dBoyLight.isEnabled && allowsBacklight

        let needMap = dimOpacity > 0.001 || wormOn
        lightLayer.isHidden = !needMap
        if needMap { render() }

        glowLayer.isHidden = !backlight
        tealLayer.isHidden = !backlight
        vignetteLayer.isHidden = !backlight
    }

    // MARK: - Render the multiplicative light map (Hardcore dim + worm pool)

    private func render() {
        let W = WormLight.w, H = WormLight.h
        let ambient: Float = max(0, min(1, 1 - lastDim))
        let wormLift: Float = 0.85
        var px = [UInt32](repeating: 0, count: W * H)
        for i in 0 ..< px.count {
            let s = lastWorm ? WormLight.strength[i] : 0
            let level = min(1, ambient + s * wormLift)
            // The worm pool casts a warm amber light.
            let r = level
            let g = level * (1 - 0.12 * s)
            let b = level * (1 - 0.40 * s)
            px[i] = 0xFF00_0000
                | (UInt32(max(0, min(255, r * 255))) << 16)
                | (UInt32(max(0, min(255, g * 255))) << 8)
                |  UInt32(max(0, min(255, b * 255)))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lightLayer.contents = makeImage(from: px)
        CATransaction.commit()
    }
}
