import AutogenesisCore
import Darwin
import Foundation
import MetalKit

struct PairedCausalExperimentConfiguration: Codable, Sendable {
    var masterSeed: UInt32 = 1
    var pairCount: Int = 8
    var steps: UInt64 = 12_000
    var interventionStep: UInt64 = 6_000
    var batchSize: Int = 64
    var sampleInterval: UInt64 = 1_200
    var auditInterval: UInt64 = 1
    var quantumStride: UInt64 = 3
    var strictInvariants = true
    var allowConcurrent = false
    var outputPath = ""

    static let usage = """
    Usage: NumiAutomata causal-experiment [options]

      --steps N             Final outcome step (default: 12000)
      --intervention-step N Last baseline step (default: 6000)
      --pairs N             Distinct paired replicates, 4...128 (default: 8)
      --seed N              Master UInt32 seed for replicate derivation (default: 1)
      --batch N             Steps encoded per command buffer (default: 64)
      --sample-every N      Lineage readback interval (default: 1200)
      --audit-every N       GPU invariant interval (default: 1)
      --quantum-stride N    Biological steps per quantum step (default: 3)
      --output PATH         Paired-estimate JSONL output path
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
            configuration.interventionStep = configuration.steps / 2
        }
        guard configuration.interventionStep < configuration.steps else {
            throw HeadlessExperimentError.invalidArgument(
                "--intervention-step must be smaller than --steps."
            )
        }
        if configuration.outputPath.isEmpty {
            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            configuration.outputPath = FileManager.default.currentDirectoryPath +
                "/Experiments/paired-mechanosensing-\(timestamp).jsonl"
        }
        return configuration
    }
}

struct CausalExperimentHeader: Codable {
    let schemaVersion: Int
    let startedAt: String
    let device: String
    let intervention: String
    let estimand: String
    let replicateSeedDerivation: String
    let pairExclusionRule: String
    let intervalMethod: String
    let multiplicityAdjustment: String
    let configuration: PairedCausalExperimentConfiguration
}

struct CausalOutcomeVector: Codable, Equatable, Sendable {
    let livingComponents: Double
    let mechanochemicalClosure: Double
    let livingCells: Double
    let meanCellATP: Double
    let meanCellIntegrity: Double
    let meanCellStress: Double
    let meanMembraneVoltage: Double
    let meanCalciumActivity: Double
    let meanERKActivity: Double
    let dividingCellFraction: Double
    let meanCellTraction: Double
    let meanFrequencyMatch: Double
    let meanTissueElongation: Double
    let trophicGain: Double
    let trophicLoss: Double

    init(sample: ExperimentSample) {
        livingComponents = Double(sample.physicalComponents)
        mechanochemicalClosure = sample.meanMechanochemicalClosure
        livingCells = Double(sample.livingCells)
        meanCellATP = sample.meanCellATP
        meanCellIntegrity = sample.meanCellIntegrity
        meanCellStress = sample.meanCellStress
        meanMembraneVoltage = sample.meanMembraneVoltage
        meanCalciumActivity = sample.meanCalciumActivity
        meanERKActivity = sample.meanERKActivity
        dividingCellFraction = sample.dividingCellFraction
        meanCellTraction = sample.meanCellTraction
        meanFrequencyMatch = sample.meanFrequencyMatch
        meanTissueElongation = sample.meanElongation
        trophicGain = sample.trophicGain
        trophicLoss = sample.trophicLoss
    }

    static func difference(treatment: Self, control: Self) -> Self {
        Self(
            livingComponents: treatment.livingComponents - control.livingComponents,
            mechanochemicalClosure: treatment.mechanochemicalClosure - control.mechanochemicalClosure,
            livingCells: treatment.livingCells - control.livingCells,
            meanCellATP: treatment.meanCellATP - control.meanCellATP,
            meanCellIntegrity: treatment.meanCellIntegrity - control.meanCellIntegrity,
            meanCellStress: treatment.meanCellStress - control.meanCellStress,
            meanMembraneVoltage: treatment.meanMembraneVoltage - control.meanMembraneVoltage,
            meanCalciumActivity: treatment.meanCalciumActivity - control.meanCalciumActivity,
            meanERKActivity: treatment.meanERKActivity - control.meanERKActivity,
            dividingCellFraction: treatment.dividingCellFraction - control.dividingCellFraction,
            meanCellTraction: treatment.meanCellTraction - control.meanCellTraction,
            meanFrequencyMatch: treatment.meanFrequencyMatch - control.meanFrequencyMatch,
            meanTissueElongation: treatment.meanTissueElongation - control.meanTissueElongation,
            trophicGain: treatment.trophicGain - control.trophicGain,
            trophicLoss: treatment.trophicLoss - control.trophicLoss
        )
    }

    private init(
        livingComponents: Double,
        mechanochemicalClosure: Double,
        livingCells: Double,
        meanCellATP: Double,
        meanCellIntegrity: Double,
        meanCellStress: Double,
        meanMembraneVoltage: Double,
        meanCalciumActivity: Double,
        meanERKActivity: Double,
        dividingCellFraction: Double,
        meanCellTraction: Double,
        meanFrequencyMatch: Double,
        meanTissueElongation: Double,
        trophicGain: Double,
        trophicLoss: Double
    ) {
        self.livingComponents = livingComponents
        self.mechanochemicalClosure = mechanochemicalClosure
        self.livingCells = livingCells
        self.meanCellATP = meanCellATP
        self.meanCellIntegrity = meanCellIntegrity
        self.meanCellStress = meanCellStress
        self.meanMembraneVoltage = meanMembraneVoltage
        self.meanCalciumActivity = meanCalciumActivity
        self.meanERKActivity = meanERKActivity
        self.dividingCellFraction = dividingCellFraction
        self.meanCellTraction = meanCellTraction
        self.meanFrequencyMatch = meanFrequencyMatch
        self.meanTissueElongation = meanTissueElongation
        self.trophicGain = trophicGain
        self.trophicLoss = trophicLoss
    }
}

struct CausalPairRecord: Codable {
    let pairIndex: Int
    let seed: UInt32
    let interventionStep: UInt64
    let outcomeStep: UInt64
    let observedBaselineMatched: Bool
    let validForEstimation: Bool
    let controlInvariants: ExperimentInvariantReport
    let treatmentInvariants: ExperimentInvariantReport
    let control: CausalOutcomeVector
    let treatment: CausalOutcomeVector
    let treatmentMinusControl: CausalOutcomeVector
}

struct NamedPairedEffect: Codable {
    let outcome: String
    let unit: String
    let estimate: PairedEffectEstimate
}

struct CausalExperimentSummary: Codable {
    let completed: Bool
    let elapsedSeconds: Double
    let requestedPairCount: Int
    let validPairCount: Int
    let excludedPairCount: Int
    let interventionStep: UInt64
    let outcomeStep: UInt64
    let effects: [NamedPairedEffect]
    let outputPath: String
}

enum PairedCausalExperimentCLI {
    private struct OutcomeDefinition {
        let name: String
        let unit: String
        let keyPath: KeyPath<CausalOutcomeVector, Double>
    }

    @MainActor private static let outcomes = [
        OutcomeDefinition(name: "living_components", unit: "count", keyPath: \.livingComponents),
        OutcomeDefinition(name: "mechanochemical_closure", unit: "dimensionless", keyPath: \.mechanochemicalClosure),
        OutcomeDefinition(name: "living_cells", unit: "count", keyPath: \.livingCells),
        OutcomeDefinition(name: "mean_cell_atp", unit: "model_energy_per_cell", keyPath: \.meanCellATP),
        OutcomeDefinition(name: "mean_cell_integrity", unit: "fraction", keyPath: \.meanCellIntegrity),
        OutcomeDefinition(name: "mean_cell_stress", unit: "dimensionless", keyPath: \.meanCellStress),
        OutcomeDefinition(name: "mean_membrane_voltage", unit: "dimensionless", keyPath: \.meanMembraneVoltage),
        OutcomeDefinition(name: "mean_calcium_activity", unit: "dimensionless", keyPath: \.meanCalciumActivity),
        OutcomeDefinition(name: "mean_erk_activity", unit: "dimensionless", keyPath: \.meanERKActivity),
        OutcomeDefinition(name: "dividing_cell_fraction", unit: "fraction", keyPath: \.dividingCellFraction),
        OutcomeDefinition(name: "mean_cell_traction", unit: "model_force", keyPath: \.meanCellTraction),
        OutcomeDefinition(name: "mean_frequency_match", unit: "fraction", keyPath: \.meanFrequencyMatch),
        OutcomeDefinition(name: "mean_tissue_elongation", unit: "fraction", keyPath: \.meanTissueElongation),
        OutcomeDefinition(name: "trophic_gain", unit: "model_energy_per_step", keyPath: \.trophicGain),
        OutcomeDefinition(name: "trophic_loss", unit: "model_energy_per_step", keyPath: \.trophicLoss)
    ]

    @MainActor
    static func run(arguments: ArraySlice<String>) throws {
        let configuration = try PairedCausalExperimentConfiguration.parse(arguments)
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
        let startedAt = ISO8601DateFormatter().string(from: Date())
        try journal.append("causal_header", CausalExperimentHeader(
            schemaVersion: 3,
            startedAt: startedAt,
            device: device.name,
            intervention: "Set mechanics-to-voltage and mechanics-to-Ca* gain from 1 to 0 after the configured baseline step.",
            estimand: "Paired average treatment effect at the final step over distinct SplitMix64-derived seeded initial worlds; each control/treatment pair shares its seed and all pre-intervention equations.",
            replicateSeedDerivation: "Distinct UInt32 seeds generated deterministically from the master seed using SplitMix64 mixing.",
            pairExclusionRule: "Exclude a pair if either final GPU invariant report has a nonzero flag; abort if recorded baseline outcome vectors differ.",
            intervalMethod: "Two-sided 95% paired-t interval over treatment-minus-control differences across valid seeded pairs.",
            multiplicityAdjustment: "None; each endpoint interval is marginal and must not be interpreted as familywise simultaneous coverage.",
            configuration: configuration
        ))

        let startTime = CFAbsoluteTimeGetCurrent()
        var controls: [CausalOutcomeVector] = []
        var treatments: [CausalOutcomeVector] = []
        controls.reserveCapacity(configuration.pairCount)
        treatments.reserveCapacity(configuration.pairCount)

        var usedSeeds: Set<UInt32> = []
        for pairIndex in 0..<configuration.pairCount {
            let seed = distinctReplicateSeed(
                masterSeed: configuration.masterSeed,
                pairIndex: pairIndex,
                used: &usedSeeds
            )
            let controlResult = try renderer.runHeadlessExperiment(
                configuration: runConfiguration(
                    configuration,
                    seed: seed,
                    postInterventionGain: 1
                ),
                journal: discardedJournal,
                reportProgress: false
            )
            let treatmentResult = try renderer.runHeadlessExperiment(
                configuration: runConfiguration(
                    configuration,
                    seed: seed,
                    postInterventionGain: 0
                ),
                journal: discardedJournal,
                reportProgress: false
            )
            guard let controlFinal = controlResult.summary.finalSample,
                  let treatmentFinal = treatmentResult.summary.finalSample,
                  let controlBaseline = controlResult.interventionSample,
                  let treatmentBaseline = treatmentResult.interventionSample else {
                throw HeadlessExperimentError.missingExperimentSample(
                    "Paired causal run did not produce its baseline and final samples."
                )
            }
            let controlBaselineVector = CausalOutcomeVector(sample: controlBaseline)
            let treatmentBaselineVector = CausalOutcomeVector(sample: treatmentBaseline)
            guard controlBaselineVector == treatmentBaselineVector else {
                throw HeadlessExperimentError.pairedBaselineMismatch(seed: seed)
            }
            let control = CausalOutcomeVector(sample: controlFinal)
            let treatment = CausalOutcomeVector(sample: treatmentFinal)
            let controlInvariants = controlFinal.invariantReport
            let treatmentInvariants = treatmentFinal.invariantReport
            let validForEstimation = controlInvariants.flags == 0 &&
                treatmentInvariants.flags == 0
            if validForEstimation {
                controls.append(control)
                treatments.append(treatment)
            }
            try journal.append("causal_pair", CausalPairRecord(
                pairIndex: pairIndex,
                seed: seed,
                interventionStep: configuration.interventionStep,
                outcomeStep: configuration.steps,
                observedBaselineMatched: true,
                validForEstimation: validForEstimation,
                controlInvariants: controlInvariants,
                treatmentInvariants: treatmentInvariants,
                control: control,
                treatment: treatment,
                treatmentMinusControl: .difference(treatment: treatment, control: control)
            ))
            print(
                "causal_pair=\(pairIndex + 1)/\(configuration.pairCount) " +
                "seed=\(seed) baseline_match=1 valid=\(validForEstimation ? 1 : 0)"
            )
        }

        let effects = outcomes.compactMap { outcome -> NamedPairedEffect? in
            let control = controls.map { $0[keyPath: outcome.keyPath] }
            let treatment = treatments.map { $0[keyPath: outcome.keyPath] }
            guard let estimate = CausalAnalysis.pairedEffect(
                control: control,
                treatment: treatment
            ) else { return nil }
            return NamedPairedEffect(
                outcome: outcome.name,
                unit: outcome.unit,
                estimate: estimate
            )
        }
        let summary = CausalExperimentSummary(
            completed: controls.count == configuration.pairCount &&
                effects.count == outcomes.count,
            elapsedSeconds: CFAbsoluteTimeGetCurrent() - startTime,
            requestedPairCount: configuration.pairCount,
            validPairCount: controls.count,
            excludedPairCount: configuration.pairCount - controls.count,
            interventionStep: configuration.interventionStep,
            outcomeStep: configuration.steps,
            effects: effects,
            outputPath: journal.outputURL.path
        )
        try journal.append("causal_summary", summary)
        print(
            "causal_experiment_complete=\(summary.completed ? 1 : 0) " +
            "pairs=\(summary.validPairCount)/\(summary.requestedPairCount) " +
            "output=\(summary.outputPath)"
        )
    }

    private static func runConfiguration(
        _ paired: PairedCausalExperimentConfiguration,
        seed: UInt32,
        postInterventionGain: Float
    ) -> HeadlessExperimentConfiguration {
        var configuration = HeadlessExperimentConfiguration()
        configuration.seed = seed
        configuration.steps = paired.steps
        configuration.batchSize = paired.batchSize
        configuration.sampleInterval = paired.sampleInterval
        configuration.auditInterval = paired.auditInterval
        configuration.quantumStride = paired.quantumStride
        configuration.strictInvariants = paired.strictInvariants
        configuration.mechanosensing = MechanosensingSchedule(
            baselineGain: 1,
            interventionStep: paired.interventionStep,
            postInterventionGain: postInterventionGain
        )
        configuration.outputPath = "/dev/null"
        return configuration
    }

    private static func distinctReplicateSeed(
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
}
