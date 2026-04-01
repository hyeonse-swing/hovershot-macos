import Foundation

public struct RecordingItem: Identifiable, Equatable, Sendable {
    public var id: String {
        url.path
    }

    public let url: URL
    public let title: String
    public let sessionName: String?
    public let segmentIndex: Int?
    public let createdAt: Date
    public let modifiedAt: Date
    public let fileSize: Int64
    public let duration: TimeInterval?
    public let notes: String?
    public let isFavorite: Bool
    public let markers: [RecordingEditMarker]

    public init(
        url: URL,
        title: String,
        sessionName: String?,
        segmentIndex: Int?,
        createdAt: Date,
        modifiedAt: Date,
        fileSize: Int64,
        duration: TimeInterval?,
        notes: String?,
        isFavorite: Bool,
        markers: [RecordingEditMarker]
    ) {
        self.url = url
        self.title = title
        self.sessionName = sessionName
        self.segmentIndex = segmentIndex
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.fileSize = fileSize
        self.duration = duration
        self.notes = notes
        self.isFavorite = isFavorite
        self.markers = markers
    }
}
