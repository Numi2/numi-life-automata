import Foundation

public struct IndividualityCandidate: Sendable, Equatable {
    public let observation: ComponentObservation
    public let positionX: Double
    public let positionY: Double
    public let isSeparatedDescendant: Bool
    public let environmentalDependence: Double
    public let parentComponentID: UInt64?

    public init(
        observation: ComponentObservation,
        positionX: Double,
        positionY: Double,
        isSeparatedDescendant: Bool,
        environmentalDependence: Double,
        parentComponentID: UInt64? = nil
    ) {
        self.observation = observation
        self.positionX = positionX
        self.positionY = positionY
        self.isSeparatedDescendant = isSeparatedDescendant
        self.environmentalDependence = environmentalDependence.isFinite
            ? environmentalDependence : 0
        self.parentComponentID = parentComponentID
    }
}

public struct ResolvedIndividual: Sendable, Equatable {
    public let candidateID: UInt64
    public let partitionLevel: CandidatePartitionLevel
    public let autonomy: AutonomyVector
    public let isSeparatedDescendant: Bool
    public let selfPredictiveInformation: SelfPredictiveInformationEstimate
}

public struct IndividualityObserverResult: Sendable, Equatable {
    public let resolvedIndividuals: [ResolvedIndividual]
    public let endogenousPredictabilityClaim: EvidenceClaim
    public let autonomyClaim: EvidenceClaim
    public let autocorrelationTime: Double
    public let observationWindows: Int

    public var resolvedCellCount: Int {
        resolvedIndividuals.count { $0.partitionLevel == .cell }
    }

    public var resolvedCollectiveCount: Int {
        resolvedIndividuals.count { $0.partitionLevel == .membraneConnectedComponent }
    }

    public var resolvedDescendantCount: Int {
        resolvedIndividuals.count {
            $0.partitionLevel == .membraneConnectedComponent && $0.isSeparatedDescendant
        }
    }
}

/// Observer-only inference over cell and membrane-connected-component partitions.
/// No result from this type is consumed by a causal simulation kernel.
public struct IndividualityObserverEngine: Sendable {
    private struct CandidateKey: Hashable, Sendable {
        let level: CandidatePartitionLevel
        let id: UInt64
    }

    private struct History: Sendable {
        var steps: [UInt64] = []
        var internalState: [Double] = []
        var environment: [Double] = []
        var autonomy: [AutonomyVector] = []
    }

    private struct PersistenceState: Sendable {
        var supportingEvaluations = 0
        var failingEvaluations = 0
        var isResolved = false
    }

    private var histories: [CandidateKey: History] = [:]
    private var predictabilityPersistence: [CandidateKey: PersistenceState] = [:]
    private var autonomyPersistence: [CandidateKey: PersistenceState] = [:]
    private var latestEstimates: [CandidateKey: SelfPredictiveInformationEstimate] = [:]
    private var batchCursor: [CandidatePartitionLevel: Int] = [:]
    private var evaluationCounter = 0

    public init() {}

    public mutating func reset() {
        histories.removeAll(keepingCapacity: true)
        predictabilityPersistence.removeAll(keepingCapacity: true)
        autonomyPersistence.removeAll(keepingCapacity: true)
        latestEstimates.removeAll(keepingCapacity: true)
        batchCursor.removeAll(keepingCapacity: true)
        evaluationCounter = 0
    }

    public mutating func rollback(after committedStep: UInt64) {
        for (key, var history) in histories {
            while history.steps.last.map({ $0 > committedStep }) == true {
                history.steps.removeLast()
                history.internalState.removeLast()
                history.environment.removeLast()
                history.autonomy.removeLast()
            }
            histories[key] = history
        }
        histories = histories.filter { !$0.value.steps.isEmpty }
        predictabilityPersistence.removeAll(keepingCapacity: true)
        autonomyPersistence.removeAll(keepingCapacity: true)
        latestEstimates.removeAll(keepingCapacity: true)
    }

    public mutating func observe(
        _ candidates: [IndividualityCandidate],
        evaluationStride: Int = 1,
        resamples: Int = 48,
        maximumCandidatesPerLevel: Int = 128
    ) -> IndividualityObserverResult? {
        let keyed = candidates.map { candidate in
            (CandidateKey(
                level: candidate.observation.partitionLevel,
                id: candidate.observation.candidateID
            ), candidate)
        }
        let livingKeys = Set(keyed.map(\.0))
        histories = histories.filter { livingKeys.contains($0.key) }
        predictabilityPersistence = predictabilityPersistence.filter {
            livingKeys.contains($0.key)
        }
        autonomyPersistence = autonomyPersistence.filter { livingKeys.contains($0.key) }
        latestEstimates = latestEstimates.filter { livingKeys.contains($0.key) }

        for (key, candidate) in keyed {
            var history = histories[key] ?? History()
            let autonomy = AutonomyVector.measured(
                from: candidate.observation,
                conditionalSelfPredictiveInformation: 0
            )
            history.steps.append(candidate.observation.step)
            history.internalState.append(autonomy.mechanochemicalClosure)
            history.environment.append(candidate.environmentalDependence)
            history.autonomy.append(autonomy)
            if history.steps.count > 256 {
                let excess = history.steps.count - 256
                history.steps.removeFirst(excess)
                history.internalState.removeFirst(excess)
                history.environment.removeFirst(excess)
                history.autonomy.removeFirst(excess)
            }
            histories[key] = history
        }

        evaluationCounter += 1
        guard evaluationCounter.isMultiple(of: max(evaluationStride, 1)) else { return nil }

        let batchSize = max(maximumCandidatesPerLevel, 1)
        let sampled = CandidatePartitionLevel.allCases.flatMap { level -> [(CandidateKey, IndividualityCandidate)] in
            let levelCandidates = keyed.filter { $0.0.level == level }
                .sorted { $0.0.id < $1.0.id }
            guard levelCandidates.count > batchSize else {
                batchCursor[level] = 0
                return levelCandidates
            }
            let start = (batchCursor[level] ?? 0) % levelCandidates.count
            let count = min(batchSize, levelCandidates.count)
            let result = (0..<count).map { levelCandidates[(start + $0) % levelCandidates.count] }
            batchCursor[level] = (start + count) % levelCandidates.count
            return result
        }
        var evaluatedKeys = Set<CandidateKey>()
        for (key, candidate) in sampled {
            guard let history = histories[key],
                  let estimate = IndividualityStatistics.conditionalSelfPredictiveInformation(
                    state: history.internalState,
                    environment: history.environment,
                    resamples: resamples,
                    seed: key.id ^ candidate.observation.step ^
                        (key.level == .cell
                            ? UInt64(0x4345_4c4c) : UInt64(0x434f_4d50))
                  ) else { continue }
            latestEstimates[key] = estimate
            evaluatedKeys.insert(key)
        }

        let keyedCandidates = Dictionary(uniqueKeysWithValues: keyed)
        let nestedKeysByComponent = Dictionary(grouping: keyed.compactMap { key, candidate in
            candidate.parentComponentID.map { ($0, key) }
        }, by: \.0).mapValues { $0.map(\.1) }
        func nestedKeys(for key: CandidateKey, candidate: IndividualityCandidate) -> [CandidateKey] {
            switch key.level {
            case .membraneConnectedComponent:
                nestedKeysByComponent[key.id] ?? []
            case .cell:
                candidate.parentComponentID.map {
                    [CandidateKey(level: .membraneConnectedComponent, id: $0)]
                } ?? []
            }
        }
        func isPredictiveMaximum(
            key: CandidateKey,
            candidate: IndividualityCandidate
        ) -> Bool {
            guard let estimate = latestEstimates[key], estimate.state == .supported,
                  let history = histories[key],
                  Double(history.internalState.count) >= 3 * estimate.autocorrelationTime
            else { return false }
            let nested = nestedKeys(for: key, candidate: candidate)
            guard !nested.isEmpty else { return false }
            return !nested.contains { neighborKey in
                guard let neighborEstimate = latestEstimates[neighborKey] else { return false }
                return neighborEstimate.observed.estimate >= estimate.observed.estimate
            }
        }
        let predictiveKeys = Set(keyed.compactMap { key, candidate in
            isPredictiveMaximum(key: key, candidate: candidate) ? key : nil
        })
        let autonomousKeys = Set(predictiveKeys.filter { key in
            guard let candidate = keyedCandidates[key],
                  let history = histories[key],
                  let estimate = latestEstimates[key] else { return false }
            return Self.hasSustainedAutonomyEvidence(
                history: history.autonomy,
                candidate: candidate,
                autocorrelationTime: estimate.autocorrelationTime
            )
        })
        for key in evaluatedKeys {
            guard let estimate = latestEstimates[key] else { continue }
            let onset = max(
                Int(ceil(3 * estimate.autocorrelationTime / Double(max(evaluationStride, 1)))),
                3
            )
            let release = max(
                Int(ceil(2 * estimate.autocorrelationTime / Double(max(evaluationStride, 1)))),
                2
            )
            Self.updatePersistence(
                &predictabilityPersistence,
                key: key,
                supports: predictiveKeys.contains(key),
                onset: onset,
                release: release
            )
            Self.updatePersistence(
                &autonomyPersistence,
                key: key,
                supports: autonomousKeys.contains(key),
                onset: onset,
                release: release
            )
        }
        let predictive = keyed.filter { key, _ in
            predictabilityPersistence[key]?.isResolved == true
        }
        let maxima = keyed.filter { key, _ in
            autonomyPersistence[key]?.isResolved == true
        }
        let resolved = maxima.compactMap { key, candidate -> ResolvedIndividual? in
            guard let estimate = latestEstimates[key] else { return nil }
            return ResolvedIndividual(
                candidateID: key.id,
                partitionLevel: key.level,
                autonomy: AutonomyVector.measured(
                    from: candidate.observation,
                    conditionalSelfPredictiveInformation: estimate.observed.estimate
                ),
                isSeparatedDescendant: candidate.isSeparatedDescendant,
                selfPredictiveInformation: estimate
            )
        }
        let best = resolved.max {
            $0.selfPredictiveInformation.observed.estimate <
                $1.selfPredictiveInformation.observed.estimate
        }
        let bestPredictive = predictive.compactMap { key, candidate -> ResolvedIndividual? in
            guard let estimate = latestEstimates[key] else { return nil }
            return ResolvedIndividual(
                candidateID: key.id,
                partitionLevel: key.level,
                autonomy: AutonomyVector.measured(
                    from: candidate.observation,
                    conditionalSelfPredictiveInformation: estimate.observed.estimate
                ),
                isSeparatedDescendant: candidate.isSeparatedDescendant,
                selfPredictiveInformation: estimate
            )
        }.max {
            $0.selfPredictiveInformation.observed.estimate <
                $1.selfPredictiveInformation.observed.estimate
        }
        let predictabilityClaim: EvidenceClaim
        if let bestPredictive {
            predictabilityClaim = EvidenceClaim(
                state: .supported,
                estimate: bestPredictive.selfPredictiveInformation.observed,
                nullUpperBound: bestPredictive.selfPredictiveInformation.shuffledNull.upper,
                reason: "A persistent nested-partition maximum of conditional self-predictive information exceeds an autocorrelation-preserving block-shuffled null."
            )
        } else {
            predictabilityClaim = EvidenceClaim(
                state: latestEstimates.isEmpty ? .inconclusive : .notSupported,
                estimate: nil,
                nullUpperBound: nil,
                reason: latestEstimates.isEmpty
                    ? "Fewer than three empirical autocorrelation windows are available."
                    : "No nested partition remains above its block-shuffled null for the required evidence windows."
            )
        }
        let claim: EvidenceClaim
        if let best {
            claim = EvidenceClaim(
                state: .supported,
                estimate: best.selfPredictiveInformation.observed,
                nullUpperBound: best.selfPredictiveInformation.shuffledNull.upper,
                reason: "A persistent nested partition independently maintains energetic uptake, boundary repair, a closed strain-Ca*-ERK*-traction loop, and endogenous predictability. Multicellular partitions additionally sustain junction-mediated cooperation."
            )
        } else {
            claim = EvidenceClaim(
                state: latestEstimates.isEmpty ? .inconclusive : .notSupported,
                estimate: nil,
                nullUpperBound: nil,
                reason: latestEstimates.isEmpty
                    ? "Fewer than three empirical autocorrelation windows are available."
                    : "No current partition jointly sustains energetic, boundary, mechanochemical, cooperation, and endogenous evidence."
            )
        }
        let bestKey = best.map { CandidateKey(level: $0.partitionLevel, id: $0.candidateID) }
        let windows = best.flatMap { individual in
            bestKey.flatMap { key in
                histories[key].map {
                    Int(Double($0.internalState.count) /
                        max(individual.selfPredictiveInformation.autocorrelationTime, 1))
                }
            }
        } ?? 0
        return IndividualityObserverResult(
            resolvedIndividuals: resolved,
            endogenousPredictabilityClaim: predictabilityClaim,
            autonomyClaim: claim,
            autocorrelationTime: best?.selfPredictiveInformation.autocorrelationTime ?? 0,
            observationWindows: windows
        )
    }

    private static func updatePersistence(
        _ states: inout [CandidateKey: PersistenceState],
        key: CandidateKey,
        supports: Bool,
        onset: Int,
        release: Int
    ) {
        var state = states[key] ?? PersistenceState()
        if supports {
            state.supportingEvaluations += 1
            state.failingEvaluations = 0
            if state.supportingEvaluations >= onset { state.isResolved = true }
        } else {
            state.supportingEvaluations = 0
            state.failingEvaluations += 1
            if state.failingEvaluations >= release { state.isResolved = false }
        }
        states[key] = state
    }

    private static func hasSustainedAutonomyEvidence(
        history: [AutonomyVector],
        candidate: IndividualityCandidate,
        autocorrelationTime: Double
    ) -> Bool {
        if candidate.observation.partitionLevel == .membraneConnectedComponent,
           candidate.observation.cellCount < 2 { return false }
        let windowLength = min(
            history.count,
            max(Int(ceil(3 * autocorrelationTime)), 16)
        )
        guard windowLength >= 16 else { return false }
        let recent = history.suffix(windowLength)
        let requiredFraction = 0.75
        func supported(_ keyPath: KeyPath<AutonomyVector, Double>, floor: Double) -> Bool {
            let count = recent.count { $0[keyPath: keyPath] > floor }
            return Double(count) / Double(windowLength) >= requiredFraction
        }
        guard supported(\.energeticIndependence, floor: 1e-6),
              supported(\.boundaryMaintenance, floor: 1e-6),
              supported(\.mechanochemicalClosure, floor: 1e-10)
        else { return false }
        if candidate.observation.partitionLevel == .membraneConnectedComponent {
            return supported(\.cooperation, floor: 1e-10)
        }
        return true
    }
}
