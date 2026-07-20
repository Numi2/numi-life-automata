import Foundation
import MetalKit
import Darwin

enum HeadlessExperimentError: LocalizedError {
    case invalidArgument(String)
    case invariantViolation(step: UInt64, names: [String])
    case missingExperimentSample(String)
    case pairedBaselineMismatch(seed: UInt32)
    case output(String)

    var errorDescription: String? {
        switch self {
        case let .invalidArgument(message): message
        case let .invariantViolation(step, names):
            "Invariant failure at simulation step \(step): \(names.joined(separator: ", "))"
        case let .missingExperimentSample(message): message
        case let .pairedBaselineMismatch(seed):
            "Control and treatment observations differ before intervention for seed \(seed)."
        case let .output(message): message
        }
    }
}

struct MechanosensingSchedule: Codable, Sendable, Equatable {
    var baselineGain: Float = 1
    var interventionStep: UInt64?
    var postInterventionGain: Float?

    func gain(forCompletedStep step: UInt64) -> Float {
        guard let interventionStep,
              let postInterventionGain,
              step > interventionStep else { return baselineGain }
        return postInterventionGain
    }
}

struct HeadlessExperimentConfiguration: Codable, Sendable {
    var seed: UInt32 = 1
    var steps: UInt64 = 1_000_000
    var batchSize: Int = 32
    var sampleInterval: UInt64 = 1_200
    var auditInterval: UInt64 = 1
    var quantumStride: UInt64 = 3
    var strictInvariants = true
    var mechanosensing = MechanosensingSchedule()
    var outputPath = ""

    static let usage = """
    Usage: NumiAutomata experiment [options]

      --steps N             Simulation steps (default: 1000000)
      --seed N              Deterministic UInt32 seed (default: 1)
      --batch N             Steps encoded per command buffer (default: 32)
      --sample-every N      JSONL sample interval (default: 1200)
      --audit-every N       GPU invariant interval (default: 1)
      --quantum-stride N    Biological steps per quantum step (default: 3)
      --mechanosensing-gain X  Baseline mechanics input gain in 0...2 (default: 1)
      --intervention-step N    Last baseline step before a scheduled gain change
      --post-mechanosensing-gain X  Gain after --intervention-step
      --output PATH         JSONL output path
      --no-strict           Record invariant failures without stopping
      --help                Show this help
    """

    static func parse(_ arguments: ArraySlice<String>) throws -> Self {
        var configuration = Self()
        var index = arguments.startIndex
        func value(after option: String) throws -> String {
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else {
                throw HeadlessExperimentError.invalidArgument("Missing value for \(option).")
            }
            index = valueIndex
            return arguments[valueIndex]
        }
        while index < arguments.endIndex {
            let argument = arguments[index]
            switch argument {
            case "--steps":
                guard let value = UInt64(try value(after: argument)), value > 0 else {
                    throw HeadlessExperimentError.invalidArgument("--steps must be positive.")
                }
                configuration.steps = value
            case "--seed":
                guard let value = UInt32(try value(after: argument)) else {
                    throw HeadlessExperimentError.invalidArgument("--seed must fit UInt32.")
                }
                configuration.seed = value
            case "--batch":
                guard let value = Int(try value(after: argument)), (1...256).contains(value) else {
                    throw HeadlessExperimentError.invalidArgument("--batch must be in 1...256.")
                }
                configuration.batchSize = value
            case "--sample-every":
                guard let value = UInt64(try value(after: argument)), value > 0 else {
                    throw HeadlessExperimentError.invalidArgument("--sample-every must be positive.")
                }
                configuration.sampleInterval = value
            case "--audit-every":
                guard let value = UInt64(try value(after: argument)), value > 0 else {
                    throw HeadlessExperimentError.invalidArgument("--audit-every must be positive.")
                }
                configuration.auditInterval = value
            case "--quantum-stride":
                guard let value = UInt64(try value(after: argument)), value > 0 else {
                    throw HeadlessExperimentError.invalidArgument("--quantum-stride must be positive.")
                }
                configuration.quantumStride = value
            case "--mechanosensing-gain":
                guard let value = Float(try value(after: argument)),
                      value.isFinite,
                      (0...2).contains(value) else {
                    throw HeadlessExperimentError.invalidArgument(
                        "--mechanosensing-gain must be finite and in 0...2."
                    )
                }
                configuration.mechanosensing.baselineGain = value
            case "--intervention-step":
                guard let value = UInt64(try value(after: argument)), value > 0 else {
                    throw HeadlessExperimentError.invalidArgument(
                        "--intervention-step must be positive."
                    )
                }
                configuration.mechanosensing.interventionStep = value
            case "--post-mechanosensing-gain":
                guard let value = Float(try value(after: argument)),
                      value.isFinite,
                      (0...2).contains(value) else {
                    throw HeadlessExperimentError.invalidArgument(
                        "--post-mechanosensing-gain must be finite and in 0...2."
                    )
                }
                configuration.mechanosensing.postInterventionGain = value
            case "--output":
                configuration.outputPath = try value(after: argument)
            case "--no-strict":
                configuration.strictInvariants = false
            case "--help", "-h":
                print(usage)
                exit(EXIT_SUCCESS)
            default:
                throw HeadlessExperimentError.invalidArgument("Unknown option: \(argument)")
            }
            index = arguments.index(after: index)
        }
        let hasInterventionStep = configuration.mechanosensing.interventionStep != nil
        let hasPostGain = configuration.mechanosensing.postInterventionGain != nil
        guard hasInterventionStep == hasPostGain else {
            throw HeadlessExperimentError.invalidArgument(
                "--intervention-step and --post-mechanosensing-gain must be supplied together."
            )
        }
        if let interventionStep = configuration.mechanosensing.interventionStep,
           interventionStep >= configuration.steps {
            throw HeadlessExperimentError.invalidArgument(
                "--intervention-step must be smaller than --steps."
            )
        }
        if configuration.outputPath.isEmpty {
            let formatter = ISO8601DateFormatter()
            let timestamp = formatter.string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            configuration.outputPath = FileManager.default.currentDirectoryPath +
                "/Experiments/seed-\(configuration.seed)-\(timestamp).jsonl"
        }
        return configuration
    }
}

struct ExperimentHeader: Codable {
    let schemaVersion: Int
    let startedAt: String
    let device: String
    let configuration: HeadlessExperimentConfiguration
}

struct ExperimentEvent: Codable {
    let sequence: UInt32
    let type: String
    let step: UInt32
    let birthID: UInt32
    let parentBirthID: UInt32?
    let generation: UInt32
    let genomeHash: UInt32
    let topologyHash: UInt32
    let mutationDistance: Float
    let resonanceFrequency: Float
    let energy: Float
    let morphology: [Float]
}

struct ExperimentInvariantReport: Codable, Sendable {
    let flags: UInt32
    let names: [String]
    let firstFailureStep: UInt32?
    let auditCount: UInt32
    let contactMomentumViolations: UInt32
    let energyDriftViolations: UInt32
    let staleProgramViolations: UInt32
    let referenceCountViolations: UInt32
    let orphanedJunctionViolations: UInt32
    let invalidMembraneViolations: UInt32
    let disconnectedOwnershipViolations: UInt32
    let maximumContactMomentumResidual: UInt32
    let maximumEnergyResidual: Double
}

struct ExperimentSample: Codable {
    let step: UInt64
    let generation: UInt32
    let elapsedSeconds: Double
    let stepsPerSecond: Double
    let livingOrganisms: Int
    let livingCells: Int
    let births: UInt64
    let deaths: UInt64
    let fissions: UInt64
    let fusions: UInt64
    let activePrograms: UInt32
    let livingProgramReferences: UInt32
    let recycledProgramClaims: UInt64
    let activeJunctions: UInt32
    let meanJunctionLoad: Double
    let trophicGain: Double
    let trophicLoss: Double
    let energyResidual: Double
    let meanCellsPerOrganism: Double
    let meanTissueRadius: Double
    let meanShapeIndex: Double
    let meanElongation: Double
    let meanExposedMembraneLength: Double
    let meanCellATP: Double
    let meanCellIntegrity: Double
    let meanCellStress: Double
    let meanMembraneVoltage: Double
    let meanCalciumActivity: Double
    let meanERKActivity: Double
    let dividingCellFraction: Double
    let meanCellTraction: Double
    let meanFrequencyMatch: Double
    let invariantReport: ExperimentInvariantReport
}

struct ExperimentSummary: Codable {
    let completed: Bool
    let step: UInt64
    let elapsedSeconds: Double
    let meanStepsPerSecond: Double
    let births: UInt64
    let deaths: UInt64
    let fissions: UInt64
    let fusions: UInt64
    let invariantReport: ExperimentInvariantReport
    let finalSample: ExperimentSample?
    let outputPath: String
}

struct HeadlessExperimentResult {
    let summary: ExperimentSummary
    let interventionSample: ExperimentSample?
}

private struct ExperimentEnvelope<Payload: Encodable>: Encodable {
    let record: String
    let payload: Payload
}

final class ExperimentJournal {
    let outputURL: URL
    private let handle: FileHandle?
    private let encoder: JSONEncoder

    init(path: String) throws {
        outputURL = URL(fileURLWithPath: path).standardizedFileURL
        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            handle = try FileHandle(forWritingTo: outputURL)
        } catch {
            throw HeadlessExperimentError.output(
                "Could not open experiment output \(outputURL.path): \(error.localizedDescription)"
            )
        }
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    private init(discarding: Bool) {
        outputURL = URL(fileURLWithPath: "/dev/null")
        handle = nil
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    static func discarding() -> ExperimentJournal {
        ExperimentJournal(discarding: true)
    }

    deinit {
        try? handle?.close()
    }

    func append<T: Encodable>(_ record: String, _ payload: T) throws {
        guard let handle else { return }
        var data = try encoder.encode(ExperimentEnvelope(record: record, payload: payload))
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }
}

enum HeadlessExperimentCLI {
    @MainActor
    static func run(arguments: ArraySlice<String>) throws {
        let configuration = try HeadlessExperimentConfiguration.parse(arguments)
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw EvolutionRendererError.noMetalDevice
        }
        let view = MTKView(frame: .zero, device: device)
        view.isPaused = true
        let renderer = try EvolutionRenderer(view: view)
        let journal = try ExperimentJournal(path: configuration.outputPath)
        let result = try renderer.runHeadlessExperiment(
            configuration: configuration,
            journal: journal
        )
        let summary = result.summary
        print(
            "experiment_complete=\(summary.completed ? 1 : 0) " +
            "steps=\(summary.step) steps_per_second=" +
            String(format: "%.1f", summary.meanStepsPerSecond) +
            " output=\(summary.outputPath)"
        )
    }
}
