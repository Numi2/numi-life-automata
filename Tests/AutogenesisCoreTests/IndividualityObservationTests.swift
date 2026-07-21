import Foundation
import Testing
@testable import AutogenesisCore

struct IndividualityObservationTests {
    @Test
    func autonomyRemainsAVectorRatherThanCollapsingIntoFitness() {
        let observation = ComponentObservation(
            step: 1_200,
            candidateID: 7,
            partitionLevel: .membraneConnectedComponent,
            cellCount: 9,
            harvestedATP: 0.8,
            importedATP: 0.2,
            repairFlux: 0.4,
            membraneIntegrity: 0.9,
            exposedPerimeter: 1.2,
            damageFlux: 0.1,
            membraneTurnover: 0.05,
            strainToCalcium: 0.5,
            calciumToERK: 0.4,
            erkToTraction: 0.3,
            tractionToStrain: 0.2,
            junctionTransmission: 0.2,
            atpSharing: 0.3,
            rejection: 0.1,
            withinComponentReplicationAdvantage: 0.05,
            descendantRepresentation: 0.6,
            parentResemblance: 0.75
        )

        let vector = AutonomyVector.measured(
            from: observation,
            conditionalSelfPredictiveInformation: 0.18
        )

        #expect(abs(vector.energeticIndependence - 0.8) < 1e-12)
        #expect(vector.boundaryMaintenance > 0.7)
        #expect(vector.mechanochemicalClosure > 0)
        #expect(vector.endogenousDetermination == 0.18)
        #expect(vector.conflict < vector.cooperation)
        #expect(vector.heredity == 0.75)
    }

    @Test
    func absentCausalLinkBreaksMechanochemicalClosure() {
        let observation = ComponentObservation(
            step: 20,
            candidateID: 1,
            partitionLevel: .cell,
            cellCount: 1,
            harvestedATP: 1,
            importedATP: 0,
            repairFlux: 0.2,
            membraneIntegrity: 0.8,
            exposedPerimeter: 0.4,
            damageFlux: 0,
            membraneTurnover: 0,
            strainToCalcium: 0.4,
            calciumToERK: 0,
            erkToTraction: 0.4,
            tractionToStrain: 0.4,
            junctionTransmission: 0,
            atpSharing: 0,
            rejection: 0,
            withinComponentReplicationAdvantage: 0,
            descendantRepresentation: 0,
            parentResemblance: 0
        )

        let vector = AutonomyVector.measured(
            from: observation,
            conditionalSelfPredictiveInformation: 0
        )
        #expect(vector.mechanochemicalClosure == 0)
    }

    @Test
    func claimsRemainIndependent() {
        let autonomy = EvidenceClaim(
            state: .supported,
            estimate: ConfidenceInterval(
                estimate: 0.2, lower: 0.1, upper: 0.3, effectiveSampleCount: 18
            ),
            nullUpperBound: 0.04,
            reason: "Self-predictive information exceeds shuffled nulls."
        )
        let evidence = IndividualityEvidence(
            mechanochemicalAutonomy: autonomy,
            physicalDescent: .init(
                state: .supported, estimate: nil, nullUpperBound: nil,
                reason: "Programs persist in separated descendants."
            ),
            heritableVariation: .init(
                state: .supported, estimate: nil, nullUpperBound: nil,
                reason: "A transmitted descendant carries a mutated program."
            ),
            differentialTransmission: .init(
                state: .supported, estimate: nil, nullUpperBound: 0,
                reason: "Transmission differs among inherited programs."
            ),
            darwinianEvolution: .init(
                state: .supported, estimate: nil, nullUpperBound: 0,
                reason: "All three Darwinian evidence terms are supported."
            ),
            collectiveLevelIndividuality: .init(
                state: .inconclusive, estimate: nil, nullUpperBound: nil,
                reason: "Between-component selection is unresolved."
            ),
            selection: .init(
                betweenComponentSelection: 0.01,
                withinComponentSelection: -0.02,
                transmissionChange: 0.003,
                covarianceSampleCount: 8
            ),
            autocorrelationTime: 14,
            observationWindows: 5
        )

        #expect(evidence.mechanochemicalAutonomy.state == .supported)
        #expect(evidence.physicalDescent.state == .supported)
        #expect(evidence.heritableVariation.state == .supported)
        #expect(evidence.differentialTransmission.state == .supported)
        #expect(evidence.darwinianEvolution.state == .supported)
        #expect(evidence.collectiveLevelIndividuality.state == .inconclusive)
    }

    @Test
    func physicalDescentAloneDoesNotEstablishDarwinianEvolution() {
        let claims = EvolutionaryEvidence.evaluate(
            selection: SelectionPartition(
                betweenComponentSelection: 0,
                withinComponentSelection: 0,
                transmissionChange: 0,
                covarianceSampleCount: 12,
                betweenComponentConfidence: ConfidenceInterval(
                    estimate: 0, lower: 0, upper: 0, effectiveSampleCount: 12
                ),
                independentDescendantCount: 4,
                transmittedVariantCount: 0
            ),
            maximumComponentDescentDepth: 2,
            conservationValid: true
        )

        #expect(claims.physicalDescent.state == .supported)
        #expect(claims.heritableVariation.state == .inconclusive)
        #expect(claims.differentialTransmission.state == .inconclusive)
        #expect(claims.darwinianEvolution.state == .inconclusive)
    }

    @Test
    func autonomyDistributionRetainsSpreadAndQuantiles() {
        let vectors = [0.1, 0.5, 0.9].map {
            AutonomyVector(
                energeticIndependence: $0, boundaryMaintenance: $0,
                mechanochemicalClosure: $0, endogenousDetermination: $0,
                cooperation: $0, conflict: 1 - $0, heredity: $0
            )
        }
        let distribution = AutonomyDistribution(vectors: vectors)

        #expect(distribution.energeticIndependence.count == 3)
        #expect(abs(distribution.energeticIndependence.mean - 0.5) < 1e-12)
        #expect(distribution.energeticIndependence.standardDeviation > 0)
        #expect(distribution.energeticIndependence.fifthPercentile < 0.5)
        #expect(distribution.energeticIndependence.ninetyFifthPercentile > 0.5)
    }

    @Test
    func predictableClumpWithoutBoundaryRepairNeverBecomesAutonomous() {
        var observer = IndividualityObserverEngine()
        var componentState = 0.24
        var latest: IndividualityObserverResult?

        for step in 0..<256 {
            componentState = 0.96 * componentState +
                sin(Double(step) * 0.37) * 0.004 + 0.006
            let component = IndividualityCandidate(
                observation: ComponentObservation(
                    step: UInt64(step), candidateID: 7,
                    partitionLevel: .membraneConnectedComponent, cellCount: 4,
                    harvestedATP: 0.8, importedATP: 0.1,
                    repairFlux: 0, membraneIntegrity: 0.9, exposedPerimeter: 1.2,
                    damageFlux: 0.02, membraneTurnover: 0.01,
                    strainToCalcium: componentState,
                    calciumToERK: componentState,
                    erkToTraction: componentState,
                    tractionToStrain: componentState,
                    junctionTransmission: 0.2, atpSharing: 0.2,
                    rejection: 0, withinComponentReplicationAdvantage: 0,
                    descendantRepresentation: 0, parentResemblance: 0
                ),
                positionX: 0.5, positionY: 0.5,
                isSeparatedDescendant: false,
                environmentalDependence: sin(Double(step) * 0.91) * 0.2
            )
            let cell = IndividualityCandidate(
                observation: ComponentObservation(
                    step: UInt64(step), candidateID: 70,
                    partitionLevel: .cell, cellCount: 1,
                    harvestedATP: 0.2, importedATP: 0,
                    repairFlux: 0, membraneIntegrity: 0.9, exposedPerimeter: 0.3,
                    damageFlux: 0, membraneTurnover: 0,
                    strainToCalcium: 0, calciumToERK: 0,
                    erkToTraction: 0, tractionToStrain: 0,
                    junctionTransmission: 0, atpSharing: 0,
                    rejection: 0, withinComponentReplicationAdvantage: 0,
                    descendantRepresentation: 0, parentResemblance: 0
                ),
                positionX: 0, positionY: 0,
                isSeparatedDescendant: false,
                environmentalDependence: cos(Double(step) * 1.27),
                parentComponentID: 7
            )
            latest = observer.observe(
                [component, cell], evaluationStride: 1,
                resamples: 32, maximumCandidatesPerLevel: 1
            ) ?? latest
        }

        #expect(latest?.resolvedCollectiveCount == 0)
        #expect(latest?.autonomyClaim.state != .supported)
    }

    @Test
    func evolutionaryClaimsDeclareAccumulatedTimeBasis() {
        let claims = EvolutionaryEvidence.evaluate(
            selection: SelectionPartition(
                betweenComponentSelection: 0,
                withinComponentSelection: 0,
                transmissionChange: 0,
                covarianceSampleCount: 0
            ),
            maximumComponentDescentDepth: 0,
            conservationValid: true
        )

        #expect(claims.physicalDescent.timeBasis == .accumulatedHistory)
        #expect(claims.heritableVariation.timeBasis == .accumulatedHistory)
        #expect(claims.differentialTransmission.timeBasis == .accumulatedHistory)
        #expect(claims.darwinianEvolution.timeBasis == .accumulatedHistory)
    }
}
