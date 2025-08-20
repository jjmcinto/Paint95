// MenuBuilder.swift
import AppKit

final class MenuBuilder {

    func makeMainMenu() -> NSMenu {
        let main = NSMenu(title: "MainMenu")

        // --- App (Paint95) menu ---
        let appName = ProcessInfo.processInfo.processName
        let appMenuItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: appName)
        appMenuItem.submenu = appMenu
        main.addItem(appMenuItem)

        // Standard items (About / Hide / Quit)
        appMenu.addItem(NSMenuItem(
            title: "About \(appName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Helper to add a titled top-level item with a disabled "<empty>"
        func addEmptyTopLevelMenu(title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            let placeholder = NSMenuItem(title: "<empty>", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            submenu.addItem(placeholder)
            item.submenu = submenu
            main.addItem(item)
        }

        addEmptyTopLevelMenu(title: "File")
        addEmptyTopLevelMenu(title: "Edit")
        addEmptyTopLevelMenu(title: "View")
        addEmptyTopLevelMenu(title: "Image")
        addEmptyTopLevelMenu(title: "Options")
        addEmptyTopLevelMenu(title: "Help")

        return main
    }
}
