import CoreGraphics

enum CapturePlacement {
    struct Display {
        let id: CGDirectDisplayID
        let bounds: CGRect
    }

    static func displayID(for windowFrame: CGRect, displays: [Display]) -> CGDirectDisplayID? {
        guard !windowFrame.isEmpty else { return nil }

        var selectedID: CGDirectDisplayID?
        var largestOverlap: CGFloat = 0
        for display in displays {
            let overlap = windowFrame.intersection(display.bounds)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > largestOverlap {
                largestOverlap = area
                selectedID = display.id
            }
        }
        return selectedID
    }
}
