import AppKit
import Darwin
import SwiftUI

final class NumiAutomataAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

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

@main
enum NumiAutomataEntrypoint {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments.dropFirst()
        guard arguments.first == "experiment" else {
            NumiAutomataApp.main()
            return
        }
        do {
            try HeadlessExperimentCLI.run(arguments: arguments.dropFirst())
        } catch {
            fputs("numi-experiment: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
