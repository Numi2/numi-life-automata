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
        case .ecology: "State fields"
        case .energy: "Resource / energy"
        case .genome: "Trait vectors"
        case .niches: "Resource-use traits"
        case .development: "Developmental regulation"
        case .causality: "Causal terms"
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

struct EvolutionSnapshot: Sendable, Equatable {
    var generation: Int = 0
    var totalSteps: UInt64 = 0
    var selectedWorld: Int = 0
    var archiveCount: Int = 0
    var quantumNorm: Double = 0
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
    var metrics: WorldMetrics = .empty
    var fitness = FitnessVector(viability: 0, adaptiveComplexity: 0, recovery: 0, novelty: 0)

    init(
        generation: Int = 0,
        totalSteps: UInt64 = 0,
        selectedWorld: Int = 0,
        archiveCount: Int = 0,
        quantumNorm: Double = 0,
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

struct RendererSettings: Sendable {
    var isRunning: Bool
    var stepsPerFrame: Int
    var resourceFlux: Float
    var mutationScale: Float
    var transportScale: Float
    var mechanosensingGain: Float
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
    @Published var stepsPerFrame = 3
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
    @Published private(set) var followedAgentID: Int?
    @Published private(set) var observableAgentCount = 0
    @Published private(set) var lineageAnalysis = LineageAnalysis.empty
    @Published private(set) var lineageBranches: [ObservedLineageBranch] = []
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
    private var lineageTracker = LineageDivergenceTracker()
    private var hasObservedFirstOrganism = false
    private var pendingMechanosensoryIntervention: (baseline: EvolutionSnapshot, blocked: Bool)?

    var rendererSettings: RendererSettings {
        RendererSettings(
            isRunning: isRunning,
            stepsPerFrame: stepsPerFrame,
            resourceFlux: Float(resourceFlux),
            mutationScale: Float(mutationScale),
            transportScale: Float(transportScale),
            mechanosensingGain: mechanosensingBlocked ? 0 : 1,
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
        lineageAnalysis = .empty
        lineageBranches.removeAll(keepingCapacity: true)
        lineageTracker.reset()
        followedBirthID = nil
        worldScale = 1
        expansionToken = 0
        lastRecordedGeneration = 0
        hasObservedFirstOrganism = false
        mechanosensingBlocked = false
        pendingMechanosensoryIntervention = nil
        resetCamera()
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
        hasObservedFirstOrganism = true
        addColonyToken &+= 1
        recordEvent(
            generation: snapshot.generation,
            kind: .intervention,
            title: "External agent slot initialized",
            detail: "Founder \(founderCount) received three sampled four-component trait vectors at the camera position."
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
        followedAgentID = nil
        let worldDelta = screenDelta * aspectScale(for: aspect) / Float(cameraZoom)
        cameraCenter -= worldDelta
        expandWorldIfNeeded(aspect: aspect)
    }

    func resetCamera() {
        followedAgentID = nil
        cameraCenter = Self.spinorOrigin
        cameraZoom = worldScale * 900
    }

    func followRandomOrganism() {
        guard let agent = observedAgents.randomElement() else { return }
        follow(agent)
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

    func applyAgentObservations(_ agents: [AgentObservation]) {
        observedAgents = agents
        if observableAgentCount != agents.count {
            observableAgentCount = agents.count
        }
        if !hasObservedFirstOrganism, let founder = agents.first {
            hasObservedFirstOrganism = true
            founderCount = 1
            recordEvent(
                generation: snapshot.generation,
                kind: .founding,
                title: "Founder-state thresholds satisfied",
                detail: String(
                    format: "Agent slot %d initialized at (%.4f, %.4f) after local biomass, energy, membrane, and catalyst thresholds were met.",
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
                if simd_distance_squared(cameraCenter, followed.position) > 1.0e-14 {
                    cameraCenter = followed.position
                }
            } else if let replacement = agents.first {
                follow(replacement)
            } else {
                self.followedAgentID = nil
                followedBirthID = nil
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
    }

    private func follow(_ agent: AgentObservation) {
        followedAgentID = agent.id
        followedBirthID = agent.birthID
        cameraCenter = agent.position
    }

    func applyLineageEvents(_ records: [RecordedLineageEvent]) {
        for record in records {
            switch record.kind {
            case .birth:
                let parent = record.parentBirthID == .max ? nil : record.parentBirthID
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
                        ? "Founder birth ID \(record.birthID) initialized"
                        : "Birth ID \(record.birthID) descended from \(parent!)",
                    detail: String(
                        format: "GPU step %u; topology hash %08X; branch mutation distance %.4f; inherited resonance %.5f cycles/step.",
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
            }
        }
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
