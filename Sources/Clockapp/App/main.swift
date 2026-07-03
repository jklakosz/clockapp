import AppKit

// Pure AppKit entry point: a menubar-only app driven by AppDelegate
// (NSStatusItem + NSPopover) so the panel is always anchored under the icon.
// Program entry is always the main thread, so we can assume MainActor isolation.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run() // blocks until the app terminates, keeping `delegate` alive
}
