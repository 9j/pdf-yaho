import AppKit

/// Compatibility shim: the Welcome window is now the Home window (see `Home/`).
@MainActor
final class WelcomeWindowController {
    static let shared = WelcomeWindowController()

    func show() { HomeWindowController.shared.show() }
    func close() { HomeWindowController.shared.close() }
}
