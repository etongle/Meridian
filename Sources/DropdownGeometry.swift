import Foundation
import CoreGraphics

enum DropdownGeometry {
    static func frame(anchor: CGRect, visibleFrame: CGRect, size: CGSize) -> CGRect {
        let safe = visibleFrame.insetBy(dx: 8, dy: 8)
        let width = min(size.width, safe.width)
        let height = min(size.height, safe.height)
        let x = min(max(anchor.midX - width / 2, safe.minX), safe.maxX - width)
        let top = min(anchor.minY - 8, safe.maxY)
        let y = max(safe.minY, top - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
