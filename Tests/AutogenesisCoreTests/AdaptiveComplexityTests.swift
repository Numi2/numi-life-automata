import Testing
@testable import AutogenesisCore

@Test func dominanceRequiresNoObjectiveToRegress() {
    let strong = FitnessVector(viability: 0.8, adaptiveComplexity: 0.7, recovery: 0.9, novelty: 0.6)
    let weak = FitnessVector(viability: 0.6, adaptiveComplexity: 0.5, recovery: 0.4, novelty: 0.3)
    let tradeoff = FitnessVector(viability: 0.9, adaptiveComplexity: 0.4, recovery: 0.8, novelty: 0.7)

    #expect(strong.dominates(weak))
    #expect(!weak.dominates(strong))
    #expect(!strong.dominates(tradeoff))
    #expect(!tradeoff.dominates(strong))
}

@Test func noveltyRewardsAnIsolatedBehaviorWithoutNamedNiches() {
    var archive = NoveltyArchive(neighbors: 2)
    archive.consider(BehaviorDescriptor(values: [0.1, 0.1]), novelty: 1, viable: true)
    archive.consider(BehaviorDescriptor(values: [0.15, 0.12]), novelty: 1, viable: true)

    let nearby = archive.novelty(of: BehaviorDescriptor(values: [0.12, 0.11]))
    let isolated = archive.novelty(of: BehaviorDescriptor(values: [0.9, 0.9]))

    #expect(isolated > nearby)
}

@Test func adaptiveComplexityRejectsCollapseSaturationAndNoise() {
    let empty = AdaptiveComplexityEvaluator.fitness(metrics: .empty, novelty: 1)
    let saturated = AdaptiveComplexityEvaluator.fitness(
        metrics: sampleMetrics(occupied: 0.99, activity: 0.2, boundary: 0.4, multiscale: 0.4, recovery: 1),
        novelty: 1
    )
    let noisy = AdaptiveComplexityEvaluator.fitness(
        metrics: sampleMetrics(occupied: 0.3, activity: 0.95, boundary: 0.005, multiscale: 0.8, recovery: 0.2),
        novelty: 1
    )
    let organized = AdaptiveComplexityEvaluator.fitness(
        metrics: sampleMetrics(occupied: 0.3, activity: 0.2, boundary: 0.22, multiscale: 0.18, recovery: 0.85),
        novelty: 0.4
    )

    #expect(empty.viability == 0)
    #expect(saturated.viability < organized.viability)
    #expect(noisy.adaptiveComplexity < organized.adaptiveComplexity)
    #expect(organized.recovery > noisy.recovery)
}

@Test func paretoSelectionPreservesDifferentSuccessfulStrategies() {
    var evaluator = AdaptiveComplexityEvaluator(seed: 42, eliteCount: 2)
    let resilient = sampleMetrics(occupied: 0.28, activity: 0.11, boundary: 0.20, multiscale: 0.11, recovery: 0.98)
    let complex = sampleMetrics(occupied: 0.31, activity: 0.28, boundary: 0.28, multiscale: 0.30, recovery: 0.52)
    let collapsed = WorldMetrics.empty
    let decision = evaluator.evaluate([resilient, complex, collapsed])

    #expect(Set(decision.eliteWorlds) == Set([0, 1]))
    #expect(decision.rankedWorlds.last?.worldIndex == 2)
}

@Test func diversificationRequiresViableCoexistingNiches() {
    var branching = sampleMetrics(
        occupied: 0.28,
        activity: 0.16,
        boundary: 0.18,
        multiscale: 0.14,
        recovery: 0.82
    )
    branching.lineageDiversity = 0.68
    branching.nicheDifferentiation = 0.021
    branching.trophicActivity = 0.013

    var monoculture = branching
    monoculture.nicheDifferentiation = 0

    var collapsed = branching
    collapsed.occupiedFraction = 0.001
    collapsed.energyDensity = 0

    let branchingFitness = AdaptiveComplexityEvaluator.fitness(metrics: branching, novelty: 0.4)
    let monocultureFitness = AdaptiveComplexityEvaluator.fitness(metrics: monoculture, novelty: 0.4)
    let collapsedFitness = AdaptiveComplexityEvaluator.fitness(metrics: collapsed, novelty: 0.4)

    #expect(branchingFitness.diversification > 0.2)
    #expect(monocultureFitness.diversification == 0)
    #expect(collapsedFitness.diversification < branchingFitness.diversification)
}

private func sampleMetrics(
    occupied: Double,
    activity: Double,
    boundary: Double,
    multiscale: Double,
    recovery: Double
) -> WorldMetrics {
    WorldMetrics(
        biomassDensity: occupied * 0.7,
        resourceDensity: 0.45,
        energyDensity: occupied * 0.3,
        occupiedFraction: occupied,
        temporalActivity: activity,
        boundaryCoherence: boundary,
        multiscaleDivergence: multiscale,
        recovery: recovery,
        geneticDiversity: 0.12,
        centroidX: 0.5,
        centroidY: 0.5
    )
}
