import Foundation
import CoreGraphics

enum DesktopLayout: String, Codable, CaseIterable, Identifiable {
    case horizontal, vertical, independent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .horizontal: return "横向排列"
        case .vertical: return "纵向排列"
        case .independent: return "独立时钟"
        }
    }
    var symbol: String {
        switch self {
        case .horizontal: return "rectangle.split.2x1"
        case .vertical: return "rectangle.split.1x2"
        case .independent: return "square.on.square"
        }
    }

    func panelIDs(for regionIDs: [String]) -> [String] {
        self == .independent && !regionIDs.isEmpty ? regionIDs : ["combined"]
    }

    func positionKey(for panelID: String) -> String {
        panelID == "combined" ? rawValue : "clock:\(panelID)"
    }
}

struct DesktopLayoutMetrics {
    let columns: Int
    let rows: Int
    let size: CGSize
    let contentHeight: CGFloat
    var needsScrolling: Bool { contentHeight > size.height - 36 }

    init(layout: DesktopLayout, clockCount: Int, availableSize: CGSize) {
        guard clockCount > 0 else {
            columns = 1; rows = 0; contentHeight = 74
            size = CGSize(width: 360, height: 110)
            return
        }
        let count = layout == .independent ? 1 : clockCount
        let fitting = max(1, Int((availableSize.width - 32) / 180))
        columns = layout == .vertical ? 1 : min(count, fitting)
        rows = Int(ceil(Double(count) / Double(columns)))
        contentHeight = CGFloat(rows * 174)
        size = CGSize(width: CGFloat(max(220, columns * 180)),
            height: min(36 + contentHeight, max(110, availableSize.height - 32)))
    }
}
