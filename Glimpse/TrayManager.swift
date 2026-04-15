import AppKit

/// Menu bar tray icon with dynamic menu.
/// Shows Screenshot, Chat, recent threads, Settings, Quit.
class TrayManager {
    private var statusItem: NSStatusItem?
    private var threadStore: ThreadStore?
    var settingsStore: SettingsStore?

    var onScreenshot: (() -> Void)?
    var onChat: (() -> Void)?
    var onSettings: (() -> Void)?
    var onOpenThread: ((String) -> Void)?

    func setup(threadStore: ThreadStore, settingsStore: SettingsStore) {
        self.threadStore = threadStore
        self.settingsStore = settingsStore

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            // Load tray icon — try bundle Resources, then dev path
            if let image = loadTrayIcon() {
                image.isTemplate = true  // adapts to light/dark menu bar
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            } else {
                button.title = "G"  // fallback text
                NSLog("[Tray] WARNING: tray-icon.png not found")
            }
        }

        refreshMenu()
        NSLog("[Tray] Status item installed")
    }

    func refreshMenu() {
        let menu = NSMenu()

        let shortcuts = settingsStore?.getShortcuts() ?? ["chat": "cmd+shift+x", "screenshot": "cmd+shift+z"]
        let ssOpt = settingsStore?.shortcutOption(for: shortcuts["screenshot"] ?? "cmd+shift+z")
        let chatOpt = settingsStore?.shortcutOption(for: shortcuts["chat"] ?? "cmd+shift+x")

        menu.addItem(makeItem("Screenshot", shortcut: ssOpt?.keyEquiv ?? "z", modMask: ssOpt?.modMask ?? [.command, .shift], action: #selector(screenshotAction)))
        menu.addItem(makeItem("Chat", shortcut: chatOpt?.keyEquiv ?? "x", modMask: chatOpt?.modMask ?? [.command, .shift], action: #selector(chatAction)))

        // Recent threads
        if let threads = threadStore?.getThreads(), !threads.isEmpty {
            menu.addItem(.separator())
            for thread in threads {
                let title = thread["title"] as? String ?? "Untitled"
                let id = thread["id"] as? String ?? ""
                let item = NSMenuItem(title: title, action: #selector(threadAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = id
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(makeItem("Settings...", shortcut: ",", action: #selector(settingsAction)))

        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Glimpse", shortcut: "q", action: #selector(quitAction)))

        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func screenshotAction() { onScreenshot?() }
    @objc private func chatAction() { onChat?() }
    @objc private func settingsAction() { onSettings?() }
    @objc private func quitAction() { NSApp.terminate(nil) }

    @objc private func threadAction(_ sender: NSMenuItem) {
        guard let threadId = sender.representedObject as? String else { return }
        onOpenThread?(threadId)
    }

    // MARK: - Helpers

    private func makeItem(_ title: String, shortcut: String, modMask: NSEvent.ModifierFlags = [], action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut)
        item.target = self
        if !modMask.isEmpty {
            item.keyEquivalentModifierMask = modMask
        }
        return item
    }

    private func loadTrayIcon() -> NSImage? {
        // Bundle path (production)
        if let url = Bundle.main.url(forResource: "tray-icon", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        // Dev fallback: icons/ directory relative to project root
        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = sourceDir.deletingLastPathComponent()
        let devPath = projectRoot.appendingPathComponent("icons/tray-icon.png")
        if let image = NSImage(contentsOf: devPath) {
            NSLog("[Tray] Loaded icon from dev path")
            return image
        }
        return nil
    }
}
