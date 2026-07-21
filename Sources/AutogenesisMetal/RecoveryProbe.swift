import AutogenesisCore
import Darwin
import Foundation
import MetalKit

enum RecoveryProbeError: LocalizedError {
    case invalidArgument(String)
    case timeout
    case recoveryNotObserved
    case rollbackExceeded(fault: UInt64, checkpoint: UInt64)

    var errorDescription: String? {
        switch self {
        case let .invalidArgument(message): message
        case .timeout: "Metal recovery probe timed out."
        case .recoveryNotObserved: "The synthetic completion fault did not produce a checkpoint recovery."
        case let .rollbackExceeded(fault, checkpoint):
            "Recovery from step \(fault) restored step \(checkpoint), exceeding the 1,199-step bound."
        }
    }
}

private final class RecoveryTelemetryBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = RendererRuntimeTelemetry.idle

    func store(_ telemetry: RendererRuntimeTelemetry) {
        lock.lock()
        value = telemetry
        lock.unlock()
    }

    func load() -> RendererRuntimeTelemetry {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

enum RecoveryProbeCLI {
    @MainActor
    static func run(arguments: ArraySlice<String>) throws {
        var targetStep: UInt64 = 2_640
        var faultStep: UInt64 = 1_800
        var allowConcurrent = false
        var simulateStall = false
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let option = arguments[index]
            if option == "--allow-concurrent" {
                allowConcurrent = true
                index = arguments.index(after: index)
                continue
            }
            if option == "--stall" {
                simulateStall = true
                index = arguments.index(after: index)
                continue
            }
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex,
                  let value = UInt64(arguments[valueIndex]) else {
                throw RecoveryProbeError.invalidArgument("Missing integer value for \(option).")
            }
            switch option {
            case "--steps": targetStep = value
            case "--fault-step": faultStep = value
            default: throw RecoveryProbeError.invalidArgument("Unknown option: \(option)")
            }
            index = arguments.index(after: valueIndex)
        }
        guard faultStep > 1_200, targetStep > faultStep else {
            throw RecoveryProbeError.invalidArgument(
                "Use --fault-step above 1200 and --steps above the fault step."
            )
        }
        let admissionLock = try ExperimentAdmissionLock.acquire(unless: allowConcurrent)
        defer { withExtendedLifetime(admissionLock) {} }

        let faultVariable = simulateStall
            ? "NUMI_SYNTHETIC_METAL_STALL_STEP"
            : "NUMI_SYNTHETIC_METAL_FAULT_STEP"
        setenv(faultVariable, String(faultStep), 1)
        defer { unsetenv(faultVariable) }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw EvolutionRendererError.noMetalDevice
        }
        let view = MTKView(frame: .zero, device: device)
        view.isPaused = true
        let renderer = try EvolutionRenderer(view: view)
        let telemetryBox = RecoveryTelemetryBox()
        renderer.onRuntimeTelemetry = { telemetryBox.store($0) }
        var settings = RendererSettings(
            isRunning: true,
            stepsPerFrame: 24,
            resourceFlux: 1,
            mutationScale: 1,
            transportScale: 1,
            mechanosensingGain: 1,
            barrierGain: 1,
            displayMode: 0,
            trackedAgentID: .max,
            cameraCenter: SIMD2<Float>(repeating: 0.5),
            cameraZoom: 1,
            worldScale: 1,
            addColonyPosition: SIMD2<Float>(repeating: 0.5),
            addColonyToken: 0,
            expansionToken: 0,
            resetToken: 1
        )
        renderer.update(settings: settings)
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            let telemetry = telemetryBox.load()
            if telemetry.scientificallyCommittedStep >= targetStep {
                settings.isRunning = false
                renderer.update(settings: settings)
                if telemetry.unfinishedCommandBuffers == 0 { break }
            } else {
                renderer.draw(in: view)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.002))
        }
        let telemetry = telemetryBox.load()
        guard telemetry.scientificallyCommittedStep >= targetStep else {
            throw RecoveryProbeError.timeout
        }
        guard telemetry.recoveryCount > 0,
              let restoredStep = telemetry.lastRestoredCheckpointStep else {
            throw RecoveryProbeError.recoveryNotObserved
        }
        guard faultStep - min(faultStep, restoredStep) <= 1_199 else {
            throw RecoveryProbeError.rollbackExceeded(
                fault: faultStep,
                checkpoint: restoredStep
            )
        }
        print(
            "recovery_probe_complete=1 committed_step=\(telemetry.scientificallyCommittedStep) " +
            "restored_step=\(restoredStep) recoveries=\(telemetry.recoveryCount) " +
            "queue=\(telemetry.unfinishedCommandBuffers)/\(telemetry.maximumCommandBuffers)"
        )
    }
}
