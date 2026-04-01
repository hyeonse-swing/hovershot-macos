import Foundation

public struct RecordingEditMarker: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: TimeInterval
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        createdAt: Date = .now
    ) {
        self.id = id
        self.timestamp = timestamp
        self.createdAt = createdAt
    }
}

public struct RecordingMetadata: Codable, Equatable, Sendable {
    public var customTitle: String?
    public var sessionName: String?
    public var segmentIndex: Int?
    public var notes: String?
    public var isFavorite: Bool
    public var markers: [RecordingEditMarker]

    public init(
        customTitle: String? = nil,
        sessionName: String? = nil,
        segmentIndex: Int? = nil,
        notes: String? = nil,
        isFavorite: Bool = false,
        markers: [RecordingEditMarker] = []
    ) {
        self.customTitle = customTitle
        self.sessionName = sessionName
        self.segmentIndex = segmentIndex
        self.notes = notes
        self.isFavorite = isFavorite
        self.markers = markers
    }
}
