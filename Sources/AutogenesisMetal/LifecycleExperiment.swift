import AutogenesisCore
import Darwin
import Foundation
import MetalKit

struct LifecycleExperimentConfiguration: Codable, Sendable {
    var masterSeed: UInt32 = 1
    var maximumSeedCount = 128
    var minimumValidCycles = 16
    var steps: UInt64 = 36_000
    var interventionStep: UInt64 = 12_000
    var recoveryDelay: UInt64 = 1_200
    var persistenceWindow: UInt64 = 1_024
    var batchSize = 64
    var sampleInterval: UInt64 = 600
    var auditInterval: UInt64 = 1
    var quantumStride: UInt64 = 3
    var strictInvariants = true
    var allowConcurrent = false
    var outputPath = ""

    static let usage = """
    Usage: NumiAutomata lifeHistory-experiment [options]

      --steps N             Final step for each paired run (default: 36000)
      --intervention-step N Last unwounded baseline step (default: 12000)
      --recovery-delay N    Steps allowed before recovery is assessed (default: 1200)
      --persistence-window N Required stable descendant duration (default: 1024)
      --max-seeds N         Maximum fixed seeds attempted, 4...128 (default: 128)
      --minimum-valid N     Eligible valid cycles required, 1...64 (default: 16)
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
            case "--persistence-window":
                guard let parsed = UInt64(try value(after: argument)), parsed > 0 else {
                    throw HeadlessExperimentError.invalidArgument(
                        "--persistence-window must be positive."
                    )
                }
                configuration.persistenceWindow = parsed
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
            configuration.interventionStep = min(12_000, configuration.steps / 3)
        }
        guard configuration.minimumValidCycles <= configuration.maximumSeedCount else {
            throw HeadlessExperimentError.invalidArgument(
                "--minimum-valid cannot exceed --max-seeds."
            )
        }
        let recoveryStep = configuration.interventionStep &+ configuration.recoveryDelay
        guard recoveryStep &+ configuration.persistenceWindow < configuration.steps else {
            throw HeadlessExperimentError.invalidArgument(
                "The run must extend beyond recovery by more than the persistence window."
            )
        }
        guard configuration.sampleInterval <= configuration.persistenceWindow else {
            throw HeadlessExperimentError.invalidArgument(
                "--sample-every cannot exceed --persistence-window."
            )
        }
        if configuration.outputPath.isEmpty {
            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            configuration.outputPath = FileManager.default.currentDirectoryPath +
                "/Experiments/lifeHistory-\(timestamp).jsonl"
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
    let completedLifecycle: Bool
    let developedMulticellularBody: Bool
    let offspringIndependent: Bool
    let grandchildIndependent: Bool
    let parentSenesced: Bool
    let parentDied: Bool
    let releasedMatterReused: Bool
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
    let independentGrandchildCount: Int
    let completedLifecycleCount: Int
    let twoGenerationCount: Int
    let senescentParentCount: Int
    let recycledMatterReuseCount: Int
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
            schemaVersion: 2,
            startedAt: ISO8601DateFormatter().string(from: Date()),
            device: device.name,
            causalMutation: "None. The protocol reads existing lineage events and component physiology; no observer result is bound to a simulation kernel.",
            targetRule: "Use the same deterministic regenerative-descendant target selected by the paired sham and wound branches at the final baseline step.",
            stoppingRule: "Attempt fixed SplitMix64-derived seeds in order until the predeclared valid-cycle count is reached or maximumSeedCount is exhausted. Stopping never depends on success or resemblance.",
            validCycleRule: "The same target must exist in both baseline branches, receive the treatment wound, and both runs must retain zero invariant flags and absolute energy residual at most 0.001.",
            completedCycleRule: "A single-cell propagule must develop at least four connected differentiated cells, recover from a real wound relative to sham, produce an independently persistent child, and that child must produce an independently persistent grandchild. The original parent must then show three-window damage-linked functional decline, die, release its exact material ledger, and have passively attributed matter taken up by later life. All thresholds classify observations only.",
            qualificationRule: "Run sixteen preregistered valid seeds; at least twelve must complete every conjunction. Wilson intervals are reported descriptively and no observer value is bound to a simulation kernel.",
            configuration: configuration
        ))

        let startedAt = CFAbsoluteTimeGetCurrent()
        var attempted = 0
        var eligible = 0
        var valid = 0
        var invalid = 0
        var recovered = 0
        var reproduced = 0
        var independentGrandchildren = 0
        var completed = 0
        var twoGeneration = 0
        var senescentParents = 0
        var recycledReuse = 0
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
            let targetDevelopmentSnapshots = treatment.componentSnapshots.filter {
                $0.birthID == targetID && $0.step <= configuration.interventionStep &&
                    $0.cellCount >= 4 && $0.meanInternalDomainCount > 0 &&
                    $0.conservedMaterialMass > 0
            }.sorted { $0.step < $1.step }
            let developedMulticellularBody = persistentSnapshots(
                targetDevelopmentSnapshots,
                window: configuration.persistenceWindow
            )
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
            let offspringIndependent = selectedFission != nil
            let childID = selectedFission?.birthID
            let childIndependentAt = selectedGrandchildSnapshots.last?.step
            let secondGenerationFissions = treatment.events.filter {
                $0.type == "fission" && $0.parentBirthID == childID &&
                    UInt64($0.step) >= (childIndependentAt ?? .max)
            }.sorted {
                $0.step == $1.step ? $0.sequence < $1.sequence : $0.step < $1.step
            }
            var selectedGrandchild: ExperimentEvent?
            var secondGenerationSnapshots: [ExperimentComponentSnapshot] = []
            for fission in secondGenerationFissions {
                let snapshots = stableGrandchildSnapshots(
                    birthID: fission.birthID,
                    bornAt: UInt64(fission.step),
                    configuration: configuration,
                    snapshots: treatment.componentSnapshots
                )
                if !snapshots.isEmpty {
                    selectedGrandchild = fission
                    secondGenerationSnapshots = snapshots
                    break
                }
            }
            let grandchildIndependent = selectedGrandchild != nil
            let parentSnapshots = treatment.componentSnapshots.filter {
                $0.birthID == targetID &&
                    $0.step >= (selectedFission.map { UInt64($0.step) } ?? .max)
            }.sorted { $0.step < $1.step }
            let senescence = sustainedSenescence(in: parentSnapshots)
            let parentDeath = treatment.events.first {
                $0.type == "death" && $0.birthID == targetID &&
                    UInt64($0.step) >= (senescence?.step ?? .max)
            }
            let releasedMatterReused = parentDeath.map { death in
                treatment.componentSnapshots.contains {
                    $0.birthID != targetID && $0.step > UInt64(death.step) &&
                        $0.recycledProvenanceMass >= 0.00001 &&
                        $0.dominantRecycledSourceBirthID == targetID
                }
            } ?? false
            let completedLifecycle = developedMulticellularBody && didRecover &&
                offspringIndependent && grandchildIndependent && senescence != nil &&
                parentDeath != nil && releasedMatterReused
            reproduced += didReproduce ? 1 : 0
            independentGrandchildren += grandchildIndependent ? 1 : 0
            completed += completedLifecycle ? 1 : 0
            twoGeneration += grandchildIndependent ? 1 : 0
            senescentParents += senescence != nil ? 1 : 0
            recycledReuse += releasedMatterReused ? 1 : 0

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
                completedLifecycle: completedLifecycle,
                developedMulticellularBody: developedMulticellularBody,
                offspringIndependent: offspringIndependent,
                grandchildIndependent: grandchildIndependent,
                parentSenesced: senescence != nil,
                parentDied: parentDeath != nil,
                releasedMatterReused: releasedMatterReused,
                targetBirthID: targetID,
                grandchildBirthID: selectedGrandchild?.birthID ?? reportedFission?.birthID,
                grandchildBirthStep: selectedGrandchild?.step ?? reportedFission?.step,
                baseline: controlBaseline,
                controlRecovery: controlRecovery,
                treatmentRecovery: treatmentRecovery,
                grandchildSnapshots: secondGenerationSnapshots.isEmpty
                    ? reportedGrandchildSnapshots : secondGenerationSnapshots,
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
                "grandchild_independent=\(grandchildIndependent ? 1 : 0)"
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
            independentGrandchildCount: independentGrandchildren,
            completedLifecycleCount: completed,
            twoGenerationCount: twoGeneration,
            senescentParentCount: senescentParents,
            recycledMatterReuseCount: recycledReuse,
            recovery: recoveryEstimate,
            recoveryQualification: BinomialQualification.evidence(
                recovery: recoveryEstimate,
                minimumTrials: configuration.minimumValidCycles,
                threshold: 0.5
            ),
            lifecycleCompletion: lifecycleEstimate,
            lifecycleQualification: EvidenceClaim(
                state: valid >= 16 && completed >= 12 ? .supported : .inconclusive,
                estimate: ConfidenceInterval(
                    estimate: lifecycleEstimate.estimate,
                    lower: lifecycleEstimate.lower,
                    upper: lifecycleEstimate.upper,
                    confidenceLevel: lifecycleEstimate.confidenceLevel,
                    effectiveSampleCount: Double(lifecycleEstimate.trials)
                ),
                nullUpperBound: 0.5,
                reason: valid >= 16 && completed >= 12
                    ? "At least 12 of 16 preregistered valid seeds completed the full two-generation lifecycle, senescence, death, and matter-reuse conjunction."
                    : "Qualification requires 16 valid seeds and at least 12 complete conjunctions.",
                timeBasis: .accumulatedHistory
            ),
            meanMorphologyResemblance: mean(morphologyResemblances),
            meanFunctionalResemblance: mean(functionalResemblances),
            outputPath: journal.outputURL.path
        )
        try journal.append("lifecycle_summary", summary)
        let resultCounts = "recovered=\(recovered)/\(valid) completed=\(completed)/\(valid)"
        let qualification = summary.lifecycleQualification.state.rawValue
        print("lifecycle_experiment_complete=1 attempted=\(attempted) valid=\(valid) " +
            resultCounts + " qualification=\(qualification) output=\(summary.outputPath)")
    }

    private static func runConfiguration(
        _ lifeHistory: LifecycleExperimentConfiguration,
        seed: UInt32,
        mode: DamageChallengeMode
    ) -> HeadlessExperimentConfiguration {
        var configuration = HeadlessExperimentConfiguration()
        configuration.seed = seed
        configuration.steps = lifeHistory.steps
        configuration.batchSize = lifeHistory.batchSize
        configuration.sampleInterval = lifeHistory.sampleInterval
        configuration.auditInterval = lifeHistory.auditInterval
        configuration.quantumStride = lifeHistory.quantumStride
        configuration.strictInvariants = lifeHistory.strictInvariants
        configuration.damageChallenge = DamageChallengeSchedule(
            mode: mode,
            interventionStep: lifeHistory.interventionStep
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
              last.step >= first.step + configuration.persistenceWindow else { return [] }
        return viable
    }

    private static func persistentSnapshots(
        _ snapshots: [ExperimentComponentSnapshot],
        window: UInt64
    ) -> Bool {
        guard let first = snapshots.first, let last = snapshots.last else { return false }
        return last.step >= first.step + window
    }

    private static func sustainedSenescence(
        in snapshots: [ExperimentComponentSnapshot]
    ) -> ExperimentComponentSnapshot? {
        guard snapshots.count >= 3 else { return nil }
        var peakFunction = 0.0
        for snapshot in snapshots {
            let function = snapshot.replicationActivity + snapshot.maintenanceActivity +
                snapshot.signalActivity + snapshot.constructionActivity
            peakFunction = max(peakFunction, function)
        }
        guard peakFunction > 0.01 else { return nil }
        for end in 2..<snapshots.count {
            let window = Array(snapshots[(end - 2)...end])
            let functions = window.map {
                $0.replicationActivity + $0.maintenanceActivity +
                    $0.signalActivity + $0.constructionActivity
            }
            let burdens = window.map {
                max($0.proteostasisBurden, $0.replicationBurden * 0.01)
            }
            let declining = functions.allSatisfy { $0 <= peakFunction * 0.72 }
            let damageRising = burdens[1] > burdens[0] && burdens[2] > burdens[1]
            if declining && damageRising { return window.last }
        }
        return nil
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
