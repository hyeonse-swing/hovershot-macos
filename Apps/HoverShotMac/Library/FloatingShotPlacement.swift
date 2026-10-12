import CoreGraphics
import Foundation

package enum FloatingShotPlacement {
    package enum Layout {
        package static let horizontalChrome: CGFloat = 24
        package static let verticalChrome: CGFloat = 74
        package static let outerMargin: CGFloat = 40
        package static let maxWidthRatio: CGFloat = 0.36
        package static let maxHeightRatio: CGFloat = 0.55
        package static let maxWidthCap: CGFloat = 820
        package static let maxHeightCap: CGFloat = 760
        package static let minimumImageWidth: CGFloat = 48
        package static let minimumImageHeight: CGFloat = 48
    }

    package static func defaultInitialFrame(for imageSize: CGSize, visibleFrame: CGRect) -> CGRect {
        let maxImageWidth = min(visibleFrame.width * Layout.maxWidthRatio, Layout.maxWidthCap)
        let maxImageHeight = min(visibleFrame.height * Layout.maxHeightRatio, Layout.maxHeightCap)
        let fittedSize = fittedImageSize(
            imageSize,
            maxSize: CGSize(width: maxImageWidth, height: maxImageHeight)
        )

        let windowWidth = fittedSize.width + Layout.horizontalChrome
        let windowHeight = fittedSize.height + Layout.verticalChrome
        let origin = CGPoint(
            x: min(visibleFrame.minX + Layout.outerMargin, max(visibleFrame.maxX - windowWidth - Layout.outerMargin, visibleFrame.minX + 16)),
            y: max(visibleFrame.maxY - windowHeight - Layout.outerMargin, visibleFrame.minY + 16)
        )

        return CGRect(origin: origin, size: CGSize(width: windowWidth, height: windowHeight)).integral
    }

    package static func fittedImageSize(_ imageSize: CGSize, maxSize: CGSize) -> CGSize {
        let baseWidth = max(imageSize.width, 1)
        let baseHeight = max(imageSize.height, 1)
        let widthScale = maxSize.width / baseWidth
        let heightScale = maxSize.height / baseHeight
        let scale = min(widthScale, heightScale, 1)

        return CGSize(
            width: max((baseWidth * scale).rounded(), Layout.minimumImageWidth),
            height: max((baseHeight * scale).rounded(), Layout.minimumImageHeight)
        )
    }
}
