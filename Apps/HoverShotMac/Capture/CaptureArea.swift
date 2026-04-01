import AppKit
import Foundation
import Library

public struct CaptureArea: Codable, Equatable, Sendable {
    public var displayID: UInt32
    public var rect: ShotRect

    public init(displayID: UInt32, rect: ShotRect) {
        self.displayID = displayID
        self.rect = rect
    }
}

extension NSScreen {
    var screenHoveringDisplayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
