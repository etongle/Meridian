import Foundation
import CoreGraphics

enum DesktopGeometry {
    static let margin: CGFloat = 16
    static let snapDistance: CGFloat = 24

    static func screen(for frame: CGRect, in screens: [CGRect]) -> CGRect? {
        screens.max { lhs, rhs in
            let left = frame.intersection(lhs)
            let right = frame.intersection(rhs)
            let leftArea = left.isNull ? 0 : left.width * left.height
            let rightArea = right.isNull ? 0 : right.width * right.height
            if leftArea != rightArea { return leftArea < rightArea }
            return distance(frame, lhs) > distance(frame, rhs)
        }
    }

    static func origin(for frame: CGRect, in screen: CGRect, snap: Bool) -> CGPoint {
        let safe = screen.insetBy(dx: margin, dy: margin)
        let maxX = max(safe.minX, safe.maxX - frame.width)
        let maxY = max(safe.minY, safe.maxY - frame.height)
        var x = min(max(frame.minX, safe.minX), maxX)
        var y = min(max(frame.minY, safe.minY), maxY)
        if snap {
            x = snapped(x, low: safe.minX, high: maxX)
            y = snapped(y, low: safe.minY, high: maxY)
        }
        return CGPoint(x: x, y: y)
    }

    private static func snapped(_ value: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        let edge = abs(value - low) <= abs(value - high) ? low : high
        return abs(value - edge) <= snapDistance ? edge : value
    }

    private static func distance(_ frame: CGRect, _ screen: CGRect) -> CGFloat {
        let x = max(screen.minX - frame.midX, 0, frame.midX - screen.maxX)
        let y = max(screen.minY - frame.midY, 0, frame.midY - screen.maxY)
        return x * x + y * y
    }
}
