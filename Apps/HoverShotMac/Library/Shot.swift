import CoreGraphics
import Foundation

public enum ShotVisibilityMode: String, Codable, Sendable, CaseIterable {
    case everywhere
    case currentSpace
    case currentApp
}

public enum ShotAnnotationStyle: String, Codable, Sendable, CaseIterable {
    case highlight
    case redaction
    case arrow
    case step
    case text

    public var displayName: String {
        switch self {
        case .highlight:
            return "Highlight"
        case .redaction:
            return "Redact"
        case .arrow:
            return "Arrow"
        case .step:
            return "Step"
        case .text:
            return "Text"
        }
    }
}

public struct ShotPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }

    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

public struct ShotRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

public struct FloatingShotState: Codable, Equatable, Sendable {
    public var frame: ShotRect?
    public var opacity: Double
    public var ignoresMouseEvents: Bool
    public var isVisible: Bool
    public var visibilityMode: ShotVisibilityMode

    public init(
        frame: ShotRect? = nil,
        opacity: Double = 1.0,
        ignoresMouseEvents: Bool = false,
        isVisible: Bool = true,
        visibilityMode: ShotVisibilityMode = .everywhere
    ) {
        self.frame = frame
        self.opacity = opacity
        self.ignoresMouseEvents = ignoresMouseEvents
        self.isVisible = isVisible
        self.visibilityMode = visibilityMode
    }
}

public struct ShotAnnotation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var style: ShotAnnotationStyle
    public var rect: ShotRect
    public var startPoint: ShotPoint?
    public var endPoint: ShotPoint?
    public var label: String?

    public init(
        id: UUID = UUID(),
        style: ShotAnnotationStyle,
        rect: ShotRect,
        startPoint: ShotPoint? = nil,
        endPoint: ShotPoint? = nil,
        label: String? = nil
    ) {
        self.id = id
        self.style = style
        self.rect = rect
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.label = label
    }
}

public struct Shot: Identifiable, Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case assetFileName
        case recognizedText
        case annotations
        case floatingState
        case notes
        case tags
        case isFavorite
    }

    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var assetFileName: String
    public var recognizedText: String?
    public var annotations: [ShotAnnotation]
    public var floatingState: FloatingShotState
    public var notes: String?
    public var tags: [String]
    public var isFavorite: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        assetFileName: String,
        recognizedText: String? = nil,
        annotations: [ShotAnnotation] = [],
        floatingState: FloatingShotState = FloatingShotState(),
        notes: String? = nil,
        tags: [String] = [],
        isFavorite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.assetFileName = assetFileName
        self.recognizedText = recognizedText
        self.annotations = annotations
        self.floatingState = floatingState
        self.notes = notes
        self.tags = tags
        self.isFavorite = isFavorite
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        assetFileName = try container.decode(String.self, forKey: .assetFileName)
        recognizedText = try container.decodeIfPresent(String.self, forKey: .recognizedText)
        annotations = try container.decodeIfPresent([ShotAnnotation].self, forKey: .annotations) ?? []
        floatingState = try container.decode(FloatingShotState.self, forKey: .floatingState)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(assetFileName, forKey: .assetFileName)
        try container.encodeIfPresent(recognizedText, forKey: .recognizedText)
        try container.encode(annotations, forKey: .annotations)
        try container.encode(floatingState, forKey: .floatingState)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(tags, forKey: .tags)
        try container.encode(isFavorite, forKey: .isFavorite)
    }
}
