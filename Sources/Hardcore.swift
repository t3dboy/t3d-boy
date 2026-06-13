// T3d Boy — screen lighting effects that recreate the original Game Boy:
//   • Hardcore Mode — the non-backlit DMG: dim the emulator in a dark room.
//   • Worm Light    — a warm '90s clip-on light shining down onto the screen,
//                     the accessory people used to actually see the thing.
// Both affect ONLY the emulator's own view (game window + library art preview),
// never the rest of the Mac display, and we only ever READ the light sensor.

import Cocoa

extension Notification.Name {
    static let screenEffectsChanged = Notification.Name("T3dBoyScreenEffectsChanged")
}

enum Hardcore {
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
        return fn(CGMainDisplayID(), &b) == 0 ? b : nil
    }

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

// A single multiplicative "light map" over the host layer (emulator view or
// library art view). visible = pixels × light, where light = ambient (lowered
// by Hardcore) plus the warm worm-light pool. Multiply can't exceed the pixel,
// so it never blows out to white — the worm light *reveals and warms* the
// screen rather than painting over it. Shared so the in-library preview matches
// gameplay exactly.
final class ScreenEffects {
    private let lightLayer = CALayer()

    init(host: CALayer) {
        lightLayer.magnificationFilter = .linear // smooth light, not pixel art
        lightLayer.compositingFilter = "multiplyBlendMode"
        lightLayer.isHidden = true
        host.addSublayer(lightLayer)
    }

    func layout(_ bounds: CGRect) { lightLayer.frame = bounds }

    func apply(dimOpacity: Float, wormOn: Bool, animated: Bool = false) {
        // Nothing to do → leave the screen untouched
        if dimOpacity <= 0.001 && !wormOn {
            lightLayer.isHidden = true
            return
        }
        let ambient = max(0, min(1, 1 - dimOpacity)) // 1 = full light, lower = dimmer room
        let lift: Float = 0.85 // how much the worm light raises illumination in its pool

        var px = [UInt32](repeating: 0, count: WormLight.w * WormLight.h)
        for i in 0 ..< px.count {
            let s = wormOn ? WormLight.strength[i] : 0
            let level = min(1, ambient + s * lift)
            // Warm tint: the worm pool pulls green/blue down, leaving an amber cast
            let r = level
            let g = level * (1 - 0.12 * s)
            let b = level * (1 - 0.40 * s)
            px[i] = 0xFF00_0000
                | (UInt32(max(0, min(255, r * 255))) << 16)
                | (UInt32(max(0, min(255, g * 255))) << 8)
                |  UInt32(max(0, min(255, b * 255)))
        }
        lightLayer.isHidden = false
        CATransaction.begin()
        CATransaction.setDisableActions(true) // discrete updates; a light switching on is instant
        lightLayer.contents = makeImage(from: px)
        CATransaction.commit()
    }
}
