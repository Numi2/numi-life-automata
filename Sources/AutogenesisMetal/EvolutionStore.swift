import AutogenesisCore
import Combine
import Foundation
import simd

enum FieldDisplayMode: UInt32, CaseIterable, Identifiable {
    case ecology
    case energy
    case genome
    case niches
    case development
    case causality

    var id: UInt32 { rawValue }

    var label: String {
        switch self {
        case .ecology: "World"
        case .energy: "Energy"
        case .genome: "Traits"
        case .niches: "Needs"
        case .development: "Growth"
        case .causality: "Cause and effect"
        }
    }

}

enum EvolutionEventKind: Sendable, Equatable {
    case founding
    case expansion
    case branching
    case scarcity
    case disturbance
    case equilibrium
    case intervention
    case observation
    case fusion
    case emergence
    case cellDivision
    case programMutation
    case crossbreeding
}

struct EvolutionEvent: Identifiable, Sendable, Equatable {
    let id: UInt64
    let generation: Int
    let kind: EvolutionEventKind
    let title: String
    let detail: String
}

struct ObservedLineageBranch: Identifiable, Sendable, Equatable {
    let id: UInt32
    let parentID: UInt32?
    let birthStep: UInt32
    let generation: UInt32
    let topologyHash: UInt32
    let mutationDistance: Float
    let resonanceFrequency: Float
    var deathStep: UInt32?
}

struct ComponentAncestryEdge: Hashable, Sendable {
    let descendantID: UInt32
    let contributorID: UInt32
    let step: UInt32
    let aroseByFusion: Bool
}

struct EvolutionSnapshot: Sendable, Equatable {
    var generation: Int = 0
    var totalSteps: UInt64 = 0
    var selectedWorld: Int = 0
    var archiveCount: Int = 0
    var quantumNorm: Double = 0
    var meanMolecularResourceB: Double = 0
    var meanMolecularCatalyst: Double = 0
    var meanMolecularToxin: Double = 0
    var meanMolecularMembrane: Double = 0
    var meanQuantumOrder: Double = 0
    var meanChemicalAffinity: Double = 0
    var meanCatalystProduction: Double = 0
    var meanPrebioticEnergyProduction: Double = 0
    var meanMembraneAssembly: Double = 0
    var meanDetritalMineralization: Double = 0
    var organismCount: Int = 0
    var hunterCount: Int = 0
    var organismLineageCount: Int = 0
    var meanOrganismSpeed: Double = 0
    var cellCount: Int = 0
    var dividingCellCount: Int = 0
    var meanCellATP: Double = 0
    var meanCellIntegrity: Double = 0
    var meanCellStress: Double = 0
    var meanMembraneVoltage: Double = 0
    var meanPhaseCoherence: Double = 0
    var meanOscillationFrequency: Double = 0
    var meanTissueStrain: Double = 0
    var meanSubstrateForcing: Double = 0
    var meanBarrierLoad: Double = 0
    var meanEnvironmentalFrequency: Double = 0
    var meanFrequencyMatch: Double = 0
    var meanArmorConstruction: Double = 0
    var meanPredatoryConstruction: Double = 0
    var cellularEnergyHarvest: Double = 0
    var cellularEnergyDemand: Double = 0
    var cellularEnergyDissipation: Double = 0
    var auditedSubstrateEnergy: Double = 0
    var auditedATPHarvest: Double = 0
    var auditedCellularStorageDelta: Double = 0
    var auditedActiveWork: Double = 0
    var auditedFrequencyWork: Double = 0
    var auditedHeatExport: Double = 0
    var auditedDetritusReturn: Double = 0
    var energyConservationResidual: Double = 0
    var meanProliferationProgram: Double = 0
    var meanAdhesiveProgram: Double = 0
    var meanContractileProgram: Double = 0
    var meanRepairProgram: Double = 0
    var meanDevelopmentalNodeCount: Double = 0
    var meanDevelopmentalEdgeCount: Double = 0
    var meanMorphogenActivator: Double = 0
    var meanMorphogenInhibitor: Double = 0
    var meanDevelopmentalFateMemory: Double = 0
    var meanJunctionMorphogenTransport: Double = 0
    var meanMorphogenDifferentiation: Double = 0
    var meanDevelopmentalPolarityCoherence: Double = 0
    var meanMorphogenSynthesisRate: Double = 0
    var meanMorphogenTransportWork: Double = 0
    var meanResonanceFrequency: Double = 0
    var meanResonanceDamping: Double = 0
    var meanResonanceBandwidth: Double = 0
    var meanResonanceAmplitude: Double = 0
    var meanMembraneArea: Double = 0
    var meanMembranePerimeter: Double = 0
    var meanMembraneShapeIndex: Double = 0
    var meanJunctionForce: Double = 0
    var meanLineageMutationDistance: Double = 0
    var persistentCladeCount: Int = 0
    var meanMorphologyDistance: Double = 0
    var meanMechanotransductionEffect: Double = 0
    var meanProliferativeDrive: Double = 0
    var meanContactSuppression: Double = 0
    var meanRepairEffect: Double = 0
    var meanCalciumActivity: Double = 0
    var meanERKActivity: Double = 0
    var meanSignalRefractory: Double = 0
    var meanMechanicsCalciumEffect: Double = 0
    var meanCalciumERKEffect: Double = 0
    var meanERKTractionEffect: Double = 0
    var cellularSignalingCost: Double = 0
    var meanTissueElongation: Double = 0
    var meanExposedMembraneLength: Double = 0
    var meanCellGeneratedForce: Double = 0
    var meanTissueTorque: Double = 0
    var cellularContactLoad: Double = 0
    var cellularTrophicGain: Double = 0
    var cellularTrophicLoss: Double = 0
    var meanDetachmentScore: Double = 0
    var meanMechanicsCalciumGain: Double = 0
    var meanJunctionTransmissionGain: Double = 0
    var meanCalciumERKGain: Double = 0
    var meanRefractoryRecoveryGain: Double = 0
    var meanInheritedSignalingCost: Double = 0
    var meanInheritedTractionGain: Double = 0
    var meanDetachmentThreshold: Double = 0
    var meanPropaguleInvestment: Double = 0
    var meanJunctionAdhesion: Double = 0
    var meanJunctionCorticalTension: Double = 0
    var meanJunctionDamping: Double = 0
    var meanJunctionPermeability: Double = 0
    var meanToxinTolerance: Double = 0
    var meanDetritalScavenging: Double = 0
    var meanShearAnchoring: Double = 0
    var meanStarvationQuiescence: Double = 0
    var meanCellsPerOrganism: Double = 0
    var largestTissueCellCount: Int = 0
    var cellPoolUtilization: Double = 0
    var heritableProgramCount: Int = 0
    var heritableProgramPoolUtilization: Double = 0
    var meanMixedProgramCellFraction: Double = 0
    var maximumProgramRichness: Int = 0
    var meanProgramATPExchange: Double = 0
    var meanProgramRejection: Double = 0
    var meanProgramRecognitionCompatibility: Double = -1
    var meanProgramNetContribution: Double = 0
    var crossComponentContactSamples: UInt32 = 0
    var membraneBreachSamples: UInt32 = 0
    var resistedAttackSamples: UInt32 = 0
    var trophicTransferSamples: UInt32 = 0
    var transferredEnergy: Double = 0
    var deflectedAttackImpulse: Double = 0
    var fusionContactSamples: UInt32 = 0
    var successfulFusionContactSamples: UInt32 = 0
    var metrics: WorldMetrics = .empty
    var fitness = FitnessVector(viability: 0, adaptiveComplexity: 0, recovery: 0, novelty: 0)

    init(
        generation: Int = 0,
        totalSteps: UInt64 = 0,
        selectedWorld: Int = 0,
        archiveCount: Int = 0,
        quantumNorm: Double = 0,
        meanMolecularResourceB: Double = 0,
        meanMolecularCatalyst: Double = 0,
        meanMolecularToxin: Double = 0,
        meanMolecularMembrane: Double = 0,
        meanQuantumOrder: Double = 0,
        meanChemicalAffinity: Double = 0,
        meanCatalystProduction: Double = 0,
        meanPrebioticEnergyProduction: Double = 0,
        meanMembraneAssembly: Double = 0,
        meanDetritalMineralization: Double = 0,
        organismCount: Int = 0,
        hunterCount: Int = 0,
        organismLineageCount: Int = 0,
        meanOrganismSpeed: Double = 0,
        cellCount: Int = 0,
        dividingCellCount: Int = 0,
        meanCellATP: Double = 0,
        meanCellIntegrity: Double = 0,
        meanCellStress: Double = 0,
        meanMembraneVoltage: Double = 0,
        meanPhaseCoherence: Double = 0,
        meanOscillationFrequency: Double = 0,
        meanTissueStrain: Double = 0,
        meanSubstrateForcing: Double = 0,
        meanBarrierLoad: Double = 0,
        meanEnvironmentalFrequency: Double = 0,
        meanFrequencyMatch: Double = 0,
        meanArmorConstruction: Double = 0,
        meanPredatoryConstruction: Double = 0,
        cellularEnergyHarvest: Double = 0,
        cellularEnergyDemand: Double = 0,
        cellularEnergyDissipation: Double = 0,
        auditedSubstrateEnergy: Double = 0,
        auditedATPHarvest: Double = 0,
        auditedCellularStorageDelta: Double = 0,
        auditedActiveWork: Double = 0,
        auditedFrequencyWork: Double = 0,
        auditedHeatExport: Double = 0,
        auditedDetritusReturn: Double = 0,
        energyConservationResidual: Double = 0,
        meanProliferationProgram: Double = 0,
        meanAdhesiveProgram: Double = 0,
        meanContractileProgram: Double = 0,
        meanRepairProgram: Double = 0,
        meanDevelopmentalNodeCount: Double = 0,
        meanDevelopmentalEdgeCount: Double = 0,
        meanMorphogenActivator: Double = 0,
        meanMorphogenInhibitor: Double = 0,
        meanDevelopmentalFateMemory: Double = 0,
        meanJunctionMorphogenTransport: Double = 0,
        meanMorphogenDifferentiation: Double = 0,
        meanDevelopmentalPolarityCoherence: Double = 0,
        meanMorphogenSynthesisRate: Double = 0,
        meanMorphogenTransportWork: Double = 0,
        meanResonanceFrequency: Double = 0,
        meanResonanceDamping: Double = 0,
        meanResonanceBandwidth: Double = 0,
        meanResonanceAmplitude: Double = 0,
        meanMembraneArea: Double = 0,
        meanMembranePerimeter: Double = 0,
        meanMembraneShapeIndex: Double = 0,
        meanJunctionForce: Double = 0,
        meanLineageMutationDistance: Double = 0,
        persistentCladeCount: Int = 0,
        meanMorphologyDistance: Double = 0,
        meanMechanotransductionEffect: Double = 0,
        meanProliferativeDrive: Double = 0,
        meanContactSuppression: Double = 0,
        meanRepairEffect: Double = 0,
        meanCalciumActivity: Double = 0,
        meanERKActivity: Double = 0,
        meanSignalRefractory: Double = 0,
        meanMechanicsCalciumEffect: Double = 0,
        meanCalciumERKEffect: Double = 0,
        meanERKTractionEffect: Double = 0,
        cellularSignalingCost: Double = 0,
        meanTissueElongation: Double = 0,
        meanExposedMembraneLength: Double = 0,
        meanCellGeneratedForce: Double = 0,
        meanTissueTorque: Double = 0,
        cellularContactLoad: Double = 0,
        cellularTrophicGain: Double = 0,
        cellularTrophicLoss: Double = 0,
        meanDetachmentScore: Double = 0,
        meanMechanicsCalciumGain: Double = 0,
        meanJunctionTransmissionGain: Double = 0,
        meanCalciumERKGain: Double = 0,
        meanRefractoryRecoveryGain: Double = 0,
        meanInheritedSignalingCost: Double = 0,
        meanInheritedTractionGain: Double = 0,
        meanDetachmentThreshold: Double = 0,
        meanPropaguleInvestment: Double = 0,
        meanJunctionAdhesion: Double = 0,
        meanJunctionCorticalTension: Double = 0,
        meanJunctionDamping: Double = 0,
        meanJunctionPermeability: Double = 0,
        meanToxinTolerance: Double = 0,
        meanDetritalScavenging: Double = 0,
        meanShearAnchoring: Double = 0,
        meanStarvationQuiescence: Double = 0,
        meanCellsPerOrganism: Double = 0,
        largestTissueCellCount: Int = 0,
        cellPoolUtilization: Double = 0,
        heritableProgramCount: Int = 0,
        heritableProgramPoolUtilization: Double = 0,
        meanMixedProgramCellFraction: Double = 0,
        maximumProgramRichness: Int = 0,
        meanProgramATPExchange: Double = 0,
        meanProgramRejection: Double = 0,
        meanProgramRecognitionCompatibility: Double = -1,
        meanProgramNetContribution: Double = 0,
        metrics: WorldMetrics = .empty,
        fitness: FitnessVector = FitnessVector(viability: 0, adaptiveComplexity: 0, recovery: 0, novelty: 0)
    ) {
        self.generation = generation
        self.totalSteps = totalSteps
        self.selectedWorld = selectedWorld
        self.archiveCount = archiveCount
        self.quantumNorm = quantumNorm
        self.meanMolecularResourceB = meanMolecularResourceB
        self.meanMolecularCatalyst = meanMolecularCatalyst
        self.meanMolecularToxin = meanMolecularToxin
        self.meanMolecularMembrane = meanMolecularMembrane
        self.meanQuantumOrder = meanQuantumOrder
        self.meanChemicalAffinity = meanChemicalAffinity
        self.meanCatalystProduction = meanCatalystProduction
        self.meanPrebioticEnergyProduction = meanPrebioticEnergyProduction
        self.meanMembraneAssembly = meanMembraneAssembly
        self.meanDetritalMineralization = meanDetritalMineralization
        self.organismCount = organismCount
        self.hunterCount = hunterCount
        self.organismLineageCount = organismLineageCount
        self.meanOrganismSpeed = meanOrganismSpeed
        self.cellCount = cellCount
        self.dividingCellCount = dividingCellCount
        self.meanCellATP = meanCellATP
        self.meanCellIntegrity = meanCellIntegrity
        self.meanCellStress = meanCellStress
        self.meanMembraneVoltage = meanMembraneVoltage
        self.meanPhaseCoherence = meanPhaseCoherence
        self.meanOscillationFrequency = meanOscillationFrequency
        self.meanTissueStrain = meanTissueStrain
        self.meanSubstrateForcing = meanSubstrateForcing
        self.meanBarrierLoad = meanBarrierLoad
        self.meanEnvironmentalFrequency = meanEnvironmentalFrequency
        self.meanFrequencyMatch = meanFrequencyMatch
        self.meanArmorConstruction = meanArmorConstruction
        self.meanPredatoryConstruction = meanPredatoryConstruction
        self.cellularEnergyHarvest = cellularEnergyHarvest
        self.cellularEnergyDemand = cellularEnergyDemand
        self.cellularEnergyDissipation = cellularEnergyDissipation
        self.auditedSubstrateEnergy = auditedSubstrateEnergy
        self.auditedATPHarvest = auditedATPHarvest
        self.auditedCellularStorageDelta = auditedCellularStorageDelta
        self.auditedActiveWork = auditedActiveWork
        self.auditedFrequencyWork = auditedFrequencyWork
        self.auditedHeatExport = auditedHeatExport
        self.auditedDetritusReturn = auditedDetritusReturn
        self.energyConservationResidual = energyConservationResidual
        self.meanProliferationProgram = meanProliferationProgram
        self.meanAdhesiveProgram = meanAdhesiveProgram
        self.meanContractileProgram = meanContractileProgram
        self.meanRepairProgram = meanRepairProgram
        self.meanDevelopmentalNodeCount = meanDevelopmentalNodeCount
        self.meanDevelopmentalEdgeCount = meanDevelopmentalEdgeCount
        self.meanMorphogenActivator = meanMorphogenActivator
        self.meanMorphogenInhibitor = meanMorphogenInhibitor
        self.meanDevelopmentalFateMemory = meanDevelopmentalFateMemory
        self.meanJunctionMorphogenTransport = meanJunctionMorphogenTransport
        self.meanMorphogenDifferentiation = meanMorphogenDifferentiation
        self.meanDevelopmentalPolarityCoherence = meanDevelopmentalPolarityCoherence
        self.meanMorphogenSynthesisRate = meanMorphogenSynthesisRate
        self.meanMorphogenTransportWork = meanMorphogenTransportWork
        self.meanResonanceFrequency = meanResonanceFrequency
        self.meanResonanceDamping = meanResonanceDamping
        self.meanResonanceBandwidth = meanResonanceBandwidth
        self.meanResonanceAmplitude = meanResonanceAmplitude
        self.meanMembraneArea = meanMembraneArea
        self.meanMembranePerimeter = meanMembranePerimeter
        self.meanMembraneShapeIndex = meanMembraneShapeIndex
        self.meanJunctionForce = meanJunctionForce
        self.meanLineageMutationDistance = meanLineageMutationDistance
        self.persistentCladeCount = persistentCladeCount
        self.meanMorphologyDistance = meanMorphologyDistance
        self.meanMechanotransductionEffect = meanMechanotransductionEffect
        self.meanProliferativeDrive = meanProliferativeDrive
        self.meanContactSuppression = meanContactSuppression
        self.meanRepairEffect = meanRepairEffect
        self.meanCalciumActivity = meanCalciumActivity
        self.meanERKActivity = meanERKActivity
        self.meanSignalRefractory = meanSignalRefractory
        self.meanMechanicsCalciumEffect = meanMechanicsCalciumEffect
        self.meanCalciumERKEffect = meanCalciumERKEffect
        self.meanERKTractionEffect = meanERKTractionEffect
        self.cellularSignalingCost = cellularSignalingCost
        self.meanTissueElongation = meanTissueElongation
        self.meanExposedMembraneLength = meanExposedMembraneLength
        self.meanCellGeneratedForce = meanCellGeneratedForce
        self.meanTissueTorque = meanTissueTorque
        self.cellularContactLoad = cellularContactLoad
        self.cellularTrophicGain = cellularTrophicGain
        self.cellularTrophicLoss = cellularTrophicLoss
        self.meanDetachmentScore = meanDetachmentScore
        self.meanMechanicsCalciumGain = meanMechanicsCalciumGain
        self.meanJunctionTransmissionGain = meanJunctionTransmissionGain
        self.meanCalciumERKGain = meanCalciumERKGain
        self.meanRefractoryRecoveryGain = meanRefractoryRecoveryGain
        self.meanInheritedSignalingCost = meanInheritedSignalingCost
        self.meanInheritedTractionGain = meanInheritedTractionGain
        self.meanDetachmentThreshold = meanDetachmentThreshold
        self.meanPropaguleInvestment = meanPropaguleInvestment
        self.meanJunctionAdhesion = meanJunctionAdhesion
        self.meanJunctionCorticalTension = meanJunctionCorticalTension
        self.meanJunctionDamping = meanJunctionDamping
        self.meanJunctionPermeability = meanJunctionPermeability
        self.meanToxinTolerance = meanToxinTolerance
        self.meanDetritalScavenging = meanDetritalScavenging
        self.meanShearAnchoring = meanShearAnchoring
        self.meanStarvationQuiescence = meanStarvationQuiescence
        self.meanCellsPerOrganism = meanCellsPerOrganism
        self.largestTissueCellCount = largestTissueCellCount
        self.cellPoolUtilization = cellPoolUtilization
        self.heritableProgramCount = heritableProgramCount
        self.heritableProgramPoolUtilization = heritableProgramPoolUtilization
        self.meanMixedProgramCellFraction = meanMixedProgramCellFraction
        self.maximumProgramRichness = maximumProgramRichness
        self.meanProgramATPExchange = meanProgramATPExchange
        self.meanProgramRejection = meanProgramRejection
        self.meanProgramRecognitionCompatibility = meanProgramRecognitionCompatibility
        self.meanProgramNetContribution = meanProgramNetContribution
        self.metrics = metrics
        self.fitness = fitness
    }
}

struct RendererSettings: Sendable, Equatable {
    var isRunning: Bool
    var stepsPerFrame: Int
    var resourceFlux: Float
    var mutationScale: Float
    var transportScale: Float
    var mechanosensingGain: Float
    var barrierGain: Float
    var displayMode: UInt32
    var trackedAgentID: UInt32
    var cameraCenter: SIMD2<Float>
    var cameraZoom: Float
    var worldScale: Float
    var addColonyPosition: SIMD2<Float>
    var addColonyToken: UInt64
    var expansionToken: UInt64
    var resetToken: UInt64
}

@MainActor
final class EvolutionStore: ObservableObject {
    private static let spinorOrigin = SIMD2<Float>(repeating: 0.500_488_281_25)

    @Published var isRunning = true
    @Published var stepsPerFrame = 6
    @Published var resourceFlux: Double = 1.0
    @Published var mutationScale: Double = 1.0
    @Published var transportScale: Double = 1.0
    @Published private(set) var mechanosensingBlocked = false
    @Published var displayMode: FieldDisplayMode = .ecology
    @Published private(set) var cameraCenter = spinorOrigin
    @Published private(set) var cameraZoom: Double = 900
    @Published private(set) var snapshot = EvolutionSnapshot()
    @Published private(set) var history: [EvolutionSnapshot] = []
    @Published private(set) var events: [EvolutionEvent] = []
    @Published private(set) var founderCount = 0
    @Published private(set) var fusionEventCount = 0
    @Published private(set) var crossbreedingEventCount = 0
    @Published private(set) var followedAgentID: Int?
    @Published private(set) var observableAgentCount = 0
    @Published private(set) var resolvedIndividualCount = 0
    @Published private(set) var resolvedCellIndividualCount = 0
    @Published private(set) var resolvedCollectiveIndividualCount = 0
    @Published private(set) var meanEnergeticIndependence = 0.0
    @Published private(set) var meanMechanochemicalClosure = 0.0
    @Published private(set) var maximumProgramReplicationGeneration: UInt32 = 0
    @Published private(set) var individualityEvidence = IndividualityEvidence.inconclusive
    @Published private(set) var autonomyVectors: [AutonomyVector] = []
    @Published private(set) var currentComponentAutonomyVectors: [AutonomyVector] = []
    @Published private(set) var resolvedIndividualLabels: [String] = []
    @Published private(set) var runtimeTelemetry = RendererRuntimeTelemetry.idle
    @Published private(set) var maximumLivingLineageGeneration: UInt32 = 0
    @Published private(set) var livingDescendantCount = 0
    @Published private(set) var regenerativeDescendantCount = 0
    @Published private(set) var challengedDescendantCount = 0
    @Published private(set) var homeostaticDescendantCount = 0
    @Published private(set) var resolvedDescendantCount = 0
    @Published private(set) var livingDescendantCellCount = 0
    @Published private(set) var followedEnergeticIndependence: Float = 0
    @Published private(set) var followedMechanochemicalClosure: Float = 0
    @Published private(set) var lineageAnalysis = LineageAnalysis.empty
    @Published private(set) var lineageBranches: [ObservedLineageBranch] = []
    @Published private(set) var componentAncestryEdges: Set<ComponentAncestryEdge> = []
    @Published private(set) var worldScale: Double = 1
    @Published private(set) var errorMessage: String?
    private var addColonyPosition = SIMD2<Float>(repeating: 0.5)
    private var addColonyToken: UInt64 = 0
    private var addedColonyCount = 0
    private var resetToken: UInt64 = 1
    private var expansionToken: UInt64 = 0
    private var nextEventID: UInt64 = 1
    private var lastRecordedGeneration = 0
    private var observedAgents: [AgentObservation] = []
    private var followedBirthID: UInt32?
    private struct ObservedProgramKey: Hashable {
        let componentID: UInt64
        let programID: UInt64
    }
    private struct ObservedProgramCount {
        let parentProgramID: UInt64?
        let inheritedTrait: Double
        let collectiveTrait: Double
        var cellCount: Int
    }
    private var individualityObserver = IndividualityObserverEngine()
    private var previousProgramRepresentations: [ProgramRepresentation] = []
    private var pendingComponentContributions: Set<ComponentContribution> = []
    private var selectionIntervals: [MultilevelSelectionInterval] = []
    private var componentMorphologyArchive: [UInt32: MorphologyDescriptor] = [:]
    private var componentMorphologyOrder: [UInt32] = []
    private var previousResolvedIndividualKeys: Set<String> = []
    private var currentSelection = SelectionPartition(
        betweenComponentSelection: 0,
        withinComponentSelection: 0,
        transmissionChange: 0,
        covarianceSampleCount: 0
    )
    private var lineageTracker = LineageDivergenceTracker()
    private var hasObservedFirstBiologicalUnit = false
    private var autoFollowInitialObservation = true
    private var pendingMechanosensoryIntervention: (baseline: EvolutionSnapshot, blocked: Bool)?

    init() {
        if let rawSpeed = ProcessInfo.processInfo.environment["NUMI_INITIAL_SPEED"],
           let speed = Int(rawSpeed), [1, 3, 6, 24].contains(speed) {
            stepsPerFrame = speed
        }
        guard let rawMagnification = ProcessInfo.processInfo.environment[
            "NUMI_INITIAL_MAGNIFICATION"
        ], let magnification = Double(rawMagnification), magnification.isFinite else { return }
        cameraZoom = min(max(magnification, 0.000_001), 1.0e24)
        autoFollowInitialObservation = magnification >= 6
        displayMode = magnification >= 64 && magnification < 160 ? .energy :
            (magnification >= 18 && magnification < 64 ? .development :
                (magnification >= 6 && magnification < 18 ? .genome : .ecology))
    }

    var rendererSettings: RendererSettings {
        RendererSettings(
            isRunning: isRunning,
            stepsPerFrame: stepsPerFrame,
            resourceFlux: Float(resourceFlux),
            mutationScale: Float(mutationScale),
            transportScale: Float(transportScale),
            mechanosensingGain: mechanosensingBlocked ? 0 : 1,
            barrierGain: 1,
            displayMode: displayMode.rawValue,
            trackedAgentID: followedAgentID.map(UInt32.init) ?? .max,
            cameraCenter: cameraCenter,
            cameraZoom: Float(cameraZoom),
            worldScale: Float(worldScale),
            addColonyPosition: addColonyPosition,
            addColonyToken: addColonyToken,
            expansionToken: expansionToken,
            resetToken: resetToken
        )
    }

    func restart() {
        resetToken &+= 1
        snapshot = EvolutionSnapshot()
        history.removeAll(keepingCapacity: true)
        events.removeAll(keepingCapacity: true)
        addedColonyCount = 0
        founderCount = 0
        fusionEventCount = 0
        crossbreedingEventCount = 0
        lineageAnalysis = .empty
        lineageBranches.removeAll(keepingCapacity: true)
        componentAncestryEdges.removeAll(keepingCapacity: true)
        lineageTracker.reset()
        followedBirthID = nil
        followedAgentID = nil
        observableAgentCount = 0
        resolvedIndividualCount = 0
        resolvedCellIndividualCount = 0
        resolvedCollectiveIndividualCount = 0
        meanEnergeticIndependence = 0
        meanMechanochemicalClosure = 0
        maximumProgramReplicationGeneration = 0
        individualityEvidence = .inconclusive
        autonomyVectors.removeAll(keepingCapacity: true)
        currentComponentAutonomyVectors.removeAll(keepingCapacity: true)
        resolvedIndividualLabels.removeAll(keepingCapacity: true)
        runtimeTelemetry = .idle
        maximumLivingLineageGeneration = 0
        livingDescendantCount = 0
        resolvedDescendantCount = 0
        livingDescendantCellCount = 0
        followedEnergeticIndependence = 0
        followedMechanochemicalClosure = 0
        observedAgents.removeAll(keepingCapacity: true)
        individualityObserver.reset()
        previousProgramRepresentations.removeAll(keepingCapacity: true)
        pendingComponentContributions.removeAll(keepingCapacity: true)
        selectionIntervals.removeAll(keepingCapacity: true)
        componentMorphologyArchive.removeAll(keepingCapacity: true)
        componentMorphologyOrder.removeAll(keepingCapacity: true)
        previousResolvedIndividualKeys.removeAll(keepingCapacity: true)
        currentSelection = SelectionPartition(
            betweenComponentSelection: 0,
            withinComponentSelection: 0,
            transmissionChange: 0,
            covarianceSampleCount: 0
        )
        worldScale = 1
        expansionToken = 0
        lastRecordedGeneration = 0
        hasObservedFirstBiologicalUnit = false
        mechanosensingBlocked = false
        pendingMechanosensoryIntervention = nil
        resetCamera()
        autoFollowInitialObservation = true
    }

    func toggleMechanosensingIntervention() {
        mechanosensingBlocked.toggle()
        pendingMechanosensoryIntervention = snapshot.generation > 0
            ? (snapshot, mechanosensingBlocked)
            : nil
        recordEvent(
            generation: snapshot.generation,
            kind: .intervention,
            title: mechanosensingBlocked
                ? "Mechanical sensing input set to zero"
                : "Mechanical sensing input restored",
            detail: mechanosensingBlocked
                ? "The coefficient multiplying mechanical input in the voltage and Ca*-gating equations is now 0."
                : "The coefficient multiplying mechanical input in the voltage and Ca*-gating equations is now 1."
        )
    }

    func addColony() {
        let angle = Float(addedColonyCount) * 2.3999632
        let visibleRadius = Float(min(0.24 / max(cameraZoom, 0.001), 0.24))
        let offset = SIMD2<Float>(cos(angle), sin(angle)) * visibleRadius
        addColonyPosition = textureCoordinate(cameraCenter + offset)
        addedColonyCount += 1
        founderCount += 1
        hasObservedFirstBiologicalUnit = true
        addColonyToken &+= 1
        recordEvent(
            generation: snapshot.generation,
            kind: .intervention,
            title: "External founder cell initialized",
            detail: "Founder \(founderCount) received an independent component handle, one persistent cell, and sampled heritable control parameters at the camera position. Observer inference remains separate from its physics."
        )
        objectWillChange.send()
    }

    func zoom(by factor: Double, around anchor: SIMD2<Float>, aspect: Float) {
        guard factor.isFinite, factor > 0 else { return }
        let oldZoom = cameraZoom
        let newZoom = min(max(oldZoom * factor, 0.000_001), 1.0e24)
        guard newZoom != oldZoom else { return }
        let scale = aspectScale(for: aspect)
        let effectiveAnchor = followedAgentID == nil ? anchor : SIMD2<Float>(repeating: 0.5)
        let anchorOffset = (effectiveAnchor - SIMD2<Float>(repeating: 0.5)) * scale
        cameraCenter += anchorOffset * Float((1 / oldZoom) - (1 / newZoom))
        cameraZoom = newZoom
        expandWorldIfNeeded(aspect: aspect)
    }

    func zoom(to magnification: Double, aspect: Float) {
        let target = min(max(magnification, 1), 1.0e24)
        zoom(
            by: target / max(observationZoom, 0.000_001),
            around: SIMD2<Float>(repeating: 0.5),
            aspect: aspect
        )
    }

    func pan(by screenDelta: SIMD2<Float>, aspect: Float) {
        clearFollow()
        let worldDelta = screenDelta * aspectScale(for: aspect) / Float(cameraZoom)
        cameraCenter -= worldDelta
        expandWorldIfNeeded(aspect: aspect)
    }

    func resetCamera() {
        clearFollow()
        cameraCenter = Self.spinorOrigin
        cameraZoom = worldScale * 900
    }

    func followRandomOrganism() {
        guard let agent = observedAgents.randomElement() else { return }
        follow(agent)
    }

    func ensureLivingFocus() {
        guard followedAgentID == nil else { return }
        guard let nearest = observedAgents.min(by: {
            simd_distance_squared($0.position, cameraCenter) <
                simd_distance_squared($1.position, cameraCenter)
        }) else {
            autoFollowInitialObservation = true
            return
        }
        autoFollowInitialObservation = false
        follow(nearest)
    }

    func followAdjacentOrganism(direction: Int) {
        guard !observedAgents.isEmpty else { return }
        let ordered = observedAgents.sorted { $0.id < $1.id }
        guard let followedAgentID,
              let current = ordered.firstIndex(where: { $0.id == followedAgentID }) else {
            follow(ordered.first!)
            return
        }
        let offset = direction < 0 ? -1 : 1
        let next = (current + offset + ordered.count) % ordered.count
        follow(ordered[next])
    }

    func followOrganism(at screenPosition: SIMD2<Float>, aspect: Float) {
        guard !observedAgents.isEmpty else { return }
        let viewScale = aspectScale(for: aspect)
        let zoom = Float(cameraZoom)
        let selected = observedAgents
            .map { agent -> (AgentObservation, Float) in
                let screenCoordinate = SIMD2<Float>(repeating: 0.5) +
                    (agent.position - cameraCenter) * zoom / viewScale
                return (agent, simd_distance_squared(screenCoordinate, screenPosition))
            }
            .min { $0.1 < $1.1 }
        guard let selected, selected.1 <= 0.010 else { return }
        follow(selected.0)
    }

    func applyAgentObservations(
        _ agents: [AgentObservation],
        cellObservations: [CellObservation]
    ) {
        observedAgents = agents
        if observableAgentCount != agents.count {
            observableAgentCount = agents.count
        }
        meanEnergeticIndependence = agents.isEmpty ? 0 : agents.reduce(0) {
            $0 + Double($1.energeticIndependence)
        } / Double(agents.count)
        meanMechanochemicalClosure = agents.isEmpty ? 0 : agents.reduce(0) {
            $0 + Double($1.mechanochemicalClosure)
        } / Double(agents.count)
        maximumProgramReplicationGeneration = agents.map(\.programReplicationGeneration).max() ?? 0
        maximumLivingLineageGeneration = agents.map(\.generation).max() ?? 0
        let livingDescendants = agents.filter { $0.generation > 0 }
        livingDescendantCount = livingDescendants.count
        regenerativeDescendantCount = livingDescendants.count {
            $0.hasRegeneratedDevelopment
        }
        challengedDescendantCount = livingDescendants.count {
            $0.hasReceivedDamageChallenge
        }
        homeostaticDescendantCount = livingDescendants.count {
            $0.hasDemonstratedHomeostasis
        }
        livingDescendantCellCount = livingDescendants.reduce(0) {
            $0 + max(Int(($1.morphology.x * 24).rounded()), 1)
        }
        updateIndividualityObserver(agents, cells: cellObservations)
        if autoFollowInitialObservation, followedAgentID == nil, let first = agents.first {
            autoFollowInitialObservation = false
            follow(first)
        }
        if !hasObservedFirstBiologicalUnit, let founder = agents.first {
            hasObservedFirstBiologicalUnit = true
            founderCount = 1
            recordEvent(
                generation: snapshot.generation,
                kind: .founding,
                title: "Founder cell nucleated",
                detail: String(
                    format: "Component handle %d initialized at (%.4f, %.4f) after local biomass, stored-energy, membrane, and catalyst thresholds were met. Individuality is inferred only from subsequent observations.",
                    founder.id,
                    founder.position.x,
                    founder.position.y
                )
            )
#if DEBUG
            print("autogenic_founder id=\(founder.id) position=\(founder.position)")
#endif
        }
        if followedAgentID != nil {
            let followed = followedBirthID.flatMap { birthID in
                agents.first(where: { $0.birthID == birthID })
            }
            if let followed {
                if self.followedAgentID != followed.id { self.followedAgentID = followed.id }
                followedEnergeticIndependence = followed.energeticIndependence
                followedMechanochemicalClosure = followed.mechanochemicalClosure
                if simd_distance_squared(cameraCenter, followed.position) > 1.0e-14 {
                    cameraCenter = followed.position
                }
            } else if let replacement = agents.first {
                follow(replacement)
            } else {
                clearFollow()
            }
        }

        let livingSamples = agents.map { agent in
            LivingLineageSample(
                birthID: agent.birthID,
                topologyHash: agent.topologyHash,
                morphology: MorphologyDescriptor(values: [
                    Double(agent.morphology.x),
                    Double(agent.morphology.y / 0.86),
                    Double((agent.morphology.z - 1) / 2.5),
                    Double(agent.morphology.w),
                    Double((agent.dynamics.x - 0.0008) / 0.0082),
                    Double(agent.dynamics.y * 18),
                    Double(agent.dynamics.z),
                    Double(agent.dynamics.w)
                ])
            )
        }
        lineageAnalysis = lineageTracker.analyze(
            living: livingSamples,
            currentStep: snapshot.totalSteps
        )
        snapshot.persistentCladeCount = lineageAnalysis.persistentCladeCount
        snapshot.meanMorphologyDistance = lineageAnalysis.meanMorphologyDistance
        archiveMorphologies(agents)
    }

    private func follow(_ agent: AgentObservation) {
        followedAgentID = agent.id
        followedBirthID = agent.birthID
        followedEnergeticIndependence = agent.energeticIndependence
        followedMechanochemicalClosure = agent.mechanochemicalClosure
        cameraCenter = agent.position
    }

    private func clearFollow() {
        autoFollowInitialObservation = false
        followedAgentID = nil
        followedBirthID = nil
        followedEnergeticIndependence = 0
        followedMechanochemicalClosure = 0
    }

    func applyRuntimeTelemetry(_ telemetry: RendererRuntimeTelemetry) {
        if telemetry.scientificallyCommittedStep < runtimeTelemetry.scientificallyCommittedStep {
            history.removeAll { $0.totalSteps > telemetry.scientificallyCommittedStep }
            lineageBranches.removeAll {
                UInt64($0.birthStep) > telemetry.scientificallyCommittedStep
            }
            componentAncestryEdges = componentAncestryEdges.filter {
                UInt64($0.step) <= telemetry.scientificallyCommittedStep
            }
            pendingComponentContributions.removeAll(keepingCapacity: true)
            individualityObserver.rollback(after: telemetry.scientificallyCommittedStep)
            previousProgramRepresentations.removeAll(keepingCapacity: true)
            selectionIntervals.removeAll(keepingCapacity: true)
            currentSelection = SelectionPartition(
                betweenComponentSelection: 0,
                withinComponentSelection: 0,
                transmissionChange: 0,
                covarianceSampleCount: 0
            )
            resolvedIndividualCount = 0
            resolvedCellIndividualCount = 0
            resolvedCollectiveIndividualCount = 0
            resolvedDescendantCount = 0
            autonomyVectors.removeAll(keepingCapacity: true)
            currentComponentAutonomyVectors.removeAll(keepingCapacity: true)
            resolvedIndividualLabels.removeAll(keepingCapacity: true)
            previousResolvedIndividualKeys.removeAll(keepingCapacity: true)
            individualityEvidence = .inconclusive
        }
        runtimeTelemetry = telemetry
    }

    private func updateIndividualityObserver(
        _ agents: [AgentObservation],
        cells: [CellObservation]
    ) {
        updateSelectionObserver(agents: agents, cells: cells)
        let observationStep = max(
            runtimeTelemetry.scientificallyCommittedStep,
            snapshot.totalSteps
        )
        let componentCandidates: [IndividualityCandidate] = agents.map { agent in
            let cellCount = max(Int((agent.morphology.x * 24).rounded()), 1)
            let morphology = morphologyDescriptor(for: agent)
            let parentResemblance: Double
            if agent.parentBirthID != .max,
               let parentMorphology = componentMorphologyArchive[agent.parentBirthID] {
                let morphologyResemblance = exp(-4 * morphology.distance(to: parentMorphology))
                let programResemblance = exp(-Double(agent.mutationDistance))
                parentResemblance = sqrt(morphologyResemblance * programResemblance)
            } else {
                parentResemblance = 0
            }
            let observation = ComponentObservation(
                step: observationStep,
                candidateID: UInt64(agent.birthID),
                partitionLevel: .membraneConnectedComponent,
                cellCount: cellCount,
                harvestedATP: Double(agent.energeticBoundary.x),
                importedATP: Double(agent.energeticBoundary.y),
                repairFlux: Double(agent.energeticBoundary.z),
                membraneIntegrity: Double(agent.boundary.w),
                exposedPerimeter: Double(agent.boundary.x),
                damageFlux: Double(agent.boundary.y),
                membraneTurnover: Double(agent.boundary.z),
                strainToCalcium: Double(agent.mechanochemical.x),
                calciumToERK: Double(agent.mechanochemical.y),
                erkToTraction: Double(agent.mechanochemical.z),
                tractionToStrain: Double(agent.mechanochemical.w),
                junctionTransmission: Double(agent.social.z),
                atpSharing: Double(agent.social.x),
                rejection: Double(agent.social.y),
                withinComponentReplicationAdvantage: Double(agent.social.w),
                descendantRepresentation: agent.componentDescentDepth > 0 ? 1 : 0,
                parentResemblance: parentResemblance
            )
            return IndividualityCandidate(
                observation: observation,
                positionX: Double(agent.position.x),
                positionY: Double(agent.position.y),
                isSeparatedDescendant: agent.componentDescentDepth > 0,
                environmentalDependence: Double(
                    abs(agent.environment.x) + abs(agent.environment.y) +
                    (1 - min(max(agent.environment.w, 0), 1))
                ),
                parentComponentID: nil
            )
        }
        currentComponentAutonomyVectors = componentCandidates.map {
            AutonomyVector.measured(
                from: $0.observation,
                conditionalSelfPredictiveInformation: 0
            )
        }
        var candidates = componentCandidates
        candidates.append(contentsOf: cells.map { cell in
            let observation = ComponentObservation(
                step: observationStep,
                candidateID: UInt64(cell.persistentID),
                partitionLevel: .cell,
                cellCount: 1,
                harvestedATP: Double(cell.energetic.x),
                importedATP: Double(cell.energetic.y),
                repairFlux: Double(cell.energetic.z),
                membraneIntegrity: Double(cell.energetic.w),
                exposedPerimeter: Double(cell.boundary.x),
                damageFlux: Double(cell.boundary.y),
                membraneTurnover: Double(cell.boundary.z),
                strainToCalcium: Double(cell.mechanochemical.x),
                calciumToERK: Double(cell.mechanochemical.y),
                erkToTraction: Double(cell.mechanochemical.z),
                tractionToStrain: Double(cell.mechanochemical.w),
                junctionTransmission: Double(cell.social.z),
                atpSharing: Double(cell.social.x),
                rejection: Double(cell.social.y),
                withinComponentReplicationAdvantage: Double(cell.social.w),
                descendantRepresentation: 0,
                parentResemblance: 0
            )
            return IndividualityCandidate(
                observation: observation,
                positionX: Double(cell.position.x),
                positionY: Double(cell.position.y),
                isSeparatedDescendant: false,
                environmentalDependence: Double(
                    abs(cell.environment.x) + abs(cell.environment.y) +
                    (1 - min(max(cell.environment.w, 0), 1))
                ),
                parentComponentID: UInt64(cell.componentBirthID)
            )
        })

        guard let observerResult = individualityObserver.observe(
            candidates,
            evaluationStride: 8,
            resamples: 48
        ) else { return }
        resolvedCellIndividualCount = observerResult.resolvedCellCount
        resolvedCollectiveIndividualCount = observerResult.resolvedCollectiveCount
        resolvedIndividualCount = observerResult.resolvedIndividuals.count
        resolvedDescendantCount = observerResult.resolvedDescendantCount
        autonomyVectors = observerResult.resolvedIndividuals.map(\.autonomy)
        let allResolvedKeys = observerResult.resolvedIndividuals
            .sorted {
                if $0.partitionLevel != $1.partitionLevel {
                    return $0.partitionLevel.rawValue < $1.partitionLevel.rawValue
                }
                return $0.candidateID < $1.candidateID
            }
            .map {
                ($0.partitionLevel == .cell ? "S" : "C") + "#\($0.candidateID)"
            }
        resolvedIndividualLabels = Array(allResolvedKeys.prefix(6))
        let resolvedKeys = Set(allResolvedKeys)
        for key in resolvedKeys.subtracting(previousResolvedIndividualKeys).sorted() {
            recordEvent(
                generation: snapshot.generation,
                kind: .emergence,
                title: "Observer resolved \(key)",
                detail: "The current partition sustained energetic uptake, boundary repair, mechanochemical closure, and endogenous predictability across the required autocorrelation-adjusted evidence windows. This observer result does not alter causal dynamics."
            )
        }
        for key in previousResolvedIndividualKeys.subtracting(resolvedKeys).sorted() {
            recordEvent(
                generation: snapshot.generation,
                kind: .observation,
                title: "Observer released \(key)",
                detail: "The current partition no longer sustained the full autonomy evidence conjunction across the release windows. Physical component identity and causal dynamics are unchanged."
            )
        }
        previousResolvedIndividualKeys = resolvedKeys

        let evolutionary = EvolutionaryEvidence.evaluate(
            selection: currentSelection,
            maximumComponentDescentDepth: agents.map(\.componentDescentDepth).max() ?? 0,
            livingSeparatedDescendantCount: livingDescendantCount,
            conservationValid: runtimeTelemetry.lastError == nil
        )
        let collectiveSupport = currentSelection.covarianceSampleCount >= 8 &&
            (currentSelection.betweenComponentConfidence?.lower ?? -.infinity) > 0 &&
            (currentSelection.collectiveHeritability?.lower ?? -.infinity) > 0
        let collectiveClaim = EvidenceClaim(
            state: collectiveSupport ? .supported : .inconclusive,
            estimate: currentSelection.betweenComponentConfidence,
            nullUpperBound: 0,
            reason: collectiveSupport
                ? "Measured between-component Price covariance and collective parent-descendant resemblance have positive 95% bootstrap intervals."
                : "Collective support requires eight transmitted parent components and positive 95% intervals for between-component covariance and collective resemblance.",
            timeBasis: .accumulatedHistory
        )
        individualityEvidence = IndividualityEvidence(
            endogenousPredictability: observerResult.endogenousPredictabilityClaim,
            mechanochemicalAutonomy: observerResult.autonomyClaim,
            physicalDescent: evolutionary.physicalDescent,
            heritableVariation: evolutionary.heritableVariation,
            differentialTransmission: evolutionary.differentialTransmission,
            darwinianEvolution: evolutionary.darwinianEvolution,
            collectiveLevelIndividuality: collectiveClaim,
            selection: currentSelection,
            autocorrelationTime: observerResult.autocorrelationTime,
            observationWindows: observerResult.observationWindows
        )
    }

    private func morphologyDescriptor(for agent: AgentObservation) -> MorphologyDescriptor {
        MorphologyDescriptor(values: [
            Double(agent.morphology.x),
            Double(agent.morphology.y / 0.86),
            Double((agent.morphology.z - 1) / 2.5),
            Double(agent.morphology.w),
            Double((agent.dynamics.x - 0.0008) / 0.0082),
            Double(agent.dynamics.y * 18),
            Double(agent.dynamics.z),
            Double(agent.dynamics.w)
        ])
    }

    private func archiveMorphologies(_ agents: [AgentObservation]) {
        for agent in agents {
            if componentMorphologyArchive[agent.birthID] == nil {
                componentMorphologyOrder.append(agent.birthID)
            }
            componentMorphologyArchive[agent.birthID] = morphologyDescriptor(for: agent)
        }
        let capacity = 8_192
        if componentMorphologyOrder.count > capacity {
            let excess = componentMorphologyOrder.count - capacity
            for id in componentMorphologyOrder.prefix(excess) {
                componentMorphologyArchive.removeValue(forKey: id)
            }
            componentMorphologyOrder.removeFirst(excess)
        }
    }

    private func updateSelectionObserver(
        agents: [AgentObservation],
        cells: [CellObservation]
    ) {
        let collectiveTraits = Dictionary(uniqueKeysWithValues: agents.map { agent in
            let terms = [
                agent.mechanochemical.x,
                agent.mechanochemical.y,
                agent.mechanochemical.z,
                agent.mechanochemical.w
            ].map { Double(max($0, 0)) }
            let trait = terms.contains(0) ? 0 : pow(terms.reduce(1, *), 0.25)
            return (UInt64(agent.birthID), trait)
        })
        var counts: [ObservedProgramKey: ObservedProgramCount] = [:]
        for cell in cells where cell.programID != 0 {
            let componentID = UInt64(cell.componentBirthID)
            let programID = cell.programID
            let key = ObservedProgramKey(componentID: componentID, programID: programID)
            var count = counts[key] ?? ObservedProgramCount(
                parentProgramID: cell.parentProgramID,
                inheritedTrait: Double(cell.inheritedMechanochemicalTrait),
                collectiveTrait: collectiveTraits[componentID] ?? 0,
                cellCount: 0
            )
            count.cellCount += 1
            counts[key] = count
        }
        let current = counts.map { key, count in
            ProgramRepresentation(
                componentID: key.componentID,
                programID: key.programID,
                parentProgramID: count.parentProgramID,
                cellCount: count.cellCount,
                inheritedTrait: count.inheritedTrait,
                collectiveTrait: count.collectiveTrait
            )
        }
        if !previousProgramRepresentations.isEmpty {
            let interval = MultilevelPriceAnalysis.interval(
                parent: previousProgramRepresentations,
                descendant: current,
                contributions: pendingComponentContributions
            )
            if interval.independentDescendantComponents > 0 {
                selectionIntervals.append(interval)
                if selectionIntervals.count > 256 {
                    selectionIntervals.removeFirst(selectionIntervals.count - 256)
                }
                currentSelection = MultilevelPriceAnalysis.summarize(
                    selectionIntervals,
                    resamples: 128
                )
            }
        }
        previousProgramRepresentations = current
        pendingComponentContributions.removeAll(keepingCapacity: true)
    }

    func applyLineageEvents(_ records: [RecordedLineageEvent]) {
        for record in records {
            switch record.kind {
            case .birth:
                let parent = record.parentBirthID == .max ? nil : record.parentBirthID
                if let parent {
                    let edge = ComponentAncestryEdge(
                        descendantID: record.birthID,
                        contributorID: parent,
                        step: record.step,
                        aroseByFusion: false
                    )
                    componentAncestryEdges.insert(edge)
                    pendingComponentContributions.insert(ComponentContribution(
                        descendantID: UInt64(edge.descendantID),
                        contributorID: UInt64(edge.contributorID)
                    ))
                    trimComponentAncestryHistory()
                }
                lineageBranches.insert(ObservedLineageBranch(
                    id: record.birthID,
                    parentID: parent,
                    birthStep: record.step,
                    generation: record.generation,
                    topologyHash: record.topologyHash,
                    mutationDistance: record.mutationDistance,
                    resonanceFrequency: record.resonanceFrequency,
                    deathStep: nil
                ), at: 0)
                if lineageBranches.count > 256 {
                    lineageBranches.removeLast(lineageBranches.count - 256)
                }
                lineageTracker.registerBirth(LineageBirthRecord(
                    birthID: record.birthID,
                    parentBirthID: parent,
                    birthStep: UInt64(record.step),
                    mutationDistance: Double(record.mutationDistance),
                    genomeHash: record.genomeHash,
                    topologyHash: record.topologyHash
                ))
                recordEvent(
                    generation: Int(record.generation),
                    kind: parent == nil ? .founding : .branching,
                    title: parent == nil
                        ? "Founder cell birth ID \(record.birthID) initialized"
                        : "Detached component received birth ID \(record.birthID)",
                    detail: String(
                        format: "GPU step %u; a component handle was allocated immediately after physical separation; topology hash %08X; accumulated program mutation distance %.4f; inherited resonance %.5f cycles/step. Separation itself introduced no mutation.",
                        record.step,
                        record.topologyHash,
                        record.mutationDistance,
                        record.resonanceFrequency
                    )
                )
            case .death:
                lineageTracker.registerDeath(birthID: record.birthID, step: UInt64(record.step))
                if let index = lineageBranches.firstIndex(where: { $0.id == record.birthID }) {
                    lineageBranches[index].deathStep = record.step
                }
                recordEvent(
                    generation: Int(record.generation),
                    kind: .disturbance,
                    title: "Birth ID \(record.birthID) terminated",
                    detail: String(
                        format: "GPU step %u; final energy %.4f; occupied-cell fraction %.3f.",
                        record.step,
                        record.energy,
                        record.morphology.x
                    )
                )
            case .fusion:
                fusionEventCount += 1
                let edge = ComponentAncestryEdge(
                    descendantID: record.birthID,
                    contributorID: record.parentBirthID,
                    step: record.step,
                    aroseByFusion: true
                )
                componentAncestryEdges.insert(edge)
                pendingComponentContributions.insert(ComponentContribution(
                    descendantID: UInt64(edge.descendantID),
                    contributorID: UInt64(edge.contributorID)
                ))
                trimComponentAncestryHistory()
                recordEvent(
                    generation: Int(record.generation),
                    kind: .fusion,
                    title: "Physical fusion: birth ID \(record.birthID) incorporated birth ID \(record.parentBirthID)",
                    detail: String(
                        format: "GPU step %u; the surviving connected component retained birth ID %u after direct membrane contact; topology hash %08X.",
                        record.step,
                        record.birthID,
                        record.topologyHash
                    )
                )
            case .cellDivision:
                recordEvent(
                    generation: Int(record.generation),
                    kind: .cellDivision,
                    title: "Cell #\(record.parentBirthID) divided into cell #\(record.birthID)",
                    detail: String(
                        format: "GPU step %u; daughter ATP %.4f, biomass %.4f, membrane integrity %.4f, stress %.4f; inherited program generation %u.",
                        record.step,
                        record.energy,
                        record.morphology.x,
                        record.morphology.y,
                        record.morphology.z,
                        record.generation
                    )
                )
            case .programMutation:
                recordEvent(
                    generation: Int(record.generation),
                    kind: .programMutation,
                    title: "Program mutation in daughter cell #\(record.birthID)",
                    detail: String(
                        format: "GPU step %u; replication generation %u; topology hash %08X; mutation distance %.5f; mechanosensory frequency %.5f cycles/step.",
                        record.step,
                        record.generation,
                        record.topologyHash,
                        record.mutationDistance,
                        record.resonanceFrequency
                    )
                )
            case .crossbreeding:
                crossbreedingEventCount += 1
                recordEvent(
                    generation: Int(record.generation),
                    kind: .crossbreeding,
                    title: "Crossbred program in daughter cell #\(record.birthID)",
                    detail: String(
                        format: "GPU step %u; compatible donor cell #%u contributed the second inherited program; recombination distance %.5f; resulting topology hash %08X.",
                        record.step,
                        record.parentBirthID,
                        record.mutationDistance,
                        record.topologyHash
                    )
                )
            }
        }
    }

    private func trimComponentAncestryHistory() {
        let capacity = 8_192
        guard componentAncestryEdges.count > capacity + 512 else { return }
        componentAncestryEdges = Set(componentAncestryEdges.sorted {
            ($0.step, $0.descendantID, $0.contributorID) >
                ($1.step, $1.descendantID, $1.contributorID)
        }.prefix(capacity))
    }

    var effectiveZoom: Double {
        cameraZoom / worldScale
    }

    var observationZoom: Double {
        effectiveZoom
    }

    func apply(_ newSnapshot: EvolutionSnapshot) {
        var analyzedSnapshot = newSnapshot
        analyzedSnapshot.persistentCladeCount = lineageAnalysis.persistentCladeCount
        analyzedSnapshot.meanMorphologyDistance = lineageAnalysis.meanMorphologyDistance
        snapshot = analyzedSnapshot
        guard analyzedSnapshot.generation > lastRecordedGeneration else { return }

        let previous = history.last
        history.append(analyzedSnapshot)
        if history.count > 120 {
            history.removeFirst(history.count - 120)
        }
        lastRecordedGeneration = analyzedSnapshot.generation
        observeMechanosensoryIntervention(to: analyzedSnapshot)
        observeChange(from: previous, to: analyzedSnapshot)
        if analyzedSnapshot.metrics.occupiedFraction > 0.72 {
            expandBackingWorld()
        }
    }

    func report(error: Error) {
        errorMessage = error.localizedDescription
        isRunning = false
    }

    private func aspectScale(for aspect: Float) -> SIMD2<Float> {
        aspect >= 1
            ? SIMD2<Float>(1, 1 / max(aspect, 0.001))
            : SIMD2<Float>(max(aspect, 0.001), 1)
    }

    private func textureCoordinate(_ position: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2<Float>(
            position.x - floor(position.x),
            position.y - floor(position.y)
        )
    }

    private func expandWorldIfNeeded(aspect: Float) {
        let scale = aspectScale(for: aspect)
        var iterations = 0
        while iterations < 64 {
            let halfView = scale * (0.5 / Float(cameraZoom))
            let exposesEdge = cameraZoom < 1 ||
                cameraCenter.x - halfView.x < 0 || cameraCenter.x + halfView.x > 1 ||
                cameraCenter.y - halfView.y < 0 || cameraCenter.y + halfView.y > 1
            guard exposesEdge else { return }
            expandBackingWorld()
            iterations += 1
        }
    }

    private func expandBackingWorld() {
        cameraCenter = SIMD2<Float>(repeating: 0.25) + cameraCenter * 0.5
        cameraZoom *= 2
        worldScale *= 2
        expansionToken &+= 1
    }

    private func observeChange(from previous: EvolutionSnapshot?, to current: EvolutionSnapshot) {
        guard let previous else {
            recordEvent(
                generation: current.generation,
                kind: .founding,
                title: "First metric reduction completed",
                detail: "Occupied-cell fraction \(percent(current.metrics.occupiedFraction)); mean biomass density \(decimal(current.metrics.biomassDensity))."
            )
            return
        }

        let occupancyDelta = current.metrics.occupiedFraction - previous.metrics.occupiedFraction
        let currentBranches = lineageEstimate(current.metrics.lineageDiversity)
        let previousBranches = lineageEstimate(previous.metrics.lineageDiversity)
        var recordedMajorEvent = false

        if let milestone = crossedOccupancyMilestone(
            from: previous.metrics.occupiedFraction,
            to: current.metrics.occupiedFraction
        ) {
            recordEvent(
                generation: current.generation,
                kind: .expansion,
                title: "Occupied-cell fraction crossed \(percent(milestone))",
                detail: "Current occupied-cell fraction: \(percent(current.metrics.occupiedFraction))."
            )
            recordedMajorEvent = true
        } else if occupancyDelta < -0.025 {
            recordEvent(
                generation: current.generation,
                kind: .disturbance,
                title: "Occupied-cell fraction decreased",
                detail: "Reduction between metric samples: \(percentagePoints(-occupancyDelta))."
            )
            recordedMajorEvent = true
        }

        if currentBranches >= previousBranches + 2 {
            recordEvent(
                generation: current.generation,
                kind: .branching,
                title: "Occupied lineage-bin count increased",
                detail: "The 16-bin lineage estimator increased from \(previousBranches) to \(currentBranches)."
            )
            recordedMajorEvent = true
        }

        if current.metrics.resourceDensity < 0.015,
           previous.metrics.resourceDensity >= 0.015 {
            recordEvent(
                generation: current.generation,
                kind: .scarcity,
                title: "Mean resource density crossed below 0.015",
                detail: "Measured free-resource density: \(decimal(current.metrics.resourceDensity))."
            )
            recordedMajorEvent = true
        }

        if current.generation >= 9, (current.generation - 1).isMultiple(of: 8) {
            recordEvent(
                generation: current.generation,
                kind: .disturbance,
                title: "Post-perturbation recovery sampled",
                detail: "Recovered biomass divided by pre-perturbation biomass: \(percent(current.metrics.recovery))."
            )
            recordedMajorEvent = true
        }

        if current.metrics.occupiedFraction > 0.75,
           current.metrics.temporalActivity < 0.003,
           previous.metrics.temporalActivity >= 0.003 {
            recordEvent(
                generation: current.generation,
                kind: .equilibrium,
                title: "High-occupancy, low-activity condition detected",
                detail: "Occupied-cell fraction > 0.75 and temporal activity < 0.003."
            )
            recordedMajorEvent = true
        }

        if !recordedMajorEvent, current.generation.isMultiple(of: 5) {
            recordEvent(
                generation: current.generation,
                kind: .observation,
                title: observationTitle(for: current),
                detail: observationDetail(for: current)
            )
        }
    }

    private func observeMechanosensoryIntervention(to current: EvolutionSnapshot) {
        guard let pending = pendingMechanosensoryIntervention,
              current.generation > pending.baseline.generation else { return }
        let baseline = pending.baseline
        let baselineDivisionFraction = Double(baseline.dividingCellCount) / Double(max(baseline.cellCount, 1))
        let currentDivisionFraction = Double(current.dividingCellCount) / Double(max(current.cellCount, 1))
        recordEvent(
            generation: current.generation,
            kind: .intervention,
            title: pending.blocked
                ? "Mechanosensory ablation response measured"
                : "Mechanosensory restoration response measured",
            detail: String(
                format: "Single-trajectory response, not a controlled effect estimate: ΔVₘ %+.4f; ΔCa* %+.4f; ΔERK* %+.4f; Δdividing fraction %+.3f.",
                current.meanMembraneVoltage - baseline.meanMembraneVoltage,
                current.meanCalciumActivity - baseline.meanCalciumActivity,
                current.meanERKActivity - baseline.meanERKActivity,
                currentDivisionFraction - baselineDivisionFraction
            )
        )
        pendingMechanosensoryIntervention = nil
    }

    private func recordEvent(
        generation: Int,
        kind: EvolutionEventKind,
        title: String,
        detail: String
    ) {
        if let matchingEvent = events.first(where: { $0.title == title }),
           generation - matchingEvent.generation < 12 {
            return
        }
        let event = EvolutionEvent(
            id: nextEventID,
            generation: generation,
            kind: kind,
            title: title,
            detail: detail
        )
        nextEventID &+= 1
        events.insert(event, at: 0)
        if events.count > 12 {
            events.removeLast(events.count - 12)
        }
    }

    private func observationTitle(for snapshot: EvolutionSnapshot) -> String {
        if snapshot.metrics.temporalActivity > 0.03 { return "Temporal activity exceeds 0.030" }
        if snapshot.fitness.diversification > 0.35 { return "Diversification score exceeds 0.35" }
        if snapshot.metrics.occupiedFraction > 0.72 { return "Occupied-cell fraction exceeds 0.72" }
        return "Periodic metric reduction completed"
    }

    private func crossedOccupancyMilestone(from previous: Double, to current: Double) -> Double? {
        [0.90, 0.75, 0.50, 0.30, 0.15, 0.05]
            .first { previous < $0 && current >= $0 }
    }

    private func observationDetail(for snapshot: EvolutionSnapshot) -> String {
        "Occupied \(percent(snapshot.metrics.occupiedFraction)); " +
            "lineage bins \(lineageEstimate(snapshot.metrics.lineageDiversity))/16; " +
            "mean temporal activity \(decimal(snapshot.metrics.temporalActivity))."
    }

    private func lineageEstimate(_ entropy: Double) -> Int {
        max(1, min(16, Int(pow(16, min(max(entropy, 0), 1)).rounded())))
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", min(max(value, 0), 1) * 100)
    }

    private func percentagePoints(_ value: Double) -> String {
        String(format: "%.1f points", min(max(value, 0), 1) * 100)
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.4f", max(value, 0))
    }
}
