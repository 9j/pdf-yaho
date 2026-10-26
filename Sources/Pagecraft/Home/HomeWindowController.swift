import AppKit
import SwiftUI

/// Owns the single Home window.
@MainActor
final class HomeWindowController: NSObject {
    static let shared = HomeWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil { window = makeWindow() }
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.orderOut(nil) }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Home"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.minSize = CGSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false
        window.tabbingIdentifier = "PagecraftDocuments"
        window.tabbingMode = .preferred
        window.backgroundColor = .windowBackgroundColor

        let hosting = NSHostingView(rootView: HomeView())
        // The window owns its size; don't let SwiftUI's ideal size resize it.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setContentSize(CGSize(width: 1000, height: 640))
        window.center()
        return window
    }
}
