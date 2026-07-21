import Foundation

public enum CandidatePartitionLevel: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case cell
    case membraneConnectedComponent
}

public enum EvidenceState: String, Codable, Sendable, Equatable {
    case supported
    case inconclusive
    case notSupported
}

public enum EvidenceTimeBasis: String, Codable, Sendable, Equatable {
    case currentPopulation
    case accumulatedHistory
}

public struct ConfidenceInterval: Codable, Sendable, Equatable {
    public let estimate: Double
    public let lower: Double
    public let upper: Double
    public let confidenceLevel: Double
    public let effectiveSampleCount: Double

    public init(
        estimate: Double,
        lower: Double,
        upper: Double,
        confidenceLevel: Double = 0.95,
        effectiveSampleCount: Double
    ) {
        self.estimate = estimate
        self.lower = lower
        self.upper = upper
        self.confidenceLevel = confidenceLevel
        self.effectiveSampleCount = effectiveSampleCount
    }
}

/// Measurements copied from the causal simulation. This type is intentionally
/// absent from every Metal binding so inferred individuality cannot alter physics.
public struct ComponentObservation: Codable, Sendable, Equatable {
    public let step: UInt64
    public let candidateID: UInt64
    public let partitionLevel: CandidatePartitionLevel
    public let cellCount: Int
    public let harvestedATP: Double
    public let importedATP: Double
    public let repairFlux: Double
    public let membraneIntegrity: Double
    public let exposedPerimeter: Double
    public let damageFlux: Double
    public let membraneTurnover: Double
    public let strainToCalcium: Double
    public let calciumToERK: Double
    public let erkToTraction: Double
    public let tractionToStrain: Double
    public let junctionTransmission: Double
    public let atpSharing: Double
    public let rejection: Double
    public let withinComponentReplicationAdvantage: Double
    public let descendantRepresentation: Double
    public let parentResemblance: Double

    public init(
        step: UInt64,
        candidateID: UInt64,
        partitionLevel: CandidatePartitionLevel,
        cellCount: Int,
        harvestedATP: Double,
        importedATP: Double,
        repairFlux: Double,
        membraneIntegrity: Double,
        exposedPerimeter: Double,
        damageFlux: Double,
        membraneTurnover: Double,
        strainToCalcium: Double,
        calciumToERK: Double,
        erkToTraction: Double,
        tractionToStrain: Double,
        junctionTransmission: Double,
        atpSharing: Double,
        rejection: Double,
        withinComponentReplicationAdvantage: Double,
        descendantRepresentation: Double,
        parentResemblance: Double
    ) {
        self.step = step
        self.candidateID = candidateID
        self.partitionLevel = partitionLevel
        self.cellCount = cellCount
        self.harvestedATP = harvestedATP
        self.importedATP = importedATP
        self.repairFlux = repairFlux
        self.membraneIntegrity = membraneIntegrity
        self.exposedPerimeter = exposedPerimeter
        self.damageFlux = damageFlux
        self.membraneTurnover = membraneTurnover
        self.strainToCalcium = strainToCalcium
        self.calciumToERK = calciumToERK
        self.erkToTraction = erkToTraction
        self.tractionToStrain = tractionToStrain
        self.junctionTransmission = junctionTransmission
        self.atpSharing = atpSharing
        self.rejection = rejection
        self.withinComponentReplicationAdvantage = withinComponentReplicationAdvantage
        self.descendantRepresentation = descendantRepresentation
        self.parentResemblance = parentResemblance
    }
}

public struct AutonomyVector: Codable, Sendable, Equatable {
    public let energeticIndependence: Double
    public let boundaryMaintenance: Double
    public let mechanochemicalClosure: Double
    public let endogenousDetermination: Double
    public let cooperation: Double
    public let conflict: Double
    public let heredity: Double

    public init(
        energeticIndependence: Double,
        boundaryMaintenance: Double,
        mechanochemicalClosure: Double,
        endogenousDetermination: Double,
        cooperation: Double,
        conflict: Double,
        heredity: Double
    ) {
        self.energeticIndependence = Self.unit(energeticIndependence)
        self.boundaryMaintenance = Self.unit(boundaryMaintenance)
        self.mechanochemicalClosure = Self.unit(mechanochemicalClosure)
        self.endogenousDetermination = max(endogenousDetermination, 0)
        self.cooperation = Self.unit(cooperation)
        self.conflict = Self.unit(conflict)
        self.heredity = Self.unit(heredity)
    }

    public static func measured(
        from observation: ComponentObservation,
        conditionalSelfPredictiveInformation: Double
    ) -> Self {
        let localATP = max(observation.harvestedATP, 0)
        let importedATP = max(observation.importedATP, 0)
        let energeticIndependence = localATP / max(localATP + importedATP, 1e-12)
        let maintainedBoundary = max(observation.repairFlux, 0) *
            max(observation.membraneIntegrity, 0) * max(observation.exposedPerimeter, 0)
        let boundaryDemand = maintainedBoundary + max(observation.damageFlux, 0) +
            max(observation.membraneTurnover, 0)
        let boundaryMaintenance = maintainedBoundary / max(boundaryDemand, 1e-12)
        let loopTerms = [
            observation.strainToCalcium,
            observation.calciumToERK,
            observation.erkToTraction,
            observation.tractionToStrain
        ].map { max($0, 0) }
        let mechanochemicalClosure = loopTerms.contains(0) ? 0 :
            pow(loopTerms.reduce(1, *), 1 / Double(loopTerms.count))
        let cooperation = max(observation.atpSharing, 0) +
            max(observation.junctionTransmission, 0)
        let conflict = max(observation.rejection, 0) +
            max(observation.withinComponentReplicationAdvantage, 0)
        return Self(
            energeticIndependence: energeticIndependence,
            boundaryMaintenance: boundaryMaintenance,
            mechanochemicalClosure: mechanochemicalClosure,
            endogenousDetermination: conditionalSelfPredictiveInformation,
            cooperation: cooperation / (1 + cooperation),
            conflict: conflict / (1 + conflict),
            heredity: observation.parentResemblance
        )
    }

    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

public struct ScalarDistribution: Codable, Sendable, Equatable {
    public let count: Int
    public let mean: Double
    public let standardDeviation: Double
    public let fifthPercentile: Double
    public let median: Double
    public let ninetyFifthPercentile: Double

    public init(_ values: [Double]) {
        let finite = values.filter(\.isFinite).sorted()
        let computedMean = finite.isEmpty ? 0 : finite.reduce(0, +) / Double(finite.count)
        count = finite.count
        mean = computedMean
        standardDeviation = finite.isEmpty ? 0 : sqrt(finite.reduce(0.0) {
            $0 + pow($1 - computedMean, 2)
        } / Double(finite.count))
        fifthPercentile = Self.quantile(finite, probability: 0.05)
        median = Self.quantile(finite, probability: 0.5)
        ninetyFifthPercentile = Self.quantile(finite, probability: 0.95)
    }

    private static func quantile(_ sorted: [Double], probability: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let coordinate = probability * Double(sorted.count - 1)
        let lower = Int(floor(coordinate))
        let upper = Int(ceil(coordinate))
        if lower == upper { return sorted[lower] }
        return sorted[lower] + (sorted[upper] - sorted[lower]) *
            (coordinate - Double(lower))
    }
}

public struct AutonomyDistribution: Codable, Sendable, Equatable {
    public let energeticIndependence: ScalarDistribution
    public let boundaryMaintenance: ScalarDistribution
    public let mechanochemicalClosure: ScalarDistribution
    public let endogenousDetermination: ScalarDistribution
    public let cooperation: ScalarDistribution
    public let conflict: ScalarDistribution
    public let heredity: ScalarDistribution

    public init(vectors: [AutonomyVector]) {
        energeticIndependence = ScalarDistribution(vectors.map(\.energeticIndependence))
        boundaryMaintenance = ScalarDistribution(vectors.map(\.boundaryMaintenance))
        mechanochemicalClosure = ScalarDistribution(vectors.map(\.mechanochemicalClosure))
        endogenousDetermination = ScalarDistribution(vectors.map(\.endogenousDetermination))
        cooperation = ScalarDistribution(vectors.map(\.cooperation))
        conflict = ScalarDistribution(vectors.map(\.conflict))
        heredity = ScalarDistribution(vectors.map(\.heredity))
    }
}

public struct SelectionPartition: Codable, Sendable, Equatable {
    public let betweenComponentSelection: Double
    public let withinComponentSelection: Double
    public let transmissionChange: Double
    public let covarianceSampleCount: Int
    public let betweenComponentConfidence: ConfidenceInterval?
    public let withinComponentConfidence: ConfidenceInterval?
    public let transmissionConfidence: ConfidenceInterval?
    public let collectiveHeritability: ConfidenceInterval?
    public let independentDescendantCount: Int
    public let transmittedVariantCount: Int

    public init(
        betweenComponentSelection: Double,
        withinComponentSelection: Double,
        transmissionChange: Double,
        covarianceSampleCount: Int,
        betweenComponentConfidence: ConfidenceInterval? = nil,
        withinComponentConfidence: ConfidenceInterval? = nil,
        transmissionConfidence: ConfidenceInterval? = nil,
        collectiveHeritability: ConfidenceInterval? = nil,
        independentDescendantCount: Int = 0,
        transmittedVariantCount: Int = 0
    ) {
        self.betweenComponentSelection = betweenComponentSelection
        self.withinComponentSelection = withinComponentSelection
        self.transmissionChange = transmissionChange
        self.covarianceSampleCount = covarianceSampleCount
        self.betweenComponentConfidence = betweenComponentConfidence
        self.withinComponentConfidence = withinComponentConfidence
        self.transmissionConfidence = transmissionConfidence
        self.collectiveHeritability = collectiveHeritability
        self.independentDescendantCount = independentDescendantCount
        self.transmittedVariantCount = transmittedVariantCount
    }
}

public struct EvidenceClaim: Codable, Sendable, Equatable {
    public let state: EvidenceState
    public let estimate: ConfidenceInterval?
    public let nullUpperBound: Double?
    public let reason: String
    public let timeBasis: EvidenceTimeBasis

    public init(
        state: EvidenceState,
        estimate: ConfidenceInterval?,
        nullUpperBound: Double?,
        reason: String,
        timeBasis: EvidenceTimeBasis = .currentPopulation
    ) {
        self.state = state
        self.estimate = estimate
        self.nullUpperBound = nullUpperBound
        self.reason = reason
        self.timeBasis = timeBasis
    }
}

public struct IndividualityEvidence: Codable, Sendable, Equatable {
    public let endogenousPredictability: EvidenceClaim
    public let mechanochemicalAutonomy: EvidenceClaim
    public let physicalDescent: EvidenceClaim
    public let heritableVariation: EvidenceClaim
    public let differentialTransmission: EvidenceClaim
    public let darwinianEvolution: EvidenceClaim
    public let collectiveLevelIndividuality: EvidenceClaim
    public let selection: SelectionPartition
    public let autocorrelationTime: Double
    public let observationWindows: Int

    public init(
        endogenousPredictability: EvidenceClaim? = nil,
        mechanochemicalAutonomy: EvidenceClaim,
        physicalDescent: EvidenceClaim,
        heritableVariation: EvidenceClaim,
        differentialTransmission: EvidenceClaim,
        darwinianEvolution: EvidenceClaim,
        collectiveLevelIndividuality: EvidenceClaim,
        selection: SelectionPartition,
        autocorrelationTime: Double,
        observationWindows: Int
    ) {
        self.endogenousPredictability = endogenousPredictability ?? mechanochemicalAutonomy
        self.mechanochemicalAutonomy = mechanochemicalAutonomy
        self.physicalDescent = physicalDescent
        self.heritableVariation = heritableVariation
        self.differentialTransmission = differentialTransmission
        self.darwinianEvolution = darwinianEvolution
        self.collectiveLevelIndividuality = collectiveLevelIndividuality
        self.selection = selection
        self.autocorrelationTime = autocorrelationTime
        self.observationWindows = observationWindows
    }

    public static let inconclusive = IndividualityEvidence(
        endogenousPredictability: EvidenceClaim(
            state: .inconclusive, estimate: nil, nullUpperBound: nil,
            reason: "Insufficient autocorrelation-adjusted observations."
        ),
        mechanochemicalAutonomy: EvidenceClaim(
            state: .inconclusive, estimate: nil, nullUpperBound: nil,
            reason: "Energetic, boundary, mechanochemical, and endogenous evidence are unresolved."
        ),
        physicalDescent: EvidenceClaim(
            state: .inconclusive, estimate: nil, nullUpperBound: nil,
            reason: "No independently separated descendant sample.",
            timeBasis: .accumulatedHistory
        ),
        heritableVariation: EvidenceClaim(
            state: .inconclusive, estimate: nil, nullUpperBound: nil,
            reason: "No inherited program variant has been transmitted to a separated component.",
            timeBasis: .accumulatedHistory
        ),
        differentialTransmission: EvidenceClaim(
            state: .inconclusive, estimate: nil, nullUpperBound: nil,
            reason: "Differential program transmission has not been resolved statistically.",
            timeBasis: .accumulatedHistory
        ),
        darwinianEvolution: EvidenceClaim(
            state: .inconclusive, estimate: nil, nullUpperBound: nil,
            reason: "Physical descent, heritable variation, and differential transmission must all be supported.",
            timeBasis: .accumulatedHistory
        ),
        collectiveLevelIndividuality: EvidenceClaim(
            state: .inconclusive, estimate: nil, nullUpperBound: nil,
            reason: "Between-component selection and collective heredity are unresolved.",
            timeBasis: .accumulatedHistory
        ),
        selection: SelectionPartition(
            betweenComponentSelection: 0,
            withinComponentSelection: 0,
            transmissionChange: 0,
            covarianceSampleCount: 0
        ),
        autocorrelationTime: 0,
        observationWindows: 0
    )
}

public enum EvolutionaryEvidence {
    public static func evaluate(
        selection: SelectionPartition,
        maximumComponentDescentDepth: UInt32,
        conservationValid: Bool
    ) -> (
        physicalDescent: EvidenceClaim,
        heritableVariation: EvidenceClaim,
        differentialTransmission: EvidenceClaim,
        darwinianEvolution: EvidenceClaim
    ) {
        let descentSupported = selection.independentDescendantCount > 0 &&
            maximumComponentDescentDepth > 0
        let physicalDescent = EvidenceClaim(
            state: descentSupported ? .supported : .inconclusive,
            estimate: nil,
            nullUpperBound: nil,
            reason: descentSupported
                ? "Inherited programs remain represented after independent physical separation."
                : "No independently separated descendant currently carries a transmitted program.",
            timeBasis: .accumulatedHistory
        )
        let variationSupported = selection.transmittedVariantCount > 0
        let heritableVariation = EvidenceClaim(
            state: variationSupported ? .supported : .inconclusive,
            estimate: nil,
            nullUpperBound: nil,
            reason: variationSupported
                ? "At least one mutated program is represented in an independently separated descendant."
                : "Mutation alone is insufficient; no variant has yet been transmitted through physical descent.",
            timeBasis: .accumulatedHistory
        )
        let confidenceIntervals = [
            selection.betweenComponentConfidence,
            selection.withinComponentConfidence,
            selection.transmissionConfidence
        ].compactMap { $0 }
        let nonzeroIntervals = confidenceIntervals.filter {
            $0.lower > 0 || $0.upper < 0
        }
        let transmissionSupported = selection.covarianceSampleCount >= 8 &&
            !nonzeroIntervals.isEmpty
        let differentialTransmission = EvidenceClaim(
            state: conservationValid
                ? (transmissionSupported ? .supported : .inconclusive)
                : .notSupported,
            estimate: nonzeroIntervals.first,
            nullUpperBound: 0,
            reason: !conservationValid
                ? "Conservation or ownership invariant failure invalidates selection inference."
                : transmissionSupported
                    ? "A multilevel Price term has a nonzero 95% bootstrap interval across transmitted descendants."
                    : "Differential transmission requires at least eight contributing parent-component samples and a nonzero 95% interval.",
            timeBasis: .accumulatedHistory
        )
        let darwinianSupported = descentSupported && variationSupported &&
            transmissionSupported && conservationValid
        let darwinianEvolution = EvidenceClaim(
            state: conservationValid
                ? (darwinianSupported ? .supported : .inconclusive)
                : .notSupported,
            estimate: differentialTransmission.estimate,
            nullUpperBound: 0,
            reason: darwinianSupported
                ? "Physical descent, inherited variation, and differential transmission are independently supported."
                : "Darwinian evolution is not claimed until descent, heritable variation, and differential transmission are all supported.",
            timeBasis: .accumulatedHistory
        )
        return (
            physicalDescent,
            heritableVariation,
            differentialTransmission,
            darwinianEvolution
        )
    }
}

public struct RendererRuntimeTelemetry: Codable, Sendable, Equatable {
    public let scheduledStep: UInt64
    public let gpuCompletedStep: UInt64
    public let scientificallyCommittedStep: UInt64
    public let stepsPerSecond: Double
    public let unfinishedCommandBuffers: Int
    public let maximumCommandBuffers: Int
    public let checkpointStep: UInt64
    public let lastRestoredCheckpointStep: UInt64?
    public let recoveryCount: UInt32
    public let lastError: String?

    public init(
        scheduledStep: UInt64,
        gpuCompletedStep: UInt64,
        scientificallyCommittedStep: UInt64,
        stepsPerSecond: Double,
        unfinishedCommandBuffers: Int,
        maximumCommandBuffers: Int,
        checkpointStep: UInt64,
        lastRestoredCheckpointStep: UInt64?,
        recoveryCount: UInt32,
        lastError: String?
    ) {
        self.scheduledStep = scheduledStep
        self.gpuCompletedStep = gpuCompletedStep
        self.scientificallyCommittedStep = scientificallyCommittedStep
        self.stepsPerSecond = stepsPerSecond
        self.unfinishedCommandBuffers = unfinishedCommandBuffers
        self.maximumCommandBuffers = maximumCommandBuffers
        self.checkpointStep = checkpointStep
        self.lastRestoredCheckpointStep = lastRestoredCheckpointStep
        self.recoveryCount = recoveryCount
        self.lastError = lastError
    }

    public static let idle = RendererRuntimeTelemetry(
        scheduledStep: 0,
        gpuCompletedStep: 0,
        scientificallyCommittedStep: 0,
        stepsPerSecond: 0,
        unfinishedCommandBuffers: 0,
        maximumCommandBuffers: 3,
        checkpointStep: 0,
        lastRestoredCheckpointStep: nil,
        recoveryCount: 0,
        lastError: nil
    )
}
