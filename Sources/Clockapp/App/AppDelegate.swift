import AppKit
import SwiftUI
import Combine

/// Owns the status-bar item, the popover panel, and the settings window.
/// Using NSStatusItem + NSPopover (instead of SwiftUI's MenuBarExtra) keeps the
/// panel consistently anchored *centered under the icon*, even as the icon's
/// width changes between idle and running.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    /// Closes the panel when the user clicks anywhere outside the app.
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        state = AppState()
        state.openSettings = { [weak self] in self?.showSettings() }

        setupMainMenu()
        setupStatusItem()
        setupPopover()

        // Keep the menubar title/icon (and window titles) in sync with the state.
        state.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateStatusButton()
                    self?.settingsWindow?.title = self?.state.t(.settingsWindowTitle) ?? ""
                }
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.shutdownMCP() // don't orphan the MCP child process
    }

    // MARK: - Main menu (enables ⌘X/⌘C/⌘V in text fields even for an accessory app)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // Application menu.
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Réglages…", action: #selector(openSettingsMenu), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Masquer", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quitter Clockapp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit menu — standard responder-chain actions carry the paste shortcut.
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Édition")
        editItem.submenu = editMenu
        // undo:/redo: have no public declaration to reference with #selector.
        editMenu.addItem(withTitle: "Annuler", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Rétablir", action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettingsMenu() { showSettings() }

    private func removeOutsideClickMonitor() {
        if let m = outsideClickMonitor {
            NSEvent.removeMonitor(m)
            outsideClickMonitor = nil
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.imagePosition = .imageLeading
            // Fixed-width digits so the ticking time doesn't jiggle the menubar item.
            button.font = NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize(for: .regular), weight: .regular)
        }
        updateStatusButton()
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        let tracking = state.isTracking
        let image = NSImage(systemSymbolName: tracking ? "timer" : "timer.circle",
                            accessibilityDescription: "Clockapp")
        image?.isTemplate = true
        button.image = image
        button.title = tracking
            ? " " + Format.clock(state.elapsed, seconds: state.settings.showSecondsInMenuBar)
            : ""
    }

    // MARK: - Popover

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let hosting = NSHostingController(rootView: MenuContentView().environmentObject(state))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            startOutsideClickMonitor()
            state.onPanelOpened()
        }
    }

    private func startOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        // Global monitor fires only for events delivered to *other* apps / the desktop,
        // so clicks inside our panel or on the status item are never caught here.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    // MARK: - Settings window

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView().environmentObject(state))
            let win = NSWindow(contentViewController: hosting)
            win.title = state.t(.settingsWindowTitle)
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.setContentSize(NSSize(width: 660, height: 520))
            win.isReleasedWhenClosed = false
            win.center()
            settingsWindow = win
        }
        settingsWindow?.title = state.t(.settingsWindowTitle)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: NSPopoverDelegate {
    // Centralized cleanup: runs no matter how the panel closed
    // (outside click, toggle, or opening settings).
    func popoverDidClose(_ notification: Notification) {
        removeOutsideClickMonitor()
    }
}
