import AppKit
import Foundation

public extension Notification.Name {
    static let shotStoreDidChange = Notification.Name("HoverShot.shotStoreDidChange")
}

public final class ShotStore {
    public enum StoreError: Error {
        case missingImageData
        case shotNotFound(UUID)
    }

    private let fileManager: FileManager
    private let baseDirectoryURL: URL
    private let metadataURL: URL
    private let assetsDirectoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let notificationCenter: NotificationCenter

    public init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.fileManager = fileManager
        self.baseDirectoryURL = baseDirectoryURL ?? Self.defaultBaseDirectoryURL(fileManager: fileManager)
        self.metadataURL = self.baseDirectoryURL.appendingPathComponent("shots.json")
        self.assetsDirectoryURL = self.baseDirectoryURL.appendingPathComponent("Assets", isDirectory: true)
        self.notificationCenter = notificationCenter

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        try? prepareStorage()
    }

    public func loadShots() throws -> [Shot] {
        try prepareStorage()

        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return []
        }

        let data = try Data(contentsOf: metadataURL)
        let shots = try decoder.decode([Shot].self, from: data)
        return shots.sorted { $0.createdAt < $1.createdAt }
    }

    public func loadShot(withID shotID: UUID) throws -> Shot {
        let shots = try loadShots()
        guard let shot = shots.first(where: { $0.id == shotID }) else {
            throw StoreError.shotNotFound(shotID)
        }

        return shot
    }

    public func upsert(_ shot: Shot) throws {
        var shots = try loadShots()

        if let index = shots.firstIndex(where: { $0.id == shot.id }) {
            shots[index] = shot
        } else {
            shots.append(shot)
        }

        try save(shots: shots)
    }

    public func save(shots: [Shot]) throws {
        try prepareStorage()
        let data = try encoder.encode(shots.sorted { $0.createdAt < $1.createdAt })
        try data.write(to: metadataURL, options: .atomic)
        postStoreDidChangeNotification()
    }

    public func assetURL(for shot: Shot) -> URL {
        assetsDirectoryURL.appendingPathComponent(shot.assetFileName)
    }

    public func loadImage(for shot: Shot) -> NSImage? {
        let url = assetURL(for: shot)
        return NSImage(contentsOf: url)
    }

    public func loadRenderedImage(for shot: Shot) -> NSImage? {
        guard let image = loadImage(for: shot) else {
            return nil
        }

        return ShotRenderer.renderedImage(for: shot, using: image)
    }

    @discardableResult
    public func persist(image: NSImage, for shotID: UUID) throws -> String {
        try prepareStorage()

        guard let data = pngData(from: image) else {
            throw StoreError.missingImageData
        }

        let fileName = "\(shotID.uuidString.lowercased()).png"
        let destinationURL = assetsDirectoryURL.appendingPathComponent(fileName)
        try data.write(to: destinationURL, options: .atomic)
        return fileName
    }

    public func createDemoShot(index: Int) throws -> Shot {
        let title = "Demo Shot \(index)"
        let image = DemoShotFactory.makeImage(
            title: title,
            subtitle: "Phase 0 foundation for HoverShot on macOS"
        )
        return try createShot(image: image, title: title)
    }

    public func createShot(
        image: NSImage,
        title: String,
        recognizedText: String? = nil,
        floatingState: FloatingShotState = FloatingShotState()
    ) throws -> Shot {
        let shotID = UUID()
        let assetFileName = try persist(image: image, for: shotID)
        let shot = Shot(
            id: shotID,
            title: title,
            assetFileName: assetFileName,
            recognizedText: recognizedText,
            floatingState: floatingState
        )

        try upsert(shot)
        return shot
    }

    public func createTextShot(
        text: String,
        title: String,
        floatingState: FloatingShotState = FloatingShotState()
    ) throws -> Shot {
        let image = TextShotFactory.makeImage(text: text, title: title)
        return try createShot(
            image: image,
            title: title,
            recognizedText: text,
            floatingState: floatingState
        )
    }

    public func updateFloatingState(for shotID: UUID, to state: FloatingShotState) throws {
        var shots = try loadShots()
        guard let index = shots.firstIndex(where: { $0.id == shotID }) else {
            throw StoreError.shotNotFound(shotID)
        }

        shots[index].floatingState = state
        try save(shots: shots)
    }

    public func updateRecognizedText(for shotID: UUID, to recognizedText: String?) throws {
        var shots = try loadShots()
        guard let index = shots.firstIndex(where: { $0.id == shotID }) else {
            throw StoreError.shotNotFound(shotID)
        }

        shots[index].recognizedText = recognizedText
        try save(shots: shots)
    }

    public func updateAnnotations(for shotID: UUID, to annotations: [ShotAnnotation]) throws {
        var shots = try loadShots()
        guard let index = shots.firstIndex(where: { $0.id == shotID }) else {
            throw StoreError.shotNotFound(shotID)
        }

        shots[index].annotations = annotations
        try save(shots: shots)
    }

    public func updateMetadata(
        for shotID: UUID,
        title: String,
        notes: String?,
        tags: [String],
        isFavorite: Bool
    ) throws {
        var shots = try loadShots()
        guard let index = shots.firstIndex(where: { $0.id == shotID }) else {
            throw StoreError.shotNotFound(shotID)
        }

        shots[index].title = normalizedTitle(title, fallback: shots[index].title)
        shots[index].notes = normalizedNotes(notes)
        shots[index].tags = normalizedTags(tags)
        shots[index].isFavorite = isFavorite
        try save(shots: shots)
    }

    @discardableResult
    public func deleteShot(withID shotID: UUID) throws -> Shot {
        var shots = try loadShots()
        guard let index = shots.firstIndex(where: { $0.id == shotID }) else {
            throw StoreError.shotNotFound(shotID)
        }

        let shot = shots.remove(at: index)
        let assetURL = assetURL(for: shot)
        if fileManager.fileExists(atPath: assetURL.path) {
            try fileManager.removeItem(at: assetURL)
        }

        try save(shots: shots)
        return shot
    }

    private func prepareStorage() throws {
        try fileManager.createDirectory(
            at: baseDirectoryURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: assetsDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private func pngData(from image: NSImage) -> Data? {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    private static func defaultBaseDirectoryURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return appSupport
            .appendingPathComponent("HoverShot", isDirectory: true)
    }

    private func postStoreDidChangeNotification() {
        notificationCenter.post(name: .shotStoreDidChange, object: self)
    }

    private func normalizedNotes(_ notes: String?) -> String? {
        guard let notes else {
            return nil
        }

        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedTitle(_ title: String, fallback: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                continue
            }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else {
                continue
            }

            normalized.append(trimmed)
        }

        return normalized
    }
}
