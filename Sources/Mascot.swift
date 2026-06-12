// T3d Boy — T3d, the pixel mascot. A little DMG-green monster who guides
// onboarding. Drawn as a 16×16 sprite, scaled with nearest-neighbor.

import Cocoa

enum Mascot {
    // Palette: o = outline, g = body, d = shade/cheeks, w = eye white, e = pupil
    static let palette: [Character: UInt32] = [
        "o": 0xFF0F380F,
        "g": 0xFF8BAC0F,
        "d": 0xFF306230,
        "w": 0xFFF4F7E8,
        "e": 0xFF0F380F,
    ]

    // Frame 0: idle. Frame 1: blink.
    static let frames: [[String]] = [
        [
            "..oo........oo..",
            "..ogo......ogo..",
            "...ogoooooogo...",
            "...oggggggggo...",
            "..oggggggggggo..",
            ".oggwwggggwwggo.",
            ".ogwweggggwwego.",
            ".oggggggggggggo.",
            ".oggggooooggggo.",
            ".odgggggggggdgo.",
            "..oggggggggggo..",
            "..oggggggggggo..",
            "...oggggggggo...",
            "..oggo....oggo..",
            "..ogo......ogo..",
            "...o........o...",
        ],
        [
            "..oo........oo..",
            "..ogo......ogo..",
            "...ogoooooogo...",
            "...oggggggggo...",
            "..oggggggggggo..",
            ".oggggggggggggo.",
            ".ogoogggggooggo.",
            ".oggggggggggggo.",
            ".oggggooooggggo.",
            ".odgggggggggdgo.",
            "..oggggggggggo..",
            "..oggggggggggo..",
            "...oggggggggo...",
            "..oggo....oggo..",
            "..ogo......ogo..",
            "...o........o...",
        ],
    ]

    static func image(frame: Int) -> CGImage? {
        let rows = frames[frame % frames.count]
        let h = rows.count
        let w = rows[0].count
        var px = [UInt32](repeating: 0, count: w * h)
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                px[y * w + x] = palette[ch] ?? 0
            }
        }
        return px.withUnsafeMutableBytes { ptr -> CGImage? in
            guard let ctx = CGContext(
                data: ptr.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return nil }
            return ctx.makeImage()
        }
    }
}

// Animated mascot view: idles, blinks every couple of seconds
final class MascotView: NSView {
    private var blinkTimer: Timer?
    private let images = [Mascot.image(frame: 0), Mascot.image(frame: 1)]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.magnificationFilter = .nearest
        layer?.contentsGravity = .resizeAspect
        layer?.contents = images[0]

        blinkTimer = Timer.scheduledTimer(withTimeInterval: 2.6, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.layer?.contents = self.images[1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.layer?.contents = self.images[0]
            }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { blinkTimer?.invalidate() }
}
