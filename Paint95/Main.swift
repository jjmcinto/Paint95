// Main.swift
import Cocoa

@main
final class Main {
    // Hold a strong reference so the delegate isn't deallocated
    private static var appDelegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared

        let delegate = AppDelegate()
        Main.appDelegate = delegate          // <-- keep strong ref
        app.delegate = delegate              // NSApplication holds this weakly

        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)

        app.run()

        // (Optional) clear on exit
        Main.appDelegate = nil
    }
}
