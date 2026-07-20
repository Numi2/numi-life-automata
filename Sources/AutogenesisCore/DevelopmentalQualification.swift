import Foundation

public struct DevelopmentalQualificationInput: Sendable, Equatable {
    public let observationCount: Int
    public let consecutiveViableEndpointObservations: Int
    public let maximumCellsPerOrganism: Double
    public let maximumActiveJunctions: UInt32
    public let maximumMorphogenTransport: Double
    public let maximumMorphogenDifferentiation: Double
    public let maximumIntegratedOrganisms: Int
    public let maximumLivingGeneration: UInt32
    public let fissions: UInt64
    public let invariantFlags: UInt32
    public let maximumAbsoluteEnergyResidual: Double

    public init(
        observationCount: Int,
        consecutiveViableEndpointObservations: Int,
        maximumCellsPerOrganism: Double,
        maximumActiveJunctions: UInt32,
        maximumMorphogenTransport: Double,
        maximumMorphogenDifferentiation: Double,
        maximumIntegratedOrganisms: Int,
        maximumLivingGeneration: UInt32,
        fissions: UInt64,
        invariantFlags: UInt32,
        maximumAbsoluteEnergyResidual: Double
    ) {
        self.observationCount = observationCount
        self.consecutiveViableEndpointObservations = consecutiveViableEndpointObservations
        self.maximumCellsPerOrganism = maximumCellsPerOrganism
        self.maximumActiveJunctions = maximumActiveJunctions
        self.maximumMorphogenTransport = maximumMorphogenTransport
        self.maximumMorphogenDifferentiation = maximumMorphogenDifferentiation
        self.maximumIntegratedOrganisms = maximumIntegratedOrganisms
        self.maximumLivingGeneration = maximumLivingGeneration
        self.fissions = fissions
        self.invariantFlags = invariantFlags
        self.maximumAbsoluteEnergyResidual = maximumAbsoluteEnergyResidual
    }
}

public struct DevelopmentalQualification: Codable, Sendable, Equatable {
    public static let minimumObservationCount = 3
    public static let minimumEndpointPersistence = 3
    public static let minimumCellsPerOrganism = 6.0
    public static let minimumMorphogenDifferentiation = 0.015
    public static let maximumEnergyResidual = 0.001

    public let passed: Bool
    public let sufficientObservationWindow: Bool
    public let persistentAtEndpoint: Bool
    public let multicellularOrganization: Bool
    public let junctionCoupledDevelopment: Bool
    public let morphogenDifferentiation: Bool
    public let integratedOrganismFormation: Bool
    public let cellularReproduction: Bool
    public let invariantAndEnergyConservation: Bool

    public static func evaluate(_ input: DevelopmentalQualificationInput) -> Self {
        let sufficientObservationWindow = input.observationCount >= minimumObservationCount
        let persistentAtEndpoint = input.consecutiveViableEndpointObservations >=
            minimumEndpointPersistence
        let multicellularOrganization = input.maximumCellsPerOrganism >=
            minimumCellsPerOrganism
        let junctionCoupledDevelopment = input.maximumActiveJunctions > 0 &&
            input.maximumMorphogenTransport > 0.000_000_01
        let morphogenDifferentiation = input.maximumMorphogenDifferentiation >=
            minimumMorphogenDifferentiation
        let integratedOrganismFormation = input.maximumIntegratedOrganisms > 0
        let cellularReproduction = input.fissions > 0 && input.maximumLivingGeneration > 0
        let invariantAndEnergyConservation = input.invariantFlags == 0 &&
            input.maximumAbsoluteEnergyResidual <= maximumEnergyResidual
        let passed = sufficientObservationWindow && persistentAtEndpoint &&
            multicellularOrganization && junctionCoupledDevelopment &&
            morphogenDifferentiation && integratedOrganismFormation && cellularReproduction &&
            invariantAndEnergyConservation
        return Self(
            passed: passed,
            sufficientObservationWindow: sufficientObservationWindow,
            persistentAtEndpoint: persistentAtEndpoint,
            multicellularOrganization: multicellularOrganization,
            junctionCoupledDevelopment: junctionCoupledDevelopment,
            morphogenDifferentiation: morphogenDifferentiation,
            integratedOrganismFormation: integratedOrganismFormation,
            cellularReproduction: cellularReproduction,
            invariantAndEnergyConservation: invariantAndEnergyConservation
        )
    }
}
