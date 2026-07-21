import AppKit
import Darwin
import SwiftUI

@MainActor
final class NumiAutomataAppDelegate: NSObject, NSApplicationDelegate {
    private var simulationWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        presentSimulationWindow()
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
        if simulationWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1240, height: 820),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Numi Automata"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isRestorable = false
            window.minSize = NSSize(width: 900, height: 620)
            window.contentView = NSHostingView(rootView: ContentView())
            window.center()
            simulationWindow = window
        }
        simulationWindow?.makeKeyAndOrderFront(nil)
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

@main
enum NumiAutomataEntrypoint {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments.dropFirst()
        guard let command = arguments.first else {
            runApplication()
            return
        }
        do {
            switch command {
            case "experiment":
                try HeadlessExperimentCLI.run(arguments: arguments.dropFirst())
            case "causal-experiment":
                try PairedCausalExperimentCLI.run(arguments: arguments.dropFirst())
            case "recovery-probe":
                try RecoveryProbeCLI.run(arguments: arguments.dropFirst())
            default:
                runApplication()
            }
        } catch {
            fputs("numi-experiment: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    @MainActor
    private static func runApplication() {
        let application = NSApplication.shared
        let delegate = NumiAutomataAppDelegate()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
