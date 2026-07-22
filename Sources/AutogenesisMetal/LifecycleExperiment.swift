import AutogenesisCore
import Darwin
import Foundation
import MetalKit

struct LifecycleExperimentConfiguration: Codable, Sendable {
    var masterSeed: UInt32 = 1
    var maximumSeedCount = 128
    var minimumValidCycles = 8
    var steps: UInt64 = 18_000
    var interventionStep: UInt64 = 9_600
    var recoveryDelay: UInt64 = 1_200
    var maturationWindow: UInt64 = 600
    var batchSize = 64
    var sampleInterval: UInt64 = 600
    var auditInterval: UInt64 = 1
    var quantumStride: UInt64 = 3
    var strictInvariants = true
    var allowConcurrent = false
    var outputPath = ""

    static let usage = """
    Usage: NumiAutomata lifecycle-experiment [options]

      --steps N             Final step for each paired run (default: 18000)
      --intervention-step N Last unwounded baseline step (default: 9600)
      --recovery-delay N    Steps allowed before recovery is assessed (default: 1200)
      --maturation-window N Required stable grandchild duration (default: 600)
      --max-seeds N         Maximum fixed seeds attempted, 4...128 (default: 128)
      --minimum-valid N     Eligible valid cycles required, 1...64 (default: 8)
      --seed N              Master UInt32 seed (default: 1)
      --batch N             Steps encoded per command buffer (default: 64)
      --sample-every N      Observer snapshot interval (default: 600)
      --audit-every N       GPU invariant interval (default: 1)
      --quantum-stride N    Biological steps per quantum step (default: 3)
      --output PATH         Lifecycle qualification JSONL output path
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
                guard let parsed = UInt64(try value(after: argument)), parsed >= 2_400 else {
                    throw HeadlessExperimentError.invalidArgument("--steps must be at least 2400.")
                }
                configuration.steps = parsed
            case "--intervention-step":
                guard let parsed = UInt64(try value(after: argument)), parsed > 0 else {
                    throw HeadlessExperimentError.invalidArgument(
                        "--intervention-step must be positive."
                    )
                }
                configuration.interventionStep = parsed
                interventionWasExplicit = true
            case "--recovery-delay":
                guard let parsed = UInt64(try value(after: argument)), parsed >= 600 else {
                    throw HeadlessExperimentError.invalidArgument(
                        "--recovery-delay must be at least 600."
                    )
                }
                configuration.recoveryDelay = parsed
            case "--maturation-window":
                guard let parsed = UInt64(try value(after: argument)), parsed > 0 else {
                    throw HeadlessExperimentError.invalidArgument(
                        "--maturation-window must be positive."
                    )
                }
                configuration.maturationWindow = parsed
            case "--max-seeds":
                guard let parsed = Int(try value(after: argument)), (4...128).contains(parsed) else {
                    throw HeadlessExperimentError.invalidArgument("--max-seeds must be in 4...128.")
                }
                configuration.maximumSeedCount = parsed
            case "--minimum-valid":
                guard let parsed = Int(try value(after: argument)), (1...64).contains(parsed) else {
                    throw HeadlessExperimentError.invalidArgument(
                        "--minimum-valid must be in 1...64."
                    )
                }
                configuration.minimumValidCycles = parsed
            case "--seed":
                guard let parsed = UInt32(try value(after: argument)) else {
                    throw HeadlessExperimentError.invalidArgument("--seed must fit UInt32.")
                }
                configuration.masterSeed = parsed
            case "--batch":
                guard let parsed = Int(try value(after: argument)), (1...256).contains(parsed) else {
                    throw HeadlessExperimentError.invalidArgument("--batch must be in 1...256.")
                }
                configuration.batchSize = parsed
            case "--sample-every":
                guard let parsed = UInt64(try value(after: argument)), parsed > 0 else {
                    throw HeadlessExperimentError.invalidArgument("--sample-every must be positive.")
                }
                configuration.sampleInterval = parsed
            case "--audit-every":
                guard let parsed = UInt64(try value(after: argument)), parsed > 0 else {
                    throw HeadlessExperimentError.invalidArgument("--audit-every must be positive.")
                }
                configuration.auditInterval = parsed
            case "--quantum-stride":
                guard let parsed = UInt64(try value(after: argument)), parsed > 0 else {
                    throw HeadlessExperimentError.invalidArgument("--quantum-stride must be positive.")
                }
                configuration.quantumStride = parsed
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
            configuration.interventionStep = min(9_600, configuration.steps * 8 / 15)
        }
        guard configuration.minimumValidCycles <= configuration.maximumSeedCount else {
            throw HeadlessExperimentError.invalidArgument(
                "--minimum-valid cannot exceed --max-seeds."
            )
        }
        let recoveryStep = configuration.interventionStep &+ configuration.recoveryDelay
        guard recoveryStep &+ configuration.maturationWindow < configuration.steps else {
            throw HeadlessExperimentError.invalidArgument(
                "The run must extend beyond recovery by more than the maturation window."
            )
        }
        guard configuration.sampleInterval <= configuration.maturationWindow else {
            throw HeadlessExperimentError.invalidArgument(
                "--sample-every cannot exceed --maturation-window."
            )
        }
        if configuration.outputPath.isEmpty {
            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            configuration.outputPath = FileManager.default.currentDirectoryPath +
                "/Experiments/lifecycle-\(timestamp).jsonl"
        }
        return configuration
    }
}

struct LifecycleExperimentHeader: Codable {
    let schemaVersion: Int
    let startedAt: String
    let device: String
    let causalMutation: String
    let targetRule: String
    let stoppingRule: String
    let validCycleRule: String
    let completedCycleRule: String
    let qualificationRule: String
    let configuration: LifecycleExperimentConfiguration
}

struct LifecycleResemblance: Codable, Sendable, Equatable {
    let morphologyDistance: Double
    let morphologyResemblance: Double
    let functionalDistance: Double
    let functionalResemblance: Double
}

struct LifecycleSeedRecord: Codable {
    let attemptIndex: Int
    let seed: UInt32
    let eligibleAtBaseline: Bool
    let observedBaselineMatched: Bool
    let woundDeliveredToTarget: Bool
    let validForEstimation: Bool
    let recoveredAfterChallenge: Bool
    let reproducedAfterRecovery: Bool
    let postRecoveryFissionCount: Int
    let grandchildMatured: Bool
    let completedLifecycle: Bool
    let targetBirthID: UInt32?
    let grandchildBirthID: UInt32?
    let grandchildBirthStep: UInt32?
    let baseline: RegenerationTargetSnapshot
    let controlRecovery: RegenerationTargetSnapshot?
    let treatmentRecovery: RegenerationTargetSnapshot?
    let grandchildSnapshots: [ExperimentComponentSnapshot]
    let parentGrandchildResemblance: LifecycleResemblance?
    let controlInvariants: ExperimentInvariantReport
    let treatmentInvariants: ExperimentInvariantReport
}

struct LifecycleExperimentSummary: Codable {
    let completed: Bool
    let reachedPredeclaredValidCount: Bool
    let elapsedSeconds: Double
    let attemptedSeedCount: Int
    let maximumSeedCount: Int
    let minimumValidCycles: Int
    let eligibleSeedCount: Int
    let validCycleCount: Int
    let ineligibleSeedCount: Int
    let invalidSeedCount: Int
    let recoveredTargetCount: Int
    let reproducedTargetCount: Int
    let maturedGrandchildCount: Int
    let completedLifecycleCount: Int
    let recovery: BinomialProportionEstimate
    let recoveryQualification: EvidenceClaim
    let lifecycleCompletion: BinomialProportionEstimate
    let lifecycleQualification: EvidenceClaim
    let meanMorphologyResemblance: Double?
    let meanFunctionalResemblance: Double?
    let outputPath: String
}

enum LifecycleExperimentCLI {
    @MainActor
    static func run(arguments: ArraySlice<String>) throws {
        let configuration = try LifecycleExperimentConfiguration.parse(arguments)
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
        try journal.append("lifecycle_header", LifecycleExperimentHeader(
            schemaVersion: 1,
            startedAt: ISO8601DateFormatter().string(from: Date()),
            device: device.name,
            causalMutation: "None. The protocol reads existing lineage events and component physiology; no observer result is bound to a simulation kernel.",
            targetRule: "Use the same deterministic regenerative-descendant target selected by the paired sham and wound branches at the final baseline step.",
            stoppingRule: "Attempt fixed SplitMix64-derived seeds in order until the predeclared valid-cycle count is reached or maximumSeedCount is exhausted. Stopping never depends on success or resemblance.",
            validCycleRule: "The same target must exist in both baseline branches, receive the treatment wound, and both runs must retain zero invariant flags and absolute energy residual at most 0.001.",
            completedCycleRule: "The wounded target must recover relative to its sham twin, then emit a physical fission whose child remains multicellular, metabolically viable, developmentally restarted, and observed across the maturation window.",
            qualificationRule: "At least minimumValidCycles are required; a two-sided 95% Wilson lower bound above 0.5 supports recovery or lifecycle completion.",
            configuration: configuration
        ))

        let startedAt = CFAbsoluteTimeGetCurrent()
        var attempted = 0
        var eligible = 0
        var valid = 0
        var invalid = 0
        var recovered = 0
        var reproduced = 0
        var matured = 0
        var completed = 0
        var morphologyResemblances: [Double] = []
        var functionalResemblances: [Double] = []
        var usedSeeds: Set<UInt32> = []

        while attempted < configuration.maximumSeedCount &&
            valid < configuration.minimumValidCycles {
            let seed = distinctSeed(
                masterSeed: configuration.masterSeed,
                attemptIndex: attempted,
                used: &usedSeeds
            )
            let control = try renderer.runHeadlessExperiment(
                configuration: runConfiguration(
                    configuration, seed: seed, mode: .shamRegenerativeTarget
                ),
                journal: discardedJournal,
                resultRetention: .samples,
                reportProgress: false
            )
            let treatment = try renderer.runHeadlessExperiment(
                configuration: runConfiguration(
                    configuration, seed: seed, mode: .targetedRegenerativeWound
                ),
                journal: discardedJournal,
                resultRetention: .all,
                reportProgress: false
            )
            guard let controlBaselineSample = control.interventionSample,
                  let treatmentBaselineSample = treatment.interventionSample,
                  let controlFinal = control.summary.finalSample,
                  let treatmentFinal = treatment.summary.finalSample else {
                throw HeadlessExperimentError.missingExperimentSample(
                    "Lifecycle run did not produce baseline and final samples."
                )
            }
            let controlBaseline = RegenerationTargetSnapshot(sample: controlBaselineSample)
            let treatmentBaseline = RegenerationTargetSnapshot(sample: treatmentBaselineSample)
            guard controlBaseline == treatmentBaseline else {
                throw HeadlessExperimentError.pairedBaselineMismatch(seed: seed)
            }
            let isEligible = controlBaseline.present && controlBaseline.birthID != nil
            eligible += isEligible ? 1 : 0
            let recoveryStep = configuration.interventionStep + configuration.recoveryDelay
            let controlRecoverySample = firstSample(atOrAfter: recoveryStep, in: control.samples)
            let treatmentRecoverySample = controlRecoverySample.flatMap { controlSample in
                treatment.samples.first { $0.step == controlSample.step }
            }
            let controlRecovery = controlRecoverySample.map(RegenerationTargetSnapshot.init(sample:))
            let treatmentRecovery = treatmentRecoverySample.map(
                RegenerationTargetSnapshot.init(sample:)
            )
            let woundDelivered = treatment.samples.contains {
                $0.step > configuration.interventionStep && $0.qualificationTargetChallenged
            }
            let invariantValid = controlFinal.invariantReport.flags == 0 &&
                treatmentFinal.invariantReport.flags == 0 &&
                controlFinal.invariantReport.maximumEnergyResidual <= 0.001 &&
                treatmentFinal.invariantReport.maximumEnergyResidual <= 0.001
            let isValid = isEligible && woundDelivered && invariantValid &&
                controlRecovery?.birthID == controlBaseline.birthID &&
                treatmentRecovery?.birthID == controlBaseline.birthID
            valid += isValid ? 1 : 0
            invalid += isEligible && !isValid ? 1 : 0

            let didRecover = isValid && recoveredRelativeToSham(
                treatment: treatmentRecovery,
                control: controlRecovery
            )
            recovered += didRecover ? 1 : 0
            let targetID = controlBaseline.birthID
            let candidateFissions = treatment.events.filter {
                $0.type == "fission" && $0.parentBirthID == targetID &&
                    UInt64($0.step) >= (treatmentRecovery?.step ?? .max)
            }.sorted {
                $0.step == $1.step ? $0.sequence < $1.sequence : $0.step < $1.step
            }

            var selectedFission: ExperimentEvent?
            var selectedGrandchildSnapshots: [ExperimentComponentSnapshot] = []
            if didRecover {
                for fission in candidateFissions {
                    let snapshots = stableGrandchildSnapshots(
                        birthID: fission.birthID,
                        bornAt: UInt64(fission.step),
                        configuration: configuration,
                        snapshots: treatment.componentSnapshots
                    )
                    if !snapshots.isEmpty {
                        selectedFission = fission
                        selectedGrandchildSnapshots = snapshots
                        break
                    }
                }
            }
            let didReproduce = didRecover && !candidateFissions.isEmpty
            let grandchildMatured = selectedFission != nil
            let completedLifecycle = didRecover && grandchildMatured
            reproduced += didReproduce ? 1 : 0
            matured += grandchildMatured ? 1 : 0
            completed += completedLifecycle ? 1 : 0

            let resemblance: LifecycleResemblance?
            if let targetID,
               let parentSnapshot = treatment.componentSnapshots.last(where: {
                   $0.birthID == targetID &&
                       $0.step <= (selectedFission.map { UInt64($0.step) } ?? .max)
               }),
               let childSnapshot = selectedGrandchildSnapshots.last {
                resemblance = resemblanceBetween(parent: parentSnapshot, child: childSnapshot)
                if let resemblance {
                    morphologyResemblances.append(resemblance.morphologyResemblance)
                    functionalResemblances.append(resemblance.functionalResemblance)
                }
            } else {
                resemblance = nil
            }
            let reportedFission = selectedFission ?? (didRecover ? candidateFissions.first : nil)
            let reportedGrandchildSnapshots = reportedFission.map { fission in
                treatment.componentSnapshots.filter {
                    $0.birthID == fission.birthID && $0.step >= UInt64(fission.step)
                }.sorted { $0.step < $1.step }
            } ?? []

            let record = LifecycleSeedRecord(
                attemptIndex: attempted,
                seed: seed,
                eligibleAtBaseline: isEligible,
                observedBaselineMatched: true,
                woundDeliveredToTarget: woundDelivered,
                validForEstimation: isValid,
                recoveredAfterChallenge: didRecover,
                reproducedAfterRecovery: didReproduce,
                postRecoveryFissionCount: didRecover ? candidateFissions.count : 0,
                grandchildMatured: grandchildMatured,
                completedLifecycle: completedLifecycle,
                targetBirthID: targetID,
                grandchildBirthID: reportedFission?.birthID,
                grandchildBirthStep: reportedFission?.step,
                baseline: controlBaseline,
                controlRecovery: controlRecovery,
                treatmentRecovery: treatmentRecovery,
                grandchildSnapshots: reportedGrandchildSnapshots,
                parentGrandchildResemblance: resemblance,
                controlInvariants: controlFinal.invariantReport,
                treatmentInvariants: treatmentFinal.invariantReport
            )
            try journal.append("lifecycle_seed", record)
            attempted += 1
            print(
                "lifecycle_seed=\(attempted)/\(configuration.maximumSeedCount) seed=\(seed) " +
                "eligible=\(isEligible ? 1 : 0) valid=\(isValid ? 1 : 0) " +
                "recovered=\(didRecover ? 1 : 0) reproduced=\(didReproduce ? 1 : 0) " +
                "matured=\(grandchildMatured ? 1 : 0)"
            )
        }

        let recoveryEstimate = BinomialQualification.wilson95(
            successes: recovered, trials: valid
        )
        let lifecycleEstimate = BinomialQualification.wilson95(
            successes: completed, trials: valid
        )
        let summary = LifecycleExperimentSummary(
            completed: true,
            reachedPredeclaredValidCount: valid >= configuration.minimumValidCycles,
            elapsedSeconds: CFAbsoluteTimeGetCurrent() - startedAt,
            attemptedSeedCount: attempted,
            maximumSeedCount: configuration.maximumSeedCount,
            minimumValidCycles: configuration.minimumValidCycles,
            eligibleSeedCount: eligible,
            validCycleCount: valid,
            ineligibleSeedCount: attempted - eligible,
            invalidSeedCount: invalid,
            recoveredTargetCount: recovered,
            reproducedTargetCount: reproduced,
            maturedGrandchildCount: matured,
            completedLifecycleCount: completed,
            recovery: recoveryEstimate,
            recoveryQualification: BinomialQualification.evidence(
                recovery: recoveryEstimate,
                minimumTrials: configuration.minimumValidCycles,
                threshold: 0.5
            ),
            lifecycleCompletion: lifecycleEstimate,
            lifecycleQualification: BinomialQualification.evidence(
                recovery: lifecycleEstimate,
                minimumTrials: configuration.minimumValidCycles,
                threshold: 0.5,
                outcomeLabel: "complete-lifecycle",
                validTrialDescription: "lifecycle cycles were observed"
            ),
            meanMorphologyResemblance: mean(morphologyResemblances),
            meanFunctionalResemblance: mean(functionalResemblances),
            outputPath: journal.outputURL.path
        )
        try journal.append("lifecycle_summary", summary)
        print(
            "lifecycle_experiment_complete=1 attempted=\(attempted) valid=\(valid) " +
            "recovered=\(recovered)/\(valid) completed=\(completed)/\(valid) " +
            "qualification=\(summary.lifecycleQualification.state.rawValue) " +
            "output=\(summary.outputPath)"
        )
    }

    private static func runConfiguration(
        _ lifecycle: LifecycleExperimentConfiguration,
        seed: UInt32,
        mode: DamageChallengeMode
    ) -> HeadlessExperimentConfiguration {
        var configuration = HeadlessExperimentConfiguration()
        configuration.seed = seed
        configuration.steps = lifecycle.steps
        configuration.batchSize = lifecycle.batchSize
        configuration.sampleInterval = lifecycle.sampleInterval
        configuration.auditInterval = lifecycle.auditInterval
        configuration.quantumStride = lifecycle.quantumStride
        configuration.strictInvariants = lifecycle.strictInvariants
        configuration.damageChallenge = DamageChallengeSchedule(
            mode: mode,
            interventionStep: lifecycle.interventionStep
        )
        configuration.outputPath = "/dev/null"
        return configuration
    }

    private static func firstSample(
        atOrAfter step: UInt64,
        in samples: [ExperimentSample]
    ) -> ExperimentSample? {
        samples.first { $0.step >= step }
    }

    private static func recoveredRelativeToSham(
        treatment: RegenerationTargetSnapshot?,
        control: RegenerationTargetSnapshot?
    ) -> Bool {
        guard let treatment, let control,
              treatment.present, treatment.homeostatic, control.present else { return false }
        let shapeTolerance = max(abs(control.shapeIndex) * 0.20, 0.15)
        return treatment.cellCount >= control.cellCount * 0.80 &&
            treatment.atp >= control.atp * 0.80 &&
            treatment.integrity >= control.integrity * 0.80 &&
            treatment.stress <= control.stress + 0.15 &&
            abs(treatment.shapeIndex - control.shapeIndex) <= shapeTolerance
    }

    private static func stableGrandchildSnapshots(
        birthID: UInt32,
        bornAt: UInt64,
        configuration: LifecycleExperimentConfiguration,
        snapshots: [ExperimentComponentSnapshot]
    ) -> [ExperimentComponentSnapshot] {
        let viable = snapshots.filter {
            $0.birthID == birthID && $0.step >= bornAt &&
                $0.regeneratedDevelopment && $0.cellCount >= 2 &&
                $0.atp >= 0.08 && $0.integrity >= 0.60 && $0.stress <= 0.35
        }.sorted { $0.step < $1.step }
        guard let first = viable.first, let last = viable.last,
              last.step >= first.step + configuration.maturationWindow else { return [] }
        return viable
    }

    private static func resemblanceBetween(
        parent: ExperimentComponentSnapshot,
        child: ExperimentComponentSnapshot
    ) -> LifecycleResemblance {
        let morphologyDistance = MorphologyDescriptor(values: parent.morphology)
            .distance(to: MorphologyDescriptor(values: child.morphology))
        let parentFunction = MorphologyDescriptor(values: [
            min(parent.atp, 1), min(parent.integrity, 1),
            min(max(1 - parent.stress, 0), 1), min(parent.shapeIndex / 3.5, 1),
            min(Double(parent.cellCount) / 24, 1)
        ])
        let childFunction = MorphologyDescriptor(values: [
            min(child.atp, 1), min(child.integrity, 1),
            min(max(1 - child.stress, 0), 1), min(child.shapeIndex / 3.5, 1),
            min(Double(child.cellCount) / 24, 1)
        ])
        let functionalDistance = parentFunction.distance(to: childFunction)
        return LifecycleResemblance(
            morphologyDistance: morphologyDistance,
            morphologyResemblance: exp(-4 * morphologyDistance),
            functionalDistance: functionalDistance,
            functionalResemblance: exp(-4 * functionalDistance)
        )
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func distinctSeed(
        masterSeed: UInt32,
        attemptIndex: Int,
        used: inout Set<UInt32>
    ) -> UInt32 {
        var nonce = UInt64(attemptIndex)
        while true {
            var value = UInt64(masterSeed) &+
                0x9E37_79B9_7F4A_7C15 &* (nonce &+ 1)
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            value ^= value >> 31
            let seed = UInt32(truncatingIfNeeded: value)
            if used.insert(seed).inserted { return seed }
            nonce &+= UInt64(max(1, attemptIndex + 1))
        }
    }
}
