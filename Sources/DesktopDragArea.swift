import AppKit
import SwiftUI

/// Supplies the native hand cursor and tooltip; DesktopPanel handles title-bar mouse events.
struct DesktopDragArea: NSViewRepresentable {
    let enabled: Bool
    let hint: String

    func makeNSView(context: Context) -> DragView { DragView() }

    func updateNSView(_ view: DragView, context: Context) {
        view.enabled = enabled
        view.toolTip = hint
        view.window?.invalidateCursorRects(for: view)
    }

    final class DragView: NSView {
        var enabled = true
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() {
            if enabled { addCursorRect(bounds, cursor: .openHand) }
        }
    }
}
