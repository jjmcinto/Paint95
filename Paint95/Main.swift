//Main.swift
import Cocoa

@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)   // show normal app UI
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
