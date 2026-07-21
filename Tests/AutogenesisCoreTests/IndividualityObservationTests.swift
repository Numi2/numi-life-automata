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
            darwinianLineage: .init(
                state: .supported, estimate: nil, nullUpperBound: nil,
                reason: "Programs persist in separated descendants."
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
        #expect(evidence.darwinianLineage.state == .supported)
        #expect(evidence.collectiveLevelIndividuality.state == .inconclusive)
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
}
