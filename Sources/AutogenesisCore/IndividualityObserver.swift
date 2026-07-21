import Foundation

public struct IndividualityCandidate: Sendable, Equatable {
    public let observation: ComponentObservation
    public let positionX: Double
    public let positionY: Double
    public let isSeparatedDescendant: Bool
    public let environmentalDependence: Double

    public init(
        observation: ComponentObservation,
        positionX: Double,
        positionY: Double,
        isSeparatedDescendant: Bool,
        environmentalDependence: Double
    ) {
        self.observation = observation
        self.positionX = positionX
        self.positionY = positionY
        self.isSeparatedDescendant = isSeparatedDescendant
        self.environmentalDependence = environmentalDependence.isFinite
            ? environmentalDependence : 0
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
    }

    private var histories: [CandidateKey: History] = [:]
    private var persistence: [CandidateKey: Int] = [:]
    private var evaluationCounter = 0

    public init() {}

    public mutating func reset() {
        histories.removeAll(keepingCapacity: true)
        persistence.removeAll(keepingCapacity: true)
        evaluationCounter = 0
    }

    public mutating func rollback(after committedStep: UInt64) {
        for (key, var history) in histories {
            while history.steps.last.map({ $0 > committedStep }) == true {
                history.steps.removeLast()
                history.internalState.removeLast()
                history.environment.removeLast()
            }
            histories[key] = history
        }
        histories = histories.filter { !$0.value.steps.isEmpty }
        persistence.removeAll(keepingCapacity: true)
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
        persistence = persistence.filter { livingKeys.contains($0.key) }

        for (key, candidate) in keyed {
            var history = histories[key] ?? History()
            let autonomy = AutonomyVector.measured(
                from: candidate.observation,
                conditionalSelfPredictiveInformation: 0
            )
            history.steps.append(candidate.observation.step)
            history.internalState.append(autonomy.mechanochemicalClosure)
            history.environment.append(candidate.environmentalDependence)
            if history.steps.count > 256 {
                let excess = history.steps.count - 256
                history.steps.removeFirst(excess)
                history.internalState.removeFirst(excess)
                history.environment.removeFirst(excess)
            }
            histories[key] = history
        }

        evaluationCounter += 1
        guard evaluationCounter.isMultiple(of: max(evaluationStride, 1)) else { return nil }

        let sampled = CandidatePartitionLevel.allCases.flatMap { level in
            keyed.lazy.filter { $0.0.level == level }
                .sorted { $0.0.id < $1.0.id }
                .prefix(max(maximumCandidatesPerLevel, 1))
        }
        var estimates: [CandidateKey: SelfPredictiveInformationEstimate] = [:]
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
            estimates[key] = estimate
        }

        let radiusSquared = 0.08 * 0.08
        let instantaneous = keyed.filter { key, candidate in
            guard let estimate = estimates[key], estimate.state == .supported,
                  let history = histories[key],
                  Double(history.internalState.count) >= 3 * estimate.autocorrelationTime
            else { return false }
            return !keyed.contains { neighborKey, neighbor in
                guard neighborKey != key,
                      let neighborEstimate = estimates[neighborKey] else { return false }
                let dx = neighbor.positionX - candidate.positionX
                let dy = neighbor.positionY - candidate.positionY
                return dx * dx + dy * dy <= radiusSquared &&
                    neighborEstimate.observed.estimate > estimate.observed.estimate
            }
        }
        let instantaneousKeys = Set(instantaneous.map(\.0))
        for (key, _) in keyed {
            persistence[key] = instantaneousKeys.contains(key) ? (persistence[key] ?? 0) + 1 : 0
        }
        let maxima = instantaneous.filter { key, _ in
            guard let estimate = estimates[key] else { return false }
            let required = max(
                Int(ceil(estimate.autocorrelationTime / Double(max(evaluationStride, 1)))),
                1
            )
            return (persistence[key] ?? 0) >= required
        }
        let resolved = maxima.compactMap { key, candidate -> ResolvedIndividual? in
            guard let estimate = estimates[key] else { return nil }
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
        let claim: EvidenceClaim
        if let best {
            claim = EvidenceClaim(
                state: best.selfPredictiveInformation.state,
                estimate: best.selfPredictiveInformation.observed,
                nullUpperBound: best.selfPredictiveInformation.shuffledNull.upper,
                reason: "A persistent local maximum of conditional self-predictive information exceeds an autocorrelation-preserving block-shuffled null."
            )
        } else {
            claim = EvidenceClaim(
                state: estimates.isEmpty ? .inconclusive : .notSupported,
                estimate: nil,
                nullUpperBound: nil,
                reason: estimates.isEmpty
                    ? "Fewer than three empirical autocorrelation windows are available."
                    : "No persistent local maximum exceeds its block-shuffled null."
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
            autonomyClaim: claim,
            autocorrelationTime: best?.selfPredictiveInformation.autocorrelationTime ?? 0,
            observationWindows: windows
        )
    }
}
