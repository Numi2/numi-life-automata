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

    private struct HistorySample: Sendable {
        let step: UInt64
        let internalState: Float
        let environment: Float
        let energeticIndependence: Float
        let boundaryMaintenance: Float
        let mechanochemicalClosure: Float
        let cooperation: Float
    }

    private struct History: Sendable {
        private(set) var samples: [HistorySample] = []
        private var nextWriteIndex = 0

        var count: Int { samples.count }
        var isEmpty: Bool { samples.isEmpty }

        mutating func append(_ sample: HistorySample, capacity: Int) {
            if samples.count < capacity {
                samples.append(sample)
                nextWriteIndex = samples.count == capacity ? 0 : samples.count
                return
            }
            samples[nextWriteIndex] = sample
            nextWriteIndex = (nextWriteIndex + 1) % capacity
        }

        mutating func rollback(after committedStep: UInt64, capacity: Int) {
            let retained = chronologicalSamples.filter { $0.step <= committedStep }
            samples = retained
            nextWriteIndex = samples.count == capacity ? 0 : samples.count
        }

        var inferenceSeries: (state: [Double], environment: [Double]) {
            var state: [Double] = []
            var environment: [Double] = []
            state.reserveCapacity(samples.count)
            environment.reserveCapacity(samples.count)
            for index in samples.indices {
                let sample = chronologicalSample(at: index)
                state.append(Double(sample.internalState))
                environment.append(Double(sample.environment))
            }
            return (state, environment)
        }

        func supportFractions(
            overLast requestedCount: Int
        ) -> (energetic: Double, boundary: Double, mechanochemical: Double, cooperation: Double) {
            let sampleCount = min(max(requestedCount, 0), samples.count)
            guard sampleCount > 0 else { return (0, 0, 0, 0) }
            var energetic = 0
            var boundary = 0
            var mechanochemical = 0
            var cooperation = 0
            for index in (samples.count - sampleCount)..<samples.count {
                let sample = chronologicalSample(at: index)
                if sample.energeticIndependence > 1e-6 { energetic += 1 }
                if sample.boundaryMaintenance > 1e-6 { boundary += 1 }
                if sample.mechanochemicalClosure > 1e-10 { mechanochemical += 1 }
                if sample.cooperation > 1e-10 { cooperation += 1 }
            }
            let denominator = Double(sampleCount)
            return (
                Double(energetic) / denominator,
                Double(boundary) / denominator,
                Double(mechanochemical) / denominator,
                Double(cooperation) / denominator
            )
        }

        private var chronologicalSamples: [HistorySample] {
            samples.indices.map { chronologicalSample(at: $0) }
        }

        private func chronologicalSample(at index: Int) -> HistorySample {
            let start = nextWriteIndex < samples.count ? nextWriteIndex : 0
            return samples[(start + index) % samples.count]
        }
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
    private let maximumTrackedCandidatesPerLevel: Int
    private let historyCapacity: Int

    public init(
        maximumTrackedCandidatesPerLevel: Int = 512,
        historyCapacity: Int = 256
    ) {
        self.maximumTrackedCandidatesPerLevel = max(maximumTrackedCandidatesPerLevel, 1)
        self.historyCapacity = max(historyCapacity, 16)
    }

    /// Observer memory is bounded independently of causal population capacity.
    public var trackedCandidateCount: Int { histories.count }
    public var storedHistorySampleCount: Int {
        histories.values.reduce(into: 0) { $0 += $1.count }
    }

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
            history.rollback(after: committedStep, capacity: historyCapacity)
            histories[key] = history
        }
        histories = histories.filter { !$0.value.isEmpty }
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
        let keyedCandidates = Dictionary(uniqueKeysWithValues: keyed)
        let trackedKeys = selectTrackedKeys(from: keyed, livingKeys: livingKeys)
        histories = histories.filter {
            livingKeys.contains($0.key) && trackedKeys.contains($0.key)
        }
        predictabilityPersistence = predictabilityPersistence.filter {
            livingKeys.contains($0.key) && trackedKeys.contains($0.key)
        }
        autonomyPersistence = autonomyPersistence.filter {
            livingKeys.contains($0.key) && trackedKeys.contains($0.key)
        }
        latestEstimates = latestEstimates.filter {
            livingKeys.contains($0.key) && trackedKeys.contains($0.key)
        }

        let tracked = keyed.filter { trackedKeys.contains($0.0) }
        for (key, candidate) in tracked {
            var history = histories[key] ?? History()
            let autonomy = AutonomyVector.measured(
                from: candidate.observation,
                conditionalSelfPredictiveInformation: 0
            )
            history.append(
                HistorySample(
                    step: candidate.observation.step,
                    internalState: Float(autonomy.mechanochemicalClosure),
                    environment: Float(candidate.environmentalDependence),
                    energeticIndependence: Float(autonomy.energeticIndependence),
                    boundaryMaintenance: Float(autonomy.boundaryMaintenance),
                    mechanochemicalClosure: Float(autonomy.mechanochemicalClosure),
                    cooperation: Float(autonomy.cooperation)
                ),
                capacity: historyCapacity
            )
            histories[key] = history
        }

        evaluationCounter += 1
        guard evaluationCounter.isMultiple(of: max(evaluationStride, 1)) else { return nil }

        let batchSize = max(maximumCandidatesPerLevel, 1)
        let sampled = CandidatePartitionLevel.allCases.flatMap { level -> [(CandidateKey, IndividualityCandidate)] in
            let levelCandidates = tracked.filter { $0.0.level == level }
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
            guard let history = histories[key] else { continue }
            let series = history.inferenceSeries
            guard
                  let estimate = IndividualityStatistics.conditionalSelfPredictiveInformation(
                    state: series.state,
                    environment: series.environment,
                    resamples: resamples,
                    seed: key.id ^ candidate.observation.step ^
                        (key.level == .cell
                            ? UInt64(0x4345_4c4c) : UInt64(0x434f_4d50))
                  ) else { continue }
            latestEstimates[key] = estimate
            evaluatedKeys.insert(key)
        }

        let nestedKeysByComponent = Dictionary(grouping: tracked.compactMap { key, candidate in
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
                  Double(history.count) >= 3 * estimate.autocorrelationTime
            else { return false }
            let nested = nestedKeys(for: key, candidate: candidate).filter {
                latestEstimates[$0] != nil
            }
            guard !nested.isEmpty else { return false }
            return !nested.contains { neighborKey in
                guard let neighborEstimate = latestEstimates[neighborKey] else { return false }
                return neighborEstimate.observed.estimate >= estimate.observed.estimate
            }
        }
        let predictiveKeys = Set(tracked.compactMap { key, candidate in
            isPredictiveMaximum(key: key, candidate: candidate) ? key : nil
        })
        let autonomousKeys = Set(predictiveKeys.filter { key in
            guard let candidate = keyedCandidates[key],
                  let history = histories[key],
                  let estimate = latestEstimates[key] else { return false }
            return Self.hasSustainedAutonomyEvidence(
                history: history,
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
        let predictive = tracked.filter { key, _ in
            predictabilityPersistence[key]?.isResolved == true
        }
        let maxima = tracked.filter { key, _ in
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
                    Int(Double($0.count) /
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

    private func selectTrackedKeys(
        from keyed: [(CandidateKey, IndividualityCandidate)],
        livingKeys: Set<CandidateKey>
    ) -> Set<CandidateKey> {
        let components = keyed.filter {
            $0.0.level == .membraneConnectedComponent
        }
        let selectedComponents = selectStableCohort(
            from: components.map(\.0),
            livingKeys: livingKeys,
            capacity: maximumTrackedCandidatesPerLevel
        )

        // Pair every longitudinal cell trace with a sampled component. This preserves
        // nested-partition comparisons while keeping observer storage population-independent.
        let eligibleCells = keyed.filter { key, candidate in
            key.level == .cell && candidate.parentComponentID.map {
                selectedComponents.contains(CandidateKey(
                    level: .membraneConnectedComponent,
                    id: $0
                ))
            } == true
        }
        let cellsByComponent = Dictionary(grouping: eligibleCells) {
            $0.1.parentComponentID!
        }
        var selectedCells = Set<CandidateKey>()
        for component in selectedComponents.sorted(by: { stableRank($0) < stableRank($1) }) {
            guard let linked = cellsByComponent[component.id],
                  let representative = linked.min(by: {
                      stableRank($0.0) < stableRank($1.0)
                  }) else { continue }
            selectedCells.insert(representative.0)
            if selectedCells.count == maximumTrackedCandidatesPerLevel { break }
        }
        if selectedCells.count < maximumTrackedCandidatesPerLevel {
            let remaining = eligibleCells.map(\.0).filter { !selectedCells.contains($0) }
            let supplemental = selectStableCohort(
                from: remaining,
                livingKeys: livingKeys,
                capacity: maximumTrackedCandidatesPerLevel - selectedCells.count
            )
            selectedCells.formUnion(supplemental)
        }
        return selectedComponents.union(selectedCells)
    }

    private func selectStableCohort(
        from keys: [CandidateKey],
        livingKeys: Set<CandidateKey>,
        capacity: Int
    ) -> Set<CandidateKey> {
        guard capacity > 0 else { return [] }
        let resolved = keys.filter {
            autonomyPersistence[$0]?.isResolved == true ||
                predictabilityPersistence[$0]?.isResolved == true
        }
        let existing = keys.filter {
            histories[$0] != nil && !resolved.contains($0)
        }
        let new = keys.filter {
            livingKeys.contains($0) && histories[$0] == nil && !resolved.contains($0)
        }
        let ordered = [resolved, existing, new].flatMap {
            $0.sorted { stableRank($0) < stableRank($1) }
        }
        return Set(ordered.prefix(capacity))
    }

    private func stableRank(_ key: CandidateKey) -> UInt64 {
        var value = key.id ^ (key.level == .cell
            ? UInt64(0x4345_4c4c_5f4f_4253)
            : UInt64(0x434f_4d50_5f4f_4253))
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
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
        history: History,
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
        let requiredFraction = 0.75
        let support = history.supportFractions(overLast: windowLength)
        guard support.energetic >= requiredFraction,
              support.boundary >= requiredFraction,
              support.mechanochemical >= requiredFraction
        else { return false }
        if candidate.observation.partitionLevel == .membraneConnectedComponent {
            return support.cooperation >= requiredFraction
        }
        return true
    }
}
