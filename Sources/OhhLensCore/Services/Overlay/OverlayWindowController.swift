import AppKit
import SwiftUI

@MainActor
public final class OverlayWindowController {
    private var window: NSWindow?

    public init() {}

    public func present<Content: View>(@ViewBuilder content: () -> Content) {
        if let window {
            window.contentView = NSHostingView(rootView: content())
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 240, y: 220, width: 720, height: 148),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content())
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
