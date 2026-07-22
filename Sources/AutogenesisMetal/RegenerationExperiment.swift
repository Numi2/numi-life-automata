import AutogenesisCore
import Darwin
import Foundation
import MetalKit

struct PairedRegenerationExperimentConfiguration: Codable, Sendable {
    var masterSeed: UInt32 = 1
    var pairCount: Int = 32
    var steps: UInt64 = 12_000
    var interventionStep: UInt64 = 9_600
    var batchSize: Int = 64
    var sampleInterval: UInt64 = 600
    var auditInterval: UInt64 = 1
    var quantumStride: UInt64 = 3
    var strictInvariants = true
    var allowConcurrent = false
    var outputPath = ""

    static let usage = """
    Usage: NumiAutomata regeneration-experiment [options]

      --steps N             Final outcome step (default: 12000)
      --intervention-step N Last unwounded baseline step (default: 9600)
      --pairs N             Distinct paired replicates, 4...128 (default: 32)
      --seed N              Master UInt32 seed for replicate derivation (default: 1)
      --batch N             Steps encoded per command buffer (default: 64)
      --sample-every N      Recovery-curve interval (default: 600)
      --audit-every N       GPU invariant interval (default: 1)
      --quantum-stride N    Biological steps per quantum step (default: 3)
      --output PATH         Paired qualification JSONL output path
      --no-strict           Record invariant failures without stopping
      --allow-concurrent    Bypass the exclusive GPU experiment lock
      --help                Show this help
    """

    static func parse(_ arguments: ArraySlice<String>) throws -> Self {
        var configuration = Self()
        var interventionWasExplicit = false
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
                guard let value = UInt64(try value(after: argument)), value >= 2 else {
                    throw HeadlessExperimentError.invalidArgument("--steps must be at least 2.")
                }
                configuration.steps = value
            case "--intervention-step":
                guard let value = UInt64(try value(after: argument)), value > 0 else {
                    throw HeadlessExperimentError.invalidArgument(
                        "--intervention-step must be positive."
                    )
                }
                configuration.interventionStep = value
                interventionWasExplicit = true
            case "--pairs":
                guard let value = Int(try value(after: argument)), (4...128).contains(value) else {
                    throw HeadlessExperimentError.invalidArgument("--pairs must be in 4...128.")
                }
                configuration.pairCount = value
            case "--seed":
                guard let value = UInt32(try value(after: argument)) else {
                    throw HeadlessExperimentError.invalidArgument("--seed must fit UInt32.")
                }
                configuration.masterSeed = value
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
            case "--output":
                configuration.outputPath = try value(after: argument)
            case "--no-strict":
                configuration.strictInvariants = false
            case "--allow-concurrent":
                configuration.allowConcurrent = true
            case "--help", "-h":
                print(usage)
                exit(EXIT_SUCCESS)
            default:
                throw HeadlessExperimentError.invalidArgument("Unknown option: \(argument)")
            }
            index = arguments.index(after: index)
        }
        if !interventionWasExplicit {
            configuration.interventionStep = min(9_600, configuration.steps * 4 / 5)
        }
        guard configuration.interventionStep &+ 1 < configuration.steps else {
            throw HeadlessExperimentError.invalidArgument(
                "--intervention-step must leave at least two post-intervention steps."
            )
        }
        guard configuration.steps - configuration.interventionStep >= 1_200 else {
            throw HeadlessExperimentError.invalidArgument(
                "The outcome must be at least 1200 steps after the wound."
            )
        }
        if configuration.outputPath.isEmpty {
            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            configuration.outputPath = FileManager.default.currentDirectoryPath +
                "/Experiments/paired-regeneration-\(timestamp).jsonl"
        }
        return configuration
    }
}

struct RegenerationExperimentHeader: Codable {
    let schemaVersion: Int
    let startedAt: String
    let device: String
    let targetRule: String
    let intervention: String
    let control: String
    let qualificationGate: String
    let pairExclusionRule: String
    let intervalMethod: String
    let configuration: PairedRegenerationExperimentConfiguration
}

struct RegenerationTargetSnapshot: Codable, Equatable, Sendable {
    let step: UInt64
    let present: Bool
    let birthID: UInt32?
    let cellCount: Double
    let atp: Double
    let integrity: Double
    let stress: Double
    let shapeIndex: Double
    let matrix: Double
    let woundCue: Double
    let challenged: Bool
    let homeostatic: Bool

    init(sample: ExperimentSample) {
        step = sample.step
        present = sample.qualificationTargetPresent
        birthID = sample.qualificationTargetBirthID
        cellCount = Double(sample.qualificationTargetCellCount)
        atp = sample.qualificationTargetATP
        integrity = sample.qualificationTargetIntegrity
        stress = sample.qualificationTargetStress
        shapeIndex = sample.qualificationTargetShapeIndex
        matrix = sample.qualificationTargetMatrix
        woundCue = sample.qualificationTargetWoundCue
        challenged = sample.qualificationTargetChallenged
        homeostatic = sample.qualificationTargetHomeostatic
    }
}

struct RegenerationEndpointVector: Codable, Equatable, Sendable {
    let alive: Double
    let cellCount: Double
    let atp: Double
    let integrity: Double
    let stress: Double
    let shapeIndex: Double
    let matrix: Double
    let woundCue: Double

    init(snapshot: RegenerationTargetSnapshot) {
        alive = snapshot.present ? 1 : 0
        cellCount = snapshot.cellCount
        atp = snapshot.atp
        integrity = snapshot.integrity
        stress = snapshot.stress
        shapeIndex = snapshot.shapeIndex
        matrix = snapshot.matrix
        woundCue = snapshot.woundCue
    }

    static func difference(treatment: Self, control: Self) -> Self {
        Self(
            alive: treatment.alive - control.alive,
            cellCount: treatment.cellCount - control.cellCount,
            atp: treatment.atp - control.atp,
            integrity: treatment.integrity - control.integrity,
            stress: treatment.stress - control.stress,
            shapeIndex: treatment.shapeIndex - control.shapeIndex,
            matrix: treatment.matrix - control.matrix,
            woundCue: treatment.woundCue - control.woundCue
        )
    }

    private init(
        alive: Double,
        cellCount: Double,
        atp: Double,
        integrity: Double,
        stress: Double,
        shapeIndex: Double,
        matrix: Double,
        woundCue: Double
    ) {
        self.alive = alive
        self.cellCount = cellCount
        self.atp = atp
        self.integrity = integrity
        self.stress = stress
        self.shapeIndex = shapeIndex
        self.matrix = matrix
        self.woundCue = woundCue
    }
}

struct RegenerationPairRecord: Codable {
    let pairIndex: Int
    let seed: UInt32
    let eligibleAtBaseline: Bool
    let observedBaselineMatched: Bool
    let woundDeliveredToTarget: Bool
    let validForEstimation: Bool
    let recoveredAtOutcome: Bool
    let controlInvariants: ExperimentInvariantReport
    let treatmentInvariants: ExperimentInvariantReport
    let baseline: RegenerationTargetSnapshot
    let controlTrajectory: [RegenerationTargetSnapshot]
    let treatmentTrajectory: [RegenerationTargetSnapshot]
    let controlFinal: RegenerationEndpointVector
    let treatmentFinal: RegenerationEndpointVector
    let treatmentMinusControl: RegenerationEndpointVector
}

struct NamedRegenerationEffect: Codable {
    let outcome: String
    let unit: String
    let estimate: PairedEffectEstimate
}

struct RegenerationExperimentSummary: Codable {
    let completed: Bool
    let elapsedSeconds: Double
    let requestedPairCount: Int
    let eligiblePairCount: Int
    let validPairCount: Int
    let ineligiblePairCount: Int
    let invalidPairCount: Int
    let recovery: BinomialProportionEstimate
    let qualification: EvidenceClaim
    let effects: [NamedRegenerationEffect]
    let outputPath: String
}

enum PairedRegenerationExperimentCLI {
    private struct OutcomeDefinition {
        let name: String
        let unit: String
        let keyPath: KeyPath<RegenerationEndpointVector, Double>
    }

    @MainActor private static let outcomes = [
        OutcomeDefinition(name: "target_alive", unit: "fraction", keyPath: \.alive),
        OutcomeDefinition(name: "target_cell_count", unit: "count", keyPath: \.cellCount),
        OutcomeDefinition(name: "target_atp", unit: "model_energy_per_cell", keyPath: \.atp),
        OutcomeDefinition(name: "target_integrity", unit: "fraction", keyPath: \.integrity),
        OutcomeDefinition(name: "target_stress", unit: "dimensionless", keyPath: \.stress),
        OutcomeDefinition(name: "target_shape_index", unit: "dimensionless", keyPath: \.shapeIndex),
        OutcomeDefinition(name: "target_matrix", unit: "dimensionless", keyPath: \.matrix),
        OutcomeDefinition(name: "target_wound_cue", unit: "dimensionless", keyPath: \.woundCue)
    ]

    @MainActor
    static func run(arguments: ArraySlice<String>) throws {
        let configuration = try PairedRegenerationExperimentConfiguration.parse(arguments)
        let admissionLock = try ExperimentAdmissionLock.acquire(
            unless: configuration.allowConcurrent
        )
        defer { withExtendedLifetime(admissionLock) {} }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw EvolutionRendererError.noMetalDevice
        }
        let view = MTKView(frame: .zero, device: device)
        view.isPaused = true
        let renderer = try EvolutionRenderer(view: view)
        let journal = try ExperimentJournal(path: configuration.outputPath)
        let discardedJournal = ExperimentJournal.discarding()
        try journal.append("regeneration_header", RegenerationExperimentHeader(
            schemaVersion: 1,
            startedAt: ISO8601DateFormatter().string(from: Date()),
            device: device.name,
            targetRule: "At the last baseline step, choose the living multicellular regenerative descendant with the smallest permanent component birth ID; use its first living owner-list cell as the wound anchor.",
            intervention: "At the next step, damage the selected target's local world, actual CellState records, and membrane vertices; clear prior homeostasis evidence and start a 667-step observer-only recovery window.",
            control: "Select and observe the identical same-seed target without applying damage.",
            qualificationGate: "A treatment target must be alive with the homeostasis flag and recover to at least 80% of sham cell count, ATP, and integrity, within sham stress plus 0.15, and within 20% (minimum tolerance 0.15) of sham shape index. Robust support additionally requires at least eight valid eligible pairs and a two-sided 95% Wilson lower bound above 0.5.",
            pairExclusionRule: "A pair is ineligible when no regenerative multicellular descendant exists at baseline; it is invalid if baseline targets differ, the wound is not delivered, a GPU invariant flag is nonzero, or absolute energy residual exceeds 0.001.",
            intervalMethod: "Wilson score interval for recovery proportion; marginal two-sided 95% paired-t intervals for treatment-minus-sham endpoint differences, without multiplicity adjustment.",
            configuration: configuration
        ))

        let startTime = CFAbsoluteTimeGetCurrent()
        var controls: [RegenerationEndpointVector] = []
        var treatments: [RegenerationEndpointVector] = []
        var eligiblePairCount = 0
        var invalidPairCount = 0
        var recoveredCount = 0
        var usedSeeds: Set<UInt32> = []

        for pairIndex in 0..<configuration.pairCount {
            let seed = distinctSeed(
                masterSeed: configuration.masterSeed,
                pairIndex: pairIndex,
                used: &usedSeeds
            )
            let controlResult = try renderer.runHeadlessExperiment(
                configuration: runConfiguration(
                    configuration, seed: seed, mode: .shamRegenerativeTarget
                ),
                journal: discardedJournal,
                resultRetention: .samples,
                reportProgress: false
            )
            let treatmentResult = try renderer.runHeadlessExperiment(
                configuration: runConfiguration(
                    configuration, seed: seed, mode: .targetedRegenerativeWound
                ),
                journal: discardedJournal,
                resultRetention: .samples,
                reportProgress: false
            )
            guard let controlBaselineSample = controlResult.interventionSample,
                  let treatmentBaselineSample = treatmentResult.interventionSample,
                  let controlFinalSample = controlResult.summary.finalSample,
                  let treatmentFinalSample = treatmentResult.summary.finalSample else {
                throw HeadlessExperimentError.missingExperimentSample(
                    "Paired regeneration run did not produce baseline and final samples."
                )
            }
            let controlBaseline = RegenerationTargetSnapshot(sample: controlBaselineSample)
            let treatmentBaseline = RegenerationTargetSnapshot(sample: treatmentBaselineSample)
            guard controlBaseline == treatmentBaseline else {
                throw HeadlessExperimentError.pairedBaselineMismatch(seed: seed)
            }
            let eligible = controlBaseline.present && controlBaseline.birthID != nil
            if eligible { eligiblePairCount += 1 }
            let controlTrajectory = controlResult.samples
                .filter { $0.step >= configuration.interventionStep }
                .map(RegenerationTargetSnapshot.init(sample:))
            let treatmentTrajectory = treatmentResult.samples
                .filter { $0.step >= configuration.interventionStep }
                .map(RegenerationTargetSnapshot.init(sample:))
            let woundDelivered = treatmentTrajectory.contains {
                $0.step > configuration.interventionStep && $0.challenged
            }
            let controlFinalSnapshot = RegenerationTargetSnapshot(sample: controlFinalSample)
            let treatmentFinalSnapshot = RegenerationTargetSnapshot(sample: treatmentFinalSample)
            let controlFinal = RegenerationEndpointVector(snapshot: controlFinalSnapshot)
            let treatmentFinal = RegenerationEndpointVector(snapshot: treatmentFinalSnapshot)
            let controlInvariants = controlFinalSample.invariantReport
            let treatmentInvariants = treatmentFinalSample.invariantReport
            let invariantValid = controlInvariants.flags == 0 &&
                treatmentInvariants.flags == 0 &&
                controlInvariants.maximumEnergyResidual <= 0.001 &&
                treatmentInvariants.maximumEnergyResidual <= 0.001
            let valid = eligible && woundDelivered && invariantValid
            let recovered = valid && recoveredRelativeToSham(
                treatment: treatmentFinalSnapshot,
                control: controlFinalSnapshot
            )
            if valid {
                controls.append(controlFinal)
                treatments.append(treatmentFinal)
                recoveredCount += recovered ? 1 : 0
            } else if eligible {
                invalidPairCount += 1
            }
            try journal.append("regeneration_pair", RegenerationPairRecord(
                pairIndex: pairIndex,
                seed: seed,
                eligibleAtBaseline: eligible,
                observedBaselineMatched: true,
                woundDeliveredToTarget: woundDelivered,
                validForEstimation: valid,
                recoveredAtOutcome: recovered,
                controlInvariants: controlInvariants,
                treatmentInvariants: treatmentInvariants,
                baseline: controlBaseline,
                controlTrajectory: controlTrajectory,
                treatmentTrajectory: treatmentTrajectory,
                controlFinal: controlFinal,
                treatmentFinal: treatmentFinal,
                treatmentMinusControl: .difference(
                    treatment: treatmentFinal, control: controlFinal
                )
            ))
            print(
                "regeneration_pair=\(pairIndex + 1)/\(configuration.pairCount) " +
                "seed=\(seed) eligible=\(eligible ? 1 : 0) " +
                "wounded=\(woundDelivered ? 1 : 0) recovered=\(recovered ? 1 : 0) " +
                "valid=\(valid ? 1 : 0)"
            )
        }

        let effects = outcomes.compactMap { outcome -> NamedRegenerationEffect? in
            guard let estimate = CausalAnalysis.pairedEffect(
                control: controls.map { $0[keyPath: outcome.keyPath] },
                treatment: treatments.map { $0[keyPath: outcome.keyPath] }
            ) else { return nil }
            return NamedRegenerationEffect(
                outcome: outcome.name,
                unit: outcome.unit,
                estimate: estimate
            )
        }
        let recovery = BinomialQualification.wilson95(
            successes: recoveredCount,
            trials: controls.count
        )
        let qualification = BinomialQualification.evidence(
            recovery: recovery,
            minimumTrials: 8,
            threshold: 0.5
        )
        let summary = RegenerationExperimentSummary(
            completed: true,
            elapsedSeconds: CFAbsoluteTimeGetCurrent() - startTime,
            requestedPairCount: configuration.pairCount,
            eligiblePairCount: eligiblePairCount,
            validPairCount: controls.count,
            ineligiblePairCount: configuration.pairCount - eligiblePairCount,
            invalidPairCount: invalidPairCount,
            recovery: recovery,
            qualification: qualification,
            effects: effects,
            outputPath: journal.outputURL.path
        )
        try journal.append("regeneration_summary", summary)
        print(
            "regeneration_experiment_complete=1 valid=\(summary.validPairCount) " +
            "eligible=\(summary.eligiblePairCount)/\(summary.requestedPairCount) " +
            "recovered=\(recovery.successes)/\(recovery.trials) " +
            "qualification=\(qualification.state.rawValue) output=\(summary.outputPath)"
        )
    }

    private static func runConfiguration(
        _ paired: PairedRegenerationExperimentConfiguration,
        seed: UInt32,
        mode: DamageChallengeMode
    ) -> HeadlessExperimentConfiguration {
        var configuration = HeadlessExperimentConfiguration()
        configuration.seed = seed
        configuration.steps = paired.steps
        configuration.batchSize = paired.batchSize
        configuration.sampleInterval = paired.sampleInterval
        configuration.auditInterval = paired.auditInterval
        configuration.quantumStride = paired.quantumStride
        configuration.strictInvariants = paired.strictInvariants
        configuration.damageChallenge = DamageChallengeSchedule(
            mode: mode,
            interventionStep: paired.interventionStep
        )
        configuration.outputPath = "/dev/null"
        return configuration
    }

    private static func distinctSeed(
        masterSeed: UInt32,
        pairIndex: Int,
        used: inout Set<UInt32>
    ) -> UInt32 {
        var nonce = UInt64(pairIndex)
        while true {
            var value = UInt64(masterSeed) &+
                0x9E37_79B9_7F4A_7C15 &* (nonce &+ 1)
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            value ^= value >> 31
            let seed = UInt32(truncatingIfNeeded: value)
            if used.insert(seed).inserted { return seed }
            nonce &+= UInt64(max(1, pairIndex + 1))
        }
    }

    private static func recoveredRelativeToSham(
        treatment: RegenerationTargetSnapshot,
        control: RegenerationTargetSnapshot
    ) -> Bool {
        guard treatment.present, treatment.homeostatic, control.present else { return false }
        let shapeTolerance = max(abs(control.shapeIndex) * 0.20, 0.15)
        return treatment.cellCount >= control.cellCount * 0.80 &&
            treatment.atp >= control.atp * 0.80 &&
            treatment.integrity >= control.integrity * 0.80 &&
            treatment.stress <= control.stress + 0.15 &&
            abs(treatment.shapeIndex - control.shapeIndex) <= shapeTolerance
    }

}
