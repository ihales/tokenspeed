import AppKit
import SwiftUI

@main
@MainActor
enum TokenSpeedApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = MonitorStore()
    private var menuBar: MenuBarController?
    private var settingsWindow: NSWindow?
    private var polling: Task<Void, Never>?
    private var localPolling: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        menuBar = MenuBarController(store: store, showSettings: { [weak self] in
            self?.showSettings()
        })
        polling = Task { await store.poll() }
        localPolling = Task { await store.pollPinnedLocal() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        polling?.cancel()
        localPolling?.cancel()
    }

    @objc private func showSettings() {
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.allowUserInteraction]
        let panes: [(String, String, AnyView)] = [
            ("General", "gearshape", AnyView(GeneralSettingsView())),
            ("Models", "gauge.with.dots.needle.67percent", AnyView(ModelSettingsView(store: store))),
            ("Badge Rules", "circle.badge.checkmark", AnyView(RuleSettingsView(store: store)))
        ]
        for (label, symbol, view) in panes {
            let host = NSHostingController(rootView: view)
            host.sizingOptions = []
            host.title = label
            let item = NSTabViewItem(viewController: host)
            item.label = label
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            tabs.addTabViewItem(item)
        }
        tabs.selectedTabViewItemIndex = 1

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 680, height: 440)
        window.setContentSize(NSSize(width: 760, height: 540))
        window.setFrameAutosaveName("TokenSpeedSettings")
        if window.frameAutosaveName.isEmpty || !window.setFrameUsingName("TokenSpeedSettings") {
            window.center()
        }
        return window
    }

    private func installMainMenu() {
        let appMenu = NSMenu(title: "TokenSpeed")
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Quit TokenSpeed", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let menu = NSMenu()
        for submenu in [appMenu, editMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            menu.addItem(item)
        }
        NSApp.mainMenu = menu
    }
}
