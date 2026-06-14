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

// Road Trip Mode — the late-night car ride. The cabin is dark and the game is hard to
// make out; the only real light is the glare of streetlights as you drive past them —
// each a soft rounded pool of light that sweeps across the screen on its own angle, swells
// as you pass beneath the lamp, then slides away into darkness. The worm light still helps
// a little. This effect is time-varying, so ScreenEffects drives an animation timer.
enum RoadTripLighting {
    private static let key = "roadTripMode"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            // Road Trip looks best with the worm light to read the screen by, so turning
            // it on forces the worm light on (and the UI locks the worm light meanwhile).
            if newValue { WormLight.isEnabled = true }
            NotificationCenter.default.post(name: .screenEffectsChanged, object: nil)
        }
    }

    /// Baseline cabin illumination between streetlights — dark, but not pitch black,
    /// so the game is faintly visible (challenging, as asked).
    static let baseAmbient: Float = 0.24
}

// A single multiplicative "light map" over the host layer (emulator view or
// library art view). visible = pixels × light, where light = ambient (lowered
// by Hardcore) plus the warm worm-light pool plus Road Trip Mode's passing
// streetlights. Multiply can't exceed the pixel, so it never blows out to white —
// the lights *reveal and warm* the screen rather than painting over it. Shared so the
// in-library preview matches gameplay exactly.
final class ScreenEffects {
    private let lightLayer = CALayer()
    private var lastDim: Float = 0
    private var lastWorm = false
    private var timer: Timer?

    // Road Trip Mode: a rolling list of streetlights, each a rounded pool of light that
    // travels across the screen from `entry` to `exit` (random angles, so lights arrive
    // from different directions as you pass them).
    private struct Streetlight {
        var start: CFTimeInterval
        var duration: Double
        var peak: Float
        var ex0: Float, ey0: Float // entry point (just off-screen)
        var ex1: Float, ey1: Float // exit point (off the far side)
    }
    private var lights: [Streetlight] = []
    private var nextSpawn: CFTimeInterval = 0
    private var carBuf = [Float](repeating: 0, count: WormLight.w * WormLight.h)

    init(host: CALayer) {
        lightLayer.magnificationFilter = .linear // smooth light, not pixel art
        lightLayer.compositingFilter = "multiplyBlendMode"
        lightLayer.isHidden = true
        host.addSublayer(lightLayer)
    }

    deinit { timer?.invalidate() }

    func layout(_ bounds: CGRect) { lightLayer.frame = bounds }

    func apply(dimOpacity: Float, wormOn: Bool, animated: Bool = false) {
        lastDim = dimOpacity
        lastWorm = wormOn
        let car = RoadTripLighting.isEnabled

        // Nothing to do → leave the screen untouched
        if dimOpacity <= 0.001 && !wormOn && !car {
            lightLayer.isHidden = true
            stopAnimating()
            return
        }
        lightLayer.isHidden = false
        if car { startAnimating() } else { stopAnimating() }
        render()
    }

    // MARK: - Animation driver (only running while Road Trip Mode is on)

    private func startAnimating() {
        guard timer == nil else { return }
        nextSpawn = CACurrentMediaTime() + Double.random(in: 0.2 ... 1.0)
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.render() }
        RunLoop.main.add(t, forMode: .common) // keep sweeping during menu tracking / resize
        timer = t
    }

    private func stopAnimating() {
        timer?.invalidate()
        timer = nil
        lights.removeAll()
    }

    // MARK: - Render the current light map

    private func render() {
        let car = RoadTripLighting.isEnabled
        let W = WormLight.w, H = WormLight.h
        // Road Trip Mode imposes its own dark cabin; otherwise ambient comes from Hardcore.
        let ambient: Float = car ? RoadTripLighting.baseAmbient : max(0, min(1, 1 - lastDim))

        for i in carBuf.indices { carBuf[i] = 0 }
        if car { accumulateStreetlights(into: &carBuf, W: W, H: H) }

        let wormLift: Float = 0.85
        var px = [UInt32](repeating: 0, count: W * H)
        for i in 0 ..< px.count {
            let s = lastWorm ? WormLight.strength[i] : 0
            let street = min(1, carBuf[i])
            let level = min(1, ambient + street + s * wormLift)
            // Streetlights read as a slightly warm white; the worm pool an amber cast.
            let r = level
            let g = level * (1 - 0.05 * street - 0.12 * s)
            let b = level * (1 - 0.18 * street - 0.40 * s)
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

    /// Advance the streetlight simulation and add each light's rounded pool to `buf`.
    private func accumulateStreetlights(into buf: inout [Float], W: Int, H: Int) {
        let now = CACurrentMediaTime()
        if now >= nextSpawn {
            // Always enter from above and exit below (a streetlight passing overhead),
            // but vary the horizontal entry/exit so the pool crosses on a random angle.
            lights.append(Streetlight(
                start: now,
                duration: Double.random(in: 0.9 ... 1.7),
                peak: Float.random(in: 0.7 ... 1.0),
                ex0: Float.random(in: -0.35 ... 1.35), ey0: -0.35,
                ex1: Float.random(in: -0.35 ... 1.35), ey1: 1.35))
            nextSpawn = now + Double.random(in: 0.5 ... 3.0) // random gaps between lamps
        }
        lights.removeAll { now - $0.start > $0.duration }

        let aspect = Float(W) / Float(H) // keep the pool round on a 10:9 screen
        let haloR2: Float = 0.62 * 0.62
        let coreR2: Float = 0.22 * 0.22
        let elong: Float = 1.45         // stretch slightly along travel → a soft motion streak

        for light in lights {
            let u = Float((now - light.start) / light.duration) // 0…1 through the pass
            let amp = light.peak * sinf(Float.pi * u)           // swells then fades
            if amp <= 0.001 { continue }
            let cx = light.ex0 + (light.ex1 - light.ex0) * u    // pool centre, this instant
            let cy = light.ey0 + (light.ey1 - light.ey0) * u
            var dirx = (light.ex1 - light.ex0) * aspect, diry = light.ey1 - light.ey0
            let dl = (dirx * dirx + diry * diry).squareRoot()
            if dl > 0.0001 { dirx /= dl; diry /= dl } else { dirx = 0; diry = 1 }

            for r in 0 ..< H {
                let dyh = Float(r) / Float(H) - cy
                let off = r * W
                for c in 0 ..< W {
                    let dxh = (Float(c) / Float(W) - cx) * aspect
                    // rotate into the pool's travel frame and squash along it for the streak
                    let along = (dxh * dirx + dyh * diry) / elong
                    let perp = -dxh * diry + dyh * dirx
                    let d2 = along * along + perp * perp
                    let halo = max(0, 1 - d2 / haloR2)
                    let core = max(0, 1 - d2 / coreR2)
                    buf[off + c] += amp * (0.55 * halo * halo + 0.9 * core * core)
                }
            }
        }
    }
}
