import AppKit
import Foundation

enum IconGeneratorError: Error {
    case missingSourceImage
    case missingOutputPath
    case pngEncodingFailed
    case sipsFailed(String)
    case icnsEncodingFailed
}

struct IconGenerator {
    let fileManager = FileManager.default

    func run() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            throw IconGeneratorError.missingOutputPath
        }

        let outputPath = arguments[1]
        let previewPath = arguments.count >= 3 ? arguments[2] : nil
        let debugIconsetPath = ProcessInfo.processInfo.environment["HOVERSHOT_DEBUG_ICONSET"]
        let outputURL = URL(fileURLWithPath: outputPath)
        let previewURL = previewPath.map(URL.init(fileURLWithPath:))

        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let iconsetURL = outputURL.deletingPathExtension().appendingPathExtension("iconset")
        try? fileManager.removeItem(at: iconsetURL)
        try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
        defer {
            if debugIconsetPath == nil {
                try? fileManager.removeItem(at: iconsetURL)
            }
        }

        let iconSizes: [(name: String, size: CGFloat, type: String)] = [
            ("icon_16x16.png", 16, "icp4"),
            ("icon_16x16@2x.png", 32, "ic11"),
            ("icon_32x32.png", 32, "icp5"),
            ("icon_32x32@2x.png", 64, "ic12"),
            ("icon_128x128.png", 128, "ic07"),
            ("icon_128x128@2x.png", 256, "ic13"),
            ("icon_256x256.png", 256, "ic08"),
            ("icon_256x256@2x.png", 512, "ic14"),
            ("icon_512x512.png", 512, "ic09"),
            ("icon_512x512@2x.png", 1024, "ic10")
        ]

        var iconEntries = Data()
        for (name, size, type) in iconSizes {
            let image = try makeImage(size: size)
            let destination = iconsetURL.appendingPathComponent(name)
            try writePNG(image: image, to: destination)
            try normalizePNG(at: destination)

            let pngData = try Data(contentsOf: destination)
            guard let entrySize = UInt32(exactly: pngData.count + 8) else {
                throw IconGeneratorError.icnsEncodingFailed
            }
            iconEntries.append(contentsOf: type.utf8)
            var bigEndianEntrySize = entrySize.bigEndian
            withUnsafeBytes(of: &bigEndianEntrySize) { iconEntries.append(contentsOf: $0) }
            iconEntries.append(pngData)
        }

        if let debugIconsetPath {
            let debugURL = URL(fileURLWithPath: debugIconsetPath)
            try? fileManager.removeItem(at: debugURL)
            try fileManager.copyItem(at: iconsetURL, to: debugURL)
        }

        if let previewURL {
            let previewImage = try makeImage(size: 1024)
            try fileManager.createDirectory(
                at: previewURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try writePNG(image: previewImage, to: previewURL)
        }

        guard let fileSize = UInt32(exactly: iconEntries.count + 8) else {
            throw IconGeneratorError.icnsEncodingFailed
        }
        var icnsData = Data("icns".utf8)
        var bigEndianFileSize = fileSize.bigEndian
        withUnsafeBytes(of: &bigEndianFileSize) { icnsData.append(contentsOf: $0) }
        icnsData.append(iconEntries)
        try icnsData.write(to: outputURL, options: .atomic)
    }

    private func writePNG(image: NSImage, to destination: URL) throws {
        let pixelWidth = Int(image.size.width.rounded())
        let pixelHeight = Int(image.size.height.rounded())

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw IconGeneratorError.pngEncodingFailed
        }

        bitmap.size = NSSize(width: pixelWidth, height: pixelHeight)

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            NSGraphicsContext.restoreGraphicsState()
            throw IconGeneratorError.pngEncodingFailed
        }
        NSGraphicsContext.current = context
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw IconGeneratorError.pngEncodingFailed
        }

        try pngData.write(to: destination)
    }

    private func normalizePNG(at url: URL) throws {
        let temporaryURL = url.deletingPathExtension().appendingPathExtension("normalized.png")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = ["-s", "format", "png", url.path, "--out", temporaryURL.path]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "sips failed"
            throw IconGeneratorError.sipsFailed(message)
        }

        try? fileManager.removeItem(at: url)
        try fileManager.moveItem(at: temporaryURL, to: url)
    }

    private func makeImage(size: CGFloat) throws -> NSImage {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Assets/HoverShotIcon.png")
        guard let image = NSImage(contentsOf: sourceURL) else {
            throw IconGeneratorError.missingSourceImage
        }
        image.size = NSSize(width: size, height: size)
        return image
    }
}

do {
    try IconGenerator().run()
} catch {
    fputs("generate-app-icon failed: \(error)\n", stderr)
    exit(1)
}
