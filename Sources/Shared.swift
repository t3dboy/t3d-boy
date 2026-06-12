// T3d Boy — shared helpers: ROM loading, framebuffer → CGImage

import Cocoa
import ImageIO
import UniformTypeIdentifiers

enum ROMLoader {
    static func romFiles(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["gb", "gbc", "zip"].contains($0.pathExtension.lowercased()) }
            .sorted {
                $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent)
                    == .orderedAscending
            }
    }

    static func load(url: URL) throws -> [UInt8] {
        if url.pathExtension.lowercased() == "zip" {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("T3dBoy-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }

            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            p.arguments = ["-o", "-j", "-qq", url.path, "-d", tmp.path]
            try p.run()
            p.waitUntilExit()

            let files = try FileManager.default.contentsOfDirectory(
                at: tmp, includingPropertiesForKeys: nil)
            guard let gbFile = files.first(where: {
                ["gb", "gbc"].contains($0.pathExtension.lowercased())
            }) else {
                throw NSError(domain: "T3dBoy", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "No Game Boy ROM (.gb) found inside the zip."
                ])
            }
            return [UInt8](try Data(contentsOf: gbFile))
        }
        return [UInt8](try Data(contentsOf: url))
    }
}

func makeImage(from framebuffer: [UInt32]) -> CGImage? {
    var fb = framebuffer
    return fb.withUnsafeMutableBytes { ptr -> CGImage? in
        guard let ctx = CGContext(
            data: ptr.baseAddress,
            width: 160, height: 144,
            bitsPerComponent: 8, bytesPerRow: 160 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        return ctx.makeImage()
    }
}

@discardableResult
func writePNG(_ image: CGImage, to url: URL) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}
