import Foundation

/// Raw, read-only reductions from one world. These values are observations,
/// never objectives, rewards, stop conditions, or inputs to simulation state.
public struct WorldMetrics: Sendable, Equatable {
    public var biomassDensity: Double
    public var basisMaterialDensity: Double
    public var energyDensity: Double
    public var occupiedFraction: Double
    public var temporalActivity: Double
    public var boundaryCoherence: Double
    public var multiscaleDivergence: Double
    public var recovery: Double
    public var geneticDiversity: Double
    public var lineageDiversity: Double
    public var interactionDiversity: Double
    public var trophicActivity: Double
    public var externalEnergyVariation: Double
    public var recycledMatterDensity: Double
    public var barrierFraction: Double
    public var environmentalMechanicalDrive: Double
    public var centroidX: Double
    public var centroidY: Double

    public init(
        biomassDensity: Double,
        basisMaterialDensity: Double,
        energyDensity: Double,
        occupiedFraction: Double,
        temporalActivity: Double,
        boundaryCoherence: Double,
        multiscaleDivergence: Double,
        recovery: Double,
        geneticDiversity: Double,
        lineageDiversity: Double = 0,
        interactionDiversity: Double = 0,
        trophicActivity: Double = 0,
        externalEnergyVariation: Double = 0,
        recycledMatterDensity: Double = 0,
        barrierFraction: Double = 0,
        environmentalMechanicalDrive: Double = 0,
        centroidX: Double,
        centroidY: Double
    ) {
        self.biomassDensity = Self.finite(biomassDensity)
        self.basisMaterialDensity = Self.finite(basisMaterialDensity)
        self.energyDensity = Self.finite(energyDensity)
        self.occupiedFraction = Self.finite(occupiedFraction)
        self.temporalActivity = Self.finite(temporalActivity)
        self.boundaryCoherence = Self.finite(boundaryCoherence)
        self.multiscaleDivergence = Self.finite(multiscaleDivergence)
        self.recovery = Self.finite(recovery)
        self.geneticDiversity = Self.finite(geneticDiversity)
        self.lineageDiversity = Self.finite(lineageDiversity)
        self.interactionDiversity = Self.finite(interactionDiversity)
        self.trophicActivity = Self.finite(trophicActivity)
        self.externalEnergyVariation = Self.finite(externalEnergyVariation)
        self.recycledMatterDensity = Self.finite(recycledMatterDensity)
        self.barrierFraction = Self.finite(barrierFraction)
        self.environmentalMechanicalDrive = Self.finite(environmentalMechanicalDrive)
        self.centroidX = Self.finite(centroidX)
        self.centroidY = Self.finite(centroidY)
    }

    public static let empty = WorldMetrics(
        biomassDensity: 0, basisMaterialDensity: 0, energyDensity: 0,
        occupiedFraction: 0, temporalActivity: 0, boundaryCoherence: 0,
        multiscaleDivergence: 0, recovery: 0, geneticDiversity: 0,
        centroidX: 0.5, centroidY: 0.5
    )

    private static func finite(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }
}

public struct SplitMix64: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
