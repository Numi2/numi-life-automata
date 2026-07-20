import AppKit
import SwiftUI

final class NumiAutomataAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct NumiAutomataApp: App {
    @NSApplicationDelegateAdaptor(NumiAutomataAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Numi Automata") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 820)
    }
}
