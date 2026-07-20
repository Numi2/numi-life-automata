import AppKit
import Darwin
import SwiftUI

@MainActor
final class NumiAutomataAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        scheduleSimulationWindowPresentation()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        scheduleSimulationWindowPresentation()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func presentSimulationWindow() {
        for window in NSApplication.shared.windows {
            window.isRestorable = false
            window.makeKeyAndOrderFront(nil)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func scheduleSimulationWindowPresentation() {
        for delay in [0.0, 0.15, 0.60] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.presentSimulationWindow()
            }
        }
    }
}

struct NumiAutomataApp: App {
    @NSApplicationDelegateAdaptor(NumiAutomataAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Numi Automata") {
            ContentView()
        }
        .restorationBehavior(.disabled)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 820)
    }
}

@main
enum NumiAutomataEntrypoint {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments.dropFirst()
        guard let command = arguments.first else {
            NumiAutomataApp.main()
            return
        }
        do {
            switch command {
            case "experiment":
                try HeadlessExperimentCLI.run(arguments: arguments.dropFirst())
            case "causal-experiment":
                try PairedCausalExperimentCLI.run(arguments: arguments.dropFirst())
            default:
                NumiAutomataApp.main()
            }
        } catch {
            fputs("numi-experiment: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
