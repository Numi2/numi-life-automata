import Testing
@testable import AutogenesisCore

struct DevelopmentalQualificationTests {
    @Test
    func qualifiesOnlyWhenEveryMechanisticCriterionIsObserved() {
        let result = DevelopmentalQualification.evaluate(.init(
            observationCount: 5,
            consecutiveViableEndpointObservations: 4,
            maximumCellsPerOrganism: 8.0,
            maximumActiveJunctions: 12,
            maximumMorphogenTransport: 0.004,
            maximumMorphogenDifferentiation: 0.08,
            maximumLivingGeneration: 2,
            fissions: 3,
            invariantFlags: 0,
            maximumAbsoluteEnergyResidual: 0.0002
        ))

        #expect(result.passed)
        #expect(result.persistentAtEndpoint)
        #expect(result.cellularReproduction)
    }

    @Test
    func rejectsTransientDifferentiationWithoutReproductionOrPersistence() {
        let result = DevelopmentalQualification.evaluate(.init(
            observationCount: 8,
            consecutiveViableEndpointObservations: 0,
            maximumCellsPerOrganism: 8.0,
            maximumActiveJunctions: 16,
            maximumMorphogenTransport: 0.002,
            maximumMorphogenDifferentiation: 0.12,
            maximumLivingGeneration: 0,
            fissions: 0,
            invariantFlags: 0,
            maximumAbsoluteEnergyResidual: 0.0001
        ))

        #expect(!result.passed)
        #expect(!result.persistentAtEndpoint)
        #expect(!result.cellularReproduction)
        #expect(result.morphogenDifferentiation)
    }

    @Test
    func rejectsInvariantOrEnergyFailure() {
        let result = DevelopmentalQualification.evaluate(.init(
            observationCount: 4,
            consecutiveViableEndpointObservations: 4,
            maximumCellsPerOrganism: 8.0,
            maximumActiveJunctions: 3,
            maximumMorphogenTransport: 0.001,
            maximumMorphogenDifferentiation: 0.04,
            maximumLivingGeneration: 1,
            fissions: 1,
            invariantFlags: 1 << 1,
            maximumAbsoluteEnergyResidual: 0.003
        ))

        #expect(!result.passed)
        #expect(!result.invariantAndEnergyConservation)
    }

    @Test
    func rejectsJunctionsWithoutMeasuredMorphogenTransport() {
        let result = DevelopmentalQualification.evaluate(.init(
            observationCount: 4,
            consecutiveViableEndpointObservations: 4,
            maximumCellsPerOrganism: 8.0,
            maximumActiveJunctions: 3,
            maximumMorphogenTransport: 0,
            maximumMorphogenDifferentiation: 0.04,
            maximumLivingGeneration: 1,
            fissions: 1,
            invariantFlags: 0,
            maximumAbsoluteEnergyResidual: 0.0002
        ))

        #expect(!result.passed)
        #expect(!result.junctionCoupledDevelopment)
    }

    @Test
    func rejectsFourCellDevelopmentalPlateau() {
        let result = DevelopmentalQualification.evaluate(.init(
            observationCount: 8,
            consecutiveViableEndpointObservations: 4,
            maximumCellsPerOrganism: 4.0,
            maximumActiveJunctions: 12,
            maximumMorphogenTransport: 0.002,
            maximumMorphogenDifferentiation: 0.08,
            maximumLivingGeneration: 2,
            fissions: 2,
            invariantFlags: 0,
            maximumAbsoluteEnergyResidual: 0.0002
        ))

        #expect(!result.passed)
        #expect(!result.multicellularOrganization)
    }
}
