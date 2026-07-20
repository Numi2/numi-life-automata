import AutogenesisCore
import Foundation
import Metal
import MetalKit
import simd

private struct SimulationUniforms {
    var width: UInt32
    var height: UInt32
    var worldCount: UInt32
    var step: UInt32
    var dt: Float
    var resourceFlux: Float
    var mutationScale: Float
    var transportScale: Float
    var displayMode: UInt32
    var trackedAgentID: UInt32
    var generation: UInt32
    var epochSteps: UInt32
    var damageStep: UInt32
    var brushPosition: SIMD2<Float>
    var brushRadius: Float
    var brushStrength: Float
    var cameraCenter: SIMD2<Float>
    var cameraZoom: Float
    var worldScale: Float
    var viewportAspect: Float
    var intervention: SIMD4<Float>
}

private struct PostProcessUniforms {
    var sourceSize: SIMD2<Float>
    var exposure: Float
    var bloomIntensity: Float
    var observationZoom: Float
    var frameIndex: UInt32
}

private struct AgentState {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var behavior: SIMD4<Float>
    var geneA: SIMD4<Float>
    var geneB: SIMD4<Float>
    var geneC: SIMD4<Float>
    var recognition: SIMD4<Float>
    var social: SIMD4<Float>
    var energy: Float
    var biomass: Float
    var age: Float
    var generation: UInt32
    var birthID: UInt32
    var parentBirthID: UInt32
    var genomeHash: UInt32
    var birthStep: UInt32
    var mutationDistance: Float
    var lastMutationDistance: Float
    var lineageFlags: UInt32
    var dominantProgramIndex: UInt32
    var tissueKinematics: SIMD4<Float>
}

private struct AgentObservationRecord {
    var position: SIMD2<Float>
    var generation: UInt32
    var flags: UInt32
    var birthID: UInt32
    var parentBirthID: UInt32
    var genomeHash: UInt32
    var topologyHash: UInt32
    var morphology: SIMD4<Float>
    var dynamics: SIMD4<Float>
    var mutationDistance: Float
    var padding: SIMD3<Float>
}

private struct CellState {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var physiology: SIMD4<Float>
    var phenotype: SIMD4<Float>
    var signals: SIMD4<Float>
    var interaction: SIMD4<Float>
    var dynamics: SIMD4<Float>
    var mechanics: SIMD4<Float>
    var energetics: SIMD4<Float>
    var regulation: SIMD4<Float>
    var regulationB: SIMD4<Float>
    var resonance: SIMD4<Float>
    var membrane: SIMD4<Float>
    var signaling: SIMD4<Float>
    var signalCausality: SIMD4<Float>
    var tissueGeometry: SIMD4<Float>
    var tissueForce: SIMD4<Float>
}

private struct CellIdentity {
    var owner: UInt32
    var programIndex: UInt32
    var persistentID: UInt32
    var componentRoot: UInt32
}

private struct HeritableProgram {
    var geneA: SIMD4<Float>
    var geneB: SIMD4<Float>
    var geneC: SIMD4<Float>
    var recognition: SIMD4<Float>
    var social: SIMD4<Float>
    var genomeHash: UInt32
    var parentProgramIndex: UInt32
    var originBirthID: UInt32
    var generation: UInt32
}

private struct CellAggregate {
    var physiology: SIMD4<Float>
    var morphology: SIMD4<Float>
    var dynamics: SIMD4<Float>
    var mechanics: SIMD4<Float>
    var energetics: SIMD4<Float>
    var regulation: SIMD4<Float>
    var regulationB: SIMD4<Float>
    var causality: SIMD4<Float>
    var resonance: SIMD4<Float>
    var shape: SIMD4<Float>
    var signaling: SIMD4<Float>
    var signalCausality: SIMD4<Float>
    var geometryAxes: SIMD4<Float>
    var geometryBoundary: SIMD4<Float>
    var tissueMotion: SIMD4<Float>
    var trophic: SIMD4<Float>
    var inheritance: SIMD4<Float>
    var programEcology: SIMD4<Float>
}

private struct DevelopmentalGenome {
    var topology: SIMD4<UInt32>
    var mutation: SIMD4<Float>
    var actuatorBiasA: SIMD4<Float>
    var actuatorBiasB: SIMD4<Float>
    var mechanochemistryA: SIMD4<Float>
    var mechanochemistryB: SIMD4<Float>
}

private struct RegulatoryNode {
    var bias: Float
    var responseRate: Float
    var sensorWeight: Float
    var outputWeight: Float
    var sensorIndex: UInt32
    var actuatorMask: UInt32
    var innovationID: UInt32
    var flags: UInt32
}

private struct RegulatoryEdge {
    var weight: Float
    var plasticity: Float
    var delay: Float
    var reserved: Float
    var source: UInt32
    var target: UInt32
    var innovationID: UInt32
    var flags: UInt32
}

private struct ResonanceGenome {
    var mechanics: SIMD4<Float>
    var tuning: SIMD4<Float>
}

private struct ProgramMetricRecord {
    var developmental: DevelopmentalGenome
    var resonance: ResonanceGenome
}

private struct MembraneVertex {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var mechanics: SIMD4<Float>
}

private struct LineageEventRecord {
    var sequence: UInt32
    var kind: UInt32
    var birthID: UInt32
    var parentBirthID: UInt32
    var step: UInt32
    var generation: UInt32
    var genomeHash: UInt32
    var topologyHash: UInt32
    var mutationDistance: Float
    var resonanceFrequency: Float
    var morphologyDistance: Float
    var energy: Float
    var morphology: SIMD4<Float>
}

struct AgentObservation: Sendable, Equatable {
    let id: Int
    let birthID: UInt32
    let parentBirthID: UInt32
    let position: SIMD2<Float>
    let generation: UInt32
    let isHunter: Bool
    let genomeHash: UInt32
    let topologyHash: UInt32
    let morphology: SIMD4<Float>
    let dynamics: SIMD4<Float>
    let mutationDistance: Float
}

struct RecordedLineageEvent: Sendable, Equatable {
    enum Kind: UInt32, Sendable {
        case birth = 1
        case death = 2
        case fusion = 3
    }

    let sequence: UInt32
    let kind: Kind
    let birthID: UInt32
    let parentBirthID: UInt32
    let step: UInt32
    let generation: UInt32
    let genomeHash: UInt32
    let topologyHash: UInt32
    let mutationDistance: Float
    let resonanceFrequency: Float
    let energy: Float
    let morphology: SIMD4<Float>
}

private struct SendableAgentObservationBuffers: @unchecked Sendable {
    let records: MTLBuffer
    let lineageEvents: MTLBuffer
    let identityCounters: MTLBuffer
}

private final class AgentObservationRingState: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight: [Bool]

    init(slotCount: Int) {
        inFlight = Array(repeating: false, count: slotCount)
    }

    func acquire() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard let slot = inFlight.firstIndex(of: false) else { return nil }
        inFlight[slot] = true
        return slot
    }

    func release(_ slot: Int) {
        lock.lock()
        inFlight[slot] = false
        lock.unlock()
    }
}

private final class LineageEventDeliveryState: @unchecked Sendable {
    private let lock = NSLock()
    private var lastSequence: UInt32 = 0

    func consume(
        records: UnsafePointer<LineageEventRecord>,
        writeSequence: UInt32,
        capacity: Int
    ) -> [RecordedLineageEvent] {
        lock.lock()
        defer { lock.unlock() }
        guard writeSequence > lastSequence else { return [] }
        let earliest = writeSequence > UInt32(capacity)
            ? writeSequence - UInt32(capacity) + 1
            : 1
        let start = max(lastSequence + 1, earliest)
        var result: [RecordedLineageEvent] = []
        result.reserveCapacity(Int(writeSequence - start + 1))
        for sequence in start...writeSequence {
            let record = records[Int((sequence - 1) % UInt32(capacity))]
            guard record.sequence == sequence,
                  let kind = RecordedLineageEvent.Kind(rawValue: record.kind) else { continue }
            result.append(RecordedLineageEvent(
                sequence: sequence,
                kind: kind,
                birthID: record.birthID,
                parentBirthID: record.parentBirthID,
                step: record.step,
                generation: record.generation,
                genomeHash: record.genomeHash,
                topologyHash: record.topologyHash,
                mutationDistance: record.mutationDistance,
                resonanceFrequency: record.resonanceFrequency,
                energy: record.energy,
                morphology: record.morphology
            ))
        }
        lastSequence = writeSequence
        return result
    }

    func reset() {
        lock.lock()
        lastSequence = 0
        lock.unlock()
    }
}

private final class MetricReadbackSlot: @unchecked Sendable {
    let metrics: MTLBuffer
    let quantumNorm: MTLBuffer
    let agentState: MTLBuffer
    let agentOccupancy: MTLBuffer
    let cellAggregates: MTLBuffer
    let programRecords: MTLBuffer
    let identityCounters: MTLBuffer

    init(
        metrics: MTLBuffer,
        quantumNorm: MTLBuffer,
        agentState: MTLBuffer,
        agentOccupancy: MTLBuffer,
        cellAggregates: MTLBuffer,
        programRecords: MTLBuffer,
        identityCounters: MTLBuffer
    ) {
        self.metrics = metrics
        self.quantumNorm = quantumNorm
        self.agentState = agentState
        self.agentOccupancy = agentOccupancy
        self.cellAggregates = cellAggregates
        self.programRecords = programRecords
        self.identityCounters = identityCounters
    }
}

private struct PendingMetricObservation: Sendable {
    let slotIndex: Int
    let generation: UInt32
    let totalSteps: UInt64
    let settings: RendererSettings
    let resetToken: UInt64
}

private struct BrushEvent: Sendable {
    var position: SIMD2<Float>
}

enum EvolutionRendererError: LocalizedError {
    case noMetalDevice
    case missingShader
    case missingFunction(String)
    case resourceAllocation(String)

    var errorDescription: String? {
        switch self {
        case .noMetalDevice: "This Mac does not expose a Metal device."
        case .missingShader: "The Numi Automata Metal source is missing from the app bundle."
        case let .missingFunction(name): "The Metal function \(name) could not be loaded."
        case let .resourceAllocation(name): "Metal could not allocate \(name)."
        }
    }
}

@MainActor
final class EvolutionRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    static let worldCount = 1
    static let gridSize = 193
    static let quantumGridSize = 1_024
    static let epochSteps = 1_200
    static let damageStep = 600
    private static let maxAgentCount = 384
    private static let maxCellCount = 9_216
    private static let maxHeritableProgramCount = 4_096
    private static let maxProgramsPerPropagule = 16
    private static let regulatoryNodeCapacity = 16
    private static let regulatoryEdgeCapacity = 48
    private static let membraneVertexCount = 12
    private static let cellSpatialHashBucketCount = 16_384
    private static let lineageEventCapacity = 4_096
    private static let agentObservationRingSize = 3
    private static let agentObservationIntervalFrames: UInt64 = 6
    private static let trackedAgentObservationIntervalFrames: UInt64 = 2
    private static let metricReadbackRingSize = 3
    private static let metricCount = 32
    private static let metricScale = 4096.0
    private static let quantumMetricScale = 1_000_000_000.0
    private static let gpuTimingEnabled = ProcessInfo.processInfo.environment["NUMI_GPU_TIMING"] == "1"

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let initializePipeline: MTLComputePipelineState
    private let initializeQuantumPipeline: MTLComputePipelineState
    private let expandWorldPipeline: MTLComputePipelineState
    private let expandQuantumPipeline: MTLComputePipelineState
    private let initializeMechanicalPipeline: MTLComputePipelineState
    private let expandMechanicalPipeline: MTLComputePipelineState
    private let evolveMechanicalPipeline: MTLComputePipelineState
    private let reactionPipeline: MTLComputePipelineState
    private let quantumPipeline: MTLComputePipelineState
    private let damagePipeline: MTLComputePipelineState
    private let brushPipeline: MTLComputePipelineState
    private let measurementPipeline: MTLComputePipelineState
    private let quantumMeasurementPipeline: MTLComputePipelineState
    private let initializeAgentPipeline: MTLComputePipelineState
    private let nucleateFounderPipeline: MTLComputePipelineState
    private let evolveAgentPipeline: MTLComputePipelineState
    private let injectFounderPipeline: MTLComputePipelineState
    private let expandAgentPipeline: MTLComputePipelineState
    private let collectAgentObservationPipeline: MTLComputePipelineState
    private let collectProgramMetricPipeline: MTLComputePipelineState
    private let evolveCellPipeline: MTLComputePipelineState
    private let evolveMembranePipeline: MTLComputePipelineState
    private let clearCellSpatialHashPipeline: MTLComputePipelineState
    private let buildCellSpatialHashPipeline: MTLComputePipelineState
    private let clearOwnerCellListsPipeline: MTLComputePipelineState
    private let buildOwnerCellListsPipeline: MTLComputePipelineState
    private let resolveCellContactsPipeline: MTLComputePipelineState
    private let applyCellContactEffectsPipeline: MTLComputePipelineState
    private let initializeCellComponentsPipeline: MTLComputePipelineState
    private let unionCellComponentsPipeline: MTLComputePipelineState
    private let compressCellComponentsPipeline: MTLComputePipelineState
    private let accumulateCellComponentsPipeline: MTLComputePipelineState
    private let selectPrimaryCellComponentsPipeline: MTLComputePipelineState
    private let assignCellComponentOwnersPipeline: MTLComputePipelineState
    private let reassignCellComponentsPipeline: MTLComputePipelineState
    private let divideAndReduceCellPipeline: MTLComputePipelineState
    private let compactCellRenderPipeline: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState
    private let cellularSurfacePipeline: MTLRenderPipelineState
    private let quantumRenderPipeline: MTLRenderPipelineState
    private let agentRenderPipeline: MTLRenderPipelineState
    private let cellRenderPipeline: MTLRenderPipelineState
    private let bloomPrefilterPipeline: MTLComputePipelineState
    private let bloomBlurPipeline: MTLComputePipelineState
    private let compositePipeline: MTLRenderPipelineState
    private var sceneColor: MTLTexture?
    private var bloomTextureA: MTLTexture?
    private var bloomTextureB: MTLTexture?
    private var renderTargetSize = MTLSize(width: 0, height: 0, depth: 1)
    private var state: MTLTexture
    private var reactionState: MTLTexture
    private var genomeA: MTLTexture
    private var reactionGenomeA: MTLTexture
    private var genomeB: MTLTexture
    private var reactionGenomeB: MTLTexture
    private var ecology: MTLTexture
    private var reactionEcology: MTLTexture
    private var genomeC: MTLTexture
    private var reactionGenomeC: MTLTexture
    private let checkpointState: MTLTexture
    private var eventState: MTLTexture
    private var reactionEventState: MTLTexture
    private var environmentState: MTLTexture
    private var reactionEnvironmentState: MTLTexture
    private var mechanicalState: MTLTexture
    private var reactionMechanicalState: MTLTexture
    private var quantumState: MTLTexture
    private var reactionQuantumState: MTLTexture
    private var agentState: MTLBuffer
    private var reactionAgentState: MTLBuffer
    private let agentOccupancy: MTLBuffer
    private var cellState: MTLBuffer
    private var reactionCellState: MTLBuffer
    private let cellOccupancy: MTLBuffer
    private let cellIdentities: MTLBuffer
    private let cellParentIDs: MTLBuffer
    private let programInteractions: MTLBuffer
    private let ownerCellHeads: MTLBuffer
    private let ownerCellNext: MTLBuffer
    private let cellComponentParents: MTLBuffer
    private let cellComponentCounts: MTLBuffer
    private let cellComponentAccumulation: MTLBuffer
    private let cellComponentOwners: MTLBuffer
    private let cellComponentPrograms: MTLBuffer
    private let cellComponentProgramSources: MTLBuffer
    private let cellComponentProgramTargets: MTLBuffer
    private let ownerPrimaryRoots: MTLBuffer
    private let cellAggregates: MTLBuffer
    private let heritablePrograms: MTLBuffer
    private let developmentalGenomes: MTLBuffer
    private let regulatoryNodes: MTLBuffer
    private let regulatoryEdges: MTLBuffer
    private let regulatoryStates: MTLBuffer
    private let resonanceGenomes: MTLBuffer
    private let membraneVertices: MTLBuffer
    private let cellSpatialHashHeads: MTLBuffer
    private let cellSpatialHashNext: MTLBuffer
    private let cellContactEffects: MTLBuffer
    private let visibleCellIndices: MTLBuffer
    private let cellDrawArguments: MTLBuffer
    private let identityCounters: MTLBuffer
    private let lineageEvents: MTLBuffer
    private let mechanicalForcing: MTLBuffer
    private let agentObservationBuffers: [MTLBuffer]
    private let lineageEventObservationBuffers: [MTLBuffer]
    private let identityCounterObservationBuffers: [MTLBuffer]
    private let metricReadbackSlots: [MetricReadbackSlot]
    private let stateLock = NSLock()
    private let agentObservationRingState = AgentObservationRingState(slotCount: agentObservationRingSize)
    private let lineageEventDeliveryState = LineageEventDeliveryState()
    private var settings = RendererSettings(
        isRunning: true,
        stepsPerFrame: 3,
        resourceFlux: 1,
        mutationScale: 1,
        transportScale: 1,
        mechanosensingGain: 1,
        displayMode: 0,
        trackedAgentID: .max,
        cameraCenter: SIMD2<Float>(repeating: 0.5),
        cameraZoom: 1,
        worldScale: 1,
        addColonyPosition: SIMD2<Float>(repeating: 0.5),
        addColonyToken: 0,
        expansionToken: 0,
        resetToken: 1
    )
    private var appliedResetToken: UInt64 = 0
    private var appliedAddColonyToken: UInt64 = 0
    private var appliedExpansionToken: UInt64 = 0
    private var viewportAspect: Float = 1
    private var totalSteps: UInt64 = 0
    private var quantumStep: UInt32 = 0
    private var generation: UInt32 = 0
    private var frameSerial: UInt64 = 0
    private var metricSlotsInFlight = Array(repeating: false, count: metricReadbackRingSize)
    private var evaluator = AdaptiveComplexityEvaluator(seed: 0xA170_6E51, eliteCount: 1)
    private var latestSnapshot = EvolutionSnapshot()

    var onSnapshot: (@Sendable (EvolutionSnapshot) -> Void)?
    var onObservationBatch: (@Sendable ([RecordedLineageEvent], [AgentObservation]) -> Void)?

    init(view: MTKView) throws {
        precondition(MemoryLayout<AgentState>.stride == 176, "AgentState Metal ABI drift")
        precondition(MemoryLayout<AgentObservationRecord>.stride == 96, "AgentObservationRecord Metal ABI drift")
        precondition(MemoryLayout<CellState>.stride == 256, "CellState Metal ABI drift")
        precondition(MemoryLayout<CellIdentity>.stride == 16, "CellIdentity Metal ABI drift")
        precondition(MemoryLayout<HeritableProgram>.stride == 96, "HeritableProgram Metal ABI drift")
        precondition(MemoryLayout<CellAggregate>.stride == 288, "CellAggregate Metal ABI drift")
        precondition(MemoryLayout<DevelopmentalGenome>.stride == 96, "DevelopmentalGenome Metal ABI drift")
        precondition(MemoryLayout<RegulatoryNode>.stride == 32, "RegulatoryNode Metal ABI drift")
        precondition(MemoryLayout<RegulatoryEdge>.stride == 32, "RegulatoryEdge Metal ABI drift")
        precondition(MemoryLayout<ResonanceGenome>.stride == 32, "ResonanceGenome Metal ABI drift")
        precondition(MemoryLayout<ProgramMetricRecord>.stride == 128, "ProgramMetricRecord Metal ABI drift")
        precondition(MemoryLayout<MembraneVertex>.stride == 32, "MembraneVertex Metal ABI drift")
        precondition(MemoryLayout<LineageEventRecord>.stride == 64, "LineageEventRecord Metal ABI drift")
        guard let device = view.device ?? MTLCreateSystemDefaultDevice() else {
            throw EvolutionRendererError.noMetalDevice
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw EvolutionRendererError.resourceAllocation("the command queue")
        }
        self.device = device
        self.commandQueue = commandQueue
        view.device = device

        let library = try Self.makeLibrary(device: device)
        initializePipeline = try Self.computePipeline(named: "initializeWorld", library: library, device: device)
        initializeQuantumPipeline = try Self.computePipeline(named: "initializeQuantumField", library: library, device: device)
        expandWorldPipeline = try Self.computePipeline(named: "expandWorld", library: library, device: device)
        expandQuantumPipeline = try Self.computePipeline(named: "expandQuantumField", library: library, device: device)
        initializeMechanicalPipeline = try Self.computePipeline(
            named: "initializeMechanicalField", library: library, device: device
        )
        expandMechanicalPipeline = try Self.computePipeline(
            named: "expandMechanicalField", library: library, device: device
        )
        evolveMechanicalPipeline = try Self.computePipeline(
            named: "evolveMechanicalField", library: library, device: device
        )
        reactionPipeline = try Self.computePipeline(named: "reactWorld", library: library, device: device)
        quantumPipeline = try Self.computePipeline(named: "evolveQuantumField", library: library, device: device)
        damagePipeline = try Self.computePipeline(named: "damageWorld", library: library, device: device)
        brushPipeline = try Self.computePipeline(named: "applyBrush", library: library, device: device)
        measurementPipeline = try Self.computePipeline(named: "measureWorld", library: library, device: device)
        quantumMeasurementPipeline = try Self.computePipeline(named: "measureQuantumField", library: library, device: device)
        initializeAgentPipeline = try Self.computePipeline(named: "initializeAgents", library: library, device: device)
        nucleateFounderPipeline = try Self.computePipeline(named: "nucleateAutogenicFounder", library: library, device: device)
        evolveAgentPipeline = try Self.computePipeline(named: "evolveAgents", library: library, device: device)
        injectFounderPipeline = try Self.computePipeline(named: "injectFounder", library: library, device: device)
        expandAgentPipeline = try Self.computePipeline(named: "expandAgents", library: library, device: device)
        collectAgentObservationPipeline = try Self.computePipeline(
            named: "collectAgentObservations",
            library: library,
            device: device
        )
        collectProgramMetricPipeline = try Self.computePipeline(
            named: "collectProgramMetricRecords",
            library: library,
            device: device
        )
        evolveCellPipeline = try Self.computePipeline(
            named: "evolveOrganismCells",
            library: library,
            device: device
        )
        evolveMembranePipeline = try Self.computePipeline(
            named: "evolveCellMembranes",
            library: library,
            device: device
        )
        clearCellSpatialHashPipeline = try Self.computePipeline(
            named: "clearCellSpatialHash", library: library, device: device
        )
        buildCellSpatialHashPipeline = try Self.computePipeline(
            named: "buildCellSpatialHash", library: library, device: device
        )
        clearOwnerCellListsPipeline = try Self.computePipeline(
            named: "clearOwnerCellLists", library: library, device: device
        )
        buildOwnerCellListsPipeline = try Self.computePipeline(
            named: "buildOwnerCellLists", library: library, device: device
        )
        resolveCellContactsPipeline = try Self.computePipeline(
            named: "resolveCrossOrganismCellContacts", library: library, device: device
        )
        applyCellContactEffectsPipeline = try Self.computePipeline(
            named: "applyCellContactEffects", library: library, device: device
        )
        initializeCellComponentsPipeline = try Self.computePipeline(
            named: "initializeCellComponents", library: library, device: device
        )
        unionCellComponentsPipeline = try Self.computePipeline(
            named: "unionCellComponents", library: library, device: device
        )
        compressCellComponentsPipeline = try Self.computePipeline(
            named: "compressCellComponents", library: library, device: device
        )
        accumulateCellComponentsPipeline = try Self.computePipeline(
            named: "accumulateCellComponents", library: library, device: device
        )
        selectPrimaryCellComponentsPipeline = try Self.computePipeline(
            named: "selectPrimaryCellComponents", library: library, device: device
        )
        assignCellComponentOwnersPipeline = try Self.computePipeline(
            named: "assignCellComponentOwners", library: library, device: device
        )
        reassignCellComponentsPipeline = try Self.computePipeline(
            named: "reassignCellComponents", library: library, device: device
        )
        divideAndReduceCellPipeline = try Self.computePipeline(
            named: "divideAndReduceOrganismCells",
            library: library,
            device: device
        )
        compactCellRenderPipeline = try Self.computePipeline(
            named: "compactVisibleCells",
            library: library,
            device: device
        )
        bloomPrefilterPipeline = try Self.computePipeline(named: "bloomPrefilter", library: library, device: device)
        bloomBlurPipeline = try Self.computePipeline(named: "blurBloom", library: library, device: device)

        guard let vertex = library.makeFunction(name: "fullscreenVertex") else {
            throw EvolutionRendererError.missingFunction("fullscreenVertex")
        }
        guard let fragment = library.makeFunction(name: "worldSurfaceFragment") else {
            throw EvolutionRendererError.missingFunction("worldSurfaceFragment")
        }
        let renderDescriptor = MTLRenderPipelineDescriptor()
        renderDescriptor.label = "Numi Automata world renderer"
        renderDescriptor.vertexFunction = vertex
        renderDescriptor.fragmentFunction = fragment
        renderDescriptor.colorAttachments[0].pixelFormat = .rg11b10Float
        renderPipeline = try device.makeRenderPipelineState(descriptor: renderDescriptor)

        guard let cellularFragment = library.makeFunction(name: "cellularSurfaceFragment") else {
            throw EvolutionRendererError.missingFunction("cellularSurfaceFragment")
        }
        let cellularSurfaceDescriptor = MTLRenderPipelineDescriptor()
        cellularSurfaceDescriptor.label = "Extracellular chemistry renderer"
        cellularSurfaceDescriptor.vertexFunction = vertex
        cellularSurfaceDescriptor.fragmentFunction = cellularFragment
        cellularSurfaceDescriptor.colorAttachments[0].pixelFormat = .rg11b10Float
        cellularSurfacePipeline = try device.makeRenderPipelineState(descriptor: cellularSurfaceDescriptor)

        guard let quantumFragment = library.makeFunction(name: "quantumSurfaceFragment") else {
            throw EvolutionRendererError.missingFunction("quantumSurfaceFragment")
        }
        let quantumRenderDescriptor = MTLRenderPipelineDescriptor()
        quantumRenderDescriptor.label = "Spinor and wave-observable renderer"
        quantumRenderDescriptor.vertexFunction = vertex
        quantumRenderDescriptor.fragmentFunction = quantumFragment
        quantumRenderDescriptor.colorAttachments[0].pixelFormat = .rg11b10Float
        quantumRenderPipeline = try device.makeRenderPipelineState(descriptor: quantumRenderDescriptor)

        guard let agentVertex = library.makeFunction(name: "agentVertex") else {
            throw EvolutionRendererError.missingFunction("agentVertex")
        }
        guard let agentFragment = library.makeFunction(name: "agentFragment") else {
            throw EvolutionRendererError.missingFunction("agentFragment")
        }
        let agentRenderDescriptor = MTLRenderPipelineDescriptor()
        agentRenderDescriptor.label = "Persistent organism renderer"
        agentRenderDescriptor.vertexFunction = agentVertex
        agentRenderDescriptor.fragmentFunction = agentFragment
        let agentAttachment = agentRenderDescriptor.colorAttachments[0]!
        agentAttachment.pixelFormat = .rg11b10Float
        agentAttachment.isBlendingEnabled = true
        agentAttachment.rgbBlendOperation = .add
        agentAttachment.alphaBlendOperation = .add
        agentAttachment.sourceRGBBlendFactor = .sourceAlpha
        agentAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        agentAttachment.sourceAlphaBlendFactor = .one
        agentAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        agentRenderPipeline = try device.makeRenderPipelineState(descriptor: agentRenderDescriptor)

        guard let cellVertex = library.makeFunction(name: "cellVertex") else {
            throw EvolutionRendererError.missingFunction("cellVertex")
        }
        guard let cellFragment = library.makeFunction(name: "cellFragment") else {
            throw EvolutionRendererError.missingFunction("cellFragment")
        }
        let cellRenderDescriptor = MTLRenderPipelineDescriptor()
        cellRenderDescriptor.label = "Persistent multicellular renderer"
        cellRenderDescriptor.vertexFunction = cellVertex
        cellRenderDescriptor.fragmentFunction = cellFragment
        let cellAttachment = cellRenderDescriptor.colorAttachments[0]!
        cellAttachment.pixelFormat = .rg11b10Float
        cellAttachment.isBlendingEnabled = true
        cellAttachment.rgbBlendOperation = .add
        cellAttachment.alphaBlendOperation = .add
        cellAttachment.sourceRGBBlendFactor = .sourceAlpha
        cellAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        cellAttachment.sourceAlphaBlendFactor = .one
        cellAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        cellRenderPipeline = try device.makeRenderPipelineState(descriptor: cellRenderDescriptor)

        guard let compositeFragment = library.makeFunction(name: "compositeFragment") else {
            throw EvolutionRendererError.missingFunction("compositeFragment")
        }
        let compositeDescriptor = MTLRenderPipelineDescriptor()
        compositeDescriptor.label = "HDR bloom and tone-mapping composite"
        compositeDescriptor.vertexFunction = vertex
        compositeDescriptor.fragmentFunction = compositeFragment
        compositeDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        compositePipeline = try device.makeRenderPipelineState(descriptor: compositeDescriptor)

        state = try Self.makeWorldTexture(device: device, label: "Living state")
        reactionState = try Self.makeWorldTexture(device: device, label: "Reaction state")
        genomeA = try Self.makeWorldTexture(device: device, label: "Genome A")
        reactionGenomeA = try Self.makeWorldTexture(device: device, label: "Reaction genome A")
        genomeB = try Self.makeWorldTexture(device: device, label: "Genome B")
        reactionGenomeB = try Self.makeWorldTexture(device: device, label: "Reaction genome B")
        ecology = try Self.makeWorldTexture(device: device, label: "Ecological chemistry")
        reactionEcology = try Self.makeWorldTexture(device: device, label: "Reaction ecological chemistry")
        genomeC = try Self.makeWorldTexture(device: device, label: "Genome C")
        reactionGenomeC = try Self.makeWorldTexture(device: device, label: "Reaction genome C")
        checkpointState = try Self.makeWorldTexture(device: device, label: "Pre-perturbation checkpoint")
        eventState = try Self.makeWorldTexture(device: device, label: "Observable biological events")
        reactionEventState = try Self.makeWorldTexture(device: device, label: "Reaction biological events")
        environmentState = try Self.makeWorldTexture(device: device, label: "Persistent geology and hazards")
        reactionEnvironmentState = try Self.makeWorldTexture(device: device, label: "Expanded geology and hazards")
        mechanicalState = try Self.makeWorldTexture(device: device, label: "Extracellular displacement and velocity")
        reactionMechanicalState = try Self.makeWorldTexture(device: device, label: "Reaction extracellular mechanics")
        quantumState = try Self.makeQuantumTexture(device: device, label: "Quantum wavefunction")
        reactionQuantumState = try Self.makeQuantumTexture(device: device, label: "Reaction quantum wavefunction")

        let agentStateLength = Self.maxAgentCount * MemoryLayout<AgentState>.stride
        guard let agentState = device.makeBuffer(length: agentStateLength, options: .storageModePrivate),
              let reactionAgentState = device.makeBuffer(length: agentStateLength, options: .storageModePrivate),
              let agentOccupancy = device.makeBuffer(
                length: Self.maxAgentCount * MemoryLayout<UInt32>.stride,
                options: .storageModePrivate
              ) else {
            throw EvolutionRendererError.resourceAllocation("persistent organism state")
        }
        agentState.label = "Persistent organisms"
        reactionAgentState.label = "Reaction organism state"
        agentOccupancy.label = "Organism occupancy"
        self.agentState = agentState
        self.reactionAgentState = reactionAgentState
        self.agentOccupancy = agentOccupancy
        let cellStateLength = Self.maxCellCount * MemoryLayout<CellState>.stride
        let cellOccupancyLength = Self.maxCellCount * MemoryLayout<UInt32>.stride
        let cellIdentityLength = Self.maxCellCount * MemoryLayout<CellIdentity>.stride
        let cellParentIDLength = Self.maxCellCount * MemoryLayout<UInt32>.stride
        let programInteractionLength = Self.maxCellCount * MemoryLayout<SIMD4<Float>>.stride
        let ownerCellHeadLength = Self.maxAgentCount * MemoryLayout<UInt32>.stride
        let ownerCellNextLength = Self.maxCellCount * MemoryLayout<UInt32>.stride
        let componentParentLength = Self.maxCellCount * MemoryLayout<UInt32>.stride
        let componentCountLength = Self.maxCellCount * MemoryLayout<UInt32>.stride
        let componentAccumulationLength = Self.maxCellCount * 5 * MemoryLayout<Int32>.stride
        let componentOwnerLength = Self.maxCellCount * MemoryLayout<UInt32>.stride
        let componentProgramLength = Self.maxCellCount * MemoryLayout<UInt32>.stride
        let componentProgramMappingLength = Self.maxCellCount * Self.maxProgramsPerPropagule *
            MemoryLayout<UInt32>.stride
        let ownerPrimaryRootLength = Self.maxAgentCount * MemoryLayout<UInt32>.stride
        let cellAggregateLength = Self.maxAgentCount * MemoryLayout<CellAggregate>.stride
        let heritableProgramLength = Self.maxHeritableProgramCount * MemoryLayout<HeritableProgram>.stride
        let developmentalGenomeLength = Self.maxHeritableProgramCount * MemoryLayout<DevelopmentalGenome>.stride
        let regulatoryNodeLength = Self.maxHeritableProgramCount * Self.regulatoryNodeCapacity *
            MemoryLayout<RegulatoryNode>.stride
        let regulatoryEdgeLength = Self.maxHeritableProgramCount * Self.regulatoryEdgeCapacity *
            MemoryLayout<RegulatoryEdge>.stride
        let regulatoryStateLength = Self.maxCellCount * Self.regulatoryNodeCapacity *
            MemoryLayout<Float>.stride
        let resonanceGenomeLength = Self.maxHeritableProgramCount * MemoryLayout<ResonanceGenome>.stride
        let membraneVertexLength = Self.maxCellCount * Self.membraneVertexCount *
            MemoryLayout<MembraneVertex>.stride
        let cellSpatialHashHeadLength = Self.cellSpatialHashBucketCount * MemoryLayout<UInt32>.stride
        let cellSpatialHashNextLength = Self.maxCellCount * MemoryLayout<UInt32>.stride
        let cellContactEffectLength = Self.maxCellCount * 4 * MemoryLayout<Int32>.stride
        let visibleCellIndexLength = Self.maxCellCount * MemoryLayout<UInt32>.stride
        let drawArgumentLength = 4 * MemoryLayout<UInt32>.stride
        let identityCounterLength = 5 * MemoryLayout<UInt32>.stride
        let lineageEventLength = Self.lineageEventCapacity * MemoryLayout<LineageEventRecord>.stride
        let mechanicalForcingLength = Self.gridSize * Self.gridSize * Self.worldCount * 2 *
            MemoryLayout<Int32>.stride
        guard let cellState = device.makeBuffer(length: cellStateLength, options: .storageModePrivate),
              let reactionCellState = device.makeBuffer(length: cellStateLength, options: .storageModePrivate),
              let cellOccupancy = device.makeBuffer(length: cellOccupancyLength, options: .storageModePrivate),
              let cellIdentities = device.makeBuffer(length: cellIdentityLength, options: .storageModePrivate),
              let cellParentIDs = device.makeBuffer(length: cellParentIDLength, options: .storageModePrivate),
              let programInteractions = device.makeBuffer(
                length: programInteractionLength, options: .storageModePrivate
              ),
              let ownerCellHeads = device.makeBuffer(length: ownerCellHeadLength, options: .storageModePrivate),
              let ownerCellNext = device.makeBuffer(length: ownerCellNextLength, options: .storageModePrivate),
              let cellComponentParents = device.makeBuffer(
                length: componentParentLength, options: .storageModePrivate
              ),
              let cellComponentCounts = device.makeBuffer(
                length: componentCountLength, options: .storageModePrivate
              ),
              let cellComponentAccumulation = device.makeBuffer(
                length: componentAccumulationLength, options: .storageModePrivate
              ),
              let cellComponentOwners = device.makeBuffer(
                length: componentOwnerLength, options: .storageModePrivate
              ),
              let cellComponentPrograms = device.makeBuffer(
                length: componentProgramLength, options: .storageModePrivate
              ),
              let cellComponentProgramSources = device.makeBuffer(
                length: componentProgramMappingLength, options: .storageModePrivate
              ),
              let cellComponentProgramTargets = device.makeBuffer(
                length: componentProgramMappingLength, options: .storageModePrivate
              ),
              let ownerPrimaryRoots = device.makeBuffer(
                length: ownerPrimaryRootLength, options: .storageModePrivate
              ),
              let cellAggregates = device.makeBuffer(length: cellAggregateLength, options: .storageModePrivate),
              let heritablePrograms = device.makeBuffer(
                length: heritableProgramLength,
                options: .storageModePrivate
              ),
              let developmentalGenomes = device.makeBuffer(
                length: developmentalGenomeLength,
                options: .storageModePrivate
              ),
              let regulatoryNodes = device.makeBuffer(length: regulatoryNodeLength, options: .storageModePrivate),
              let regulatoryEdges = device.makeBuffer(length: regulatoryEdgeLength, options: .storageModePrivate),
              let regulatoryStates = device.makeBuffer(length: regulatoryStateLength, options: .storageModePrivate),
              let resonanceGenomes = device.makeBuffer(length: resonanceGenomeLength, options: .storageModePrivate),
              let membraneVertices = device.makeBuffer(length: membraneVertexLength, options: .storageModePrivate),
              let cellSpatialHashHeads = device.makeBuffer(
                length: cellSpatialHashHeadLength, options: .storageModePrivate
              ),
              let cellSpatialHashNext = device.makeBuffer(
                length: cellSpatialHashNextLength, options: .storageModePrivate
              ),
              let cellContactEffects = device.makeBuffer(
                length: cellContactEffectLength, options: .storageModePrivate
              ),
              let visibleCellIndices = device.makeBuffer(
                length: visibleCellIndexLength,
                options: .storageModePrivate
              ),
              let cellDrawArguments = device.makeBuffer(
                length: drawArgumentLength,
                options: .storageModeShared
              ),
              let identityCounters = device.makeBuffer(length: identityCounterLength, options: .storageModePrivate),
              let lineageEvents = device.makeBuffer(length: lineageEventLength, options: .storageModePrivate),
              let mechanicalForcing = device.makeBuffer(
                length: mechanicalForcingLength,
                options: .storageModePrivate
              ) else {
            throw EvolutionRendererError.resourceAllocation("persistent multicellular state")
        }
        cellState.label = "Persistent organism cells"
        reactionCellState.label = "Reaction organism cells"
        cellOccupancy.label = "Cell occupancy"
        cellIdentities.label = "Hot cell identity and component roots"
        cellParentIDs.label = "Cold parent-cell genealogy"
        programInteractions.label = "Cold cell program interaction state"
        ownerCellHeads.label = "Dynamic organism cell-list heads"
        ownerCellNext.label = "Dynamic organism cell-list links"
        cellComponentParents.label = "Cell connectivity union-find parents"
        cellComponentCounts.label = "Connected-component cell counts"
        cellComponentAccumulation.label = "Connected-component viability accumulation"
        cellComponentOwners.label = "Connected-component owner assignments"
        cellComponentPrograms.label = "Connected-component program-map counts"
        cellComponentProgramSources.label = "Connected-component source programs"
        cellComponentProgramTargets.label = "Connected-component descendant programs"
        ownerPrimaryRoots.label = "Primary connected component per organism"
        cellAggregates.label = "Per-organism cellular aggregates"
        heritablePrograms.label = "Persistent heritable-program records"
        developmentalGenomes.label = "Evolvable developmental programs"
        regulatoryNodes.label = "Sparse developmental nodes"
        regulatoryEdges.label = "Sparse developmental edges"
        regulatoryStates.label = "Cell-local regulatory activity"
        resonanceGenomes.label = "Heritable mechanosensory resonance"
        membraneVertices.label = "Deformable cell membrane vertices"
        cellSpatialHashHeads.label = "Cross-organism cell spatial hash heads"
        cellSpatialHashNext.label = "Cross-organism cell spatial hash links"
        cellContactEffects.label = "Accumulated cell contact effects"
        visibleCellIndices.label = "GPU-compacted visible cell indices"
        cellDrawArguments.label = "Indirect living-cell draw arguments"
        let drawArguments = cellDrawArguments.contents().bindMemory(to: UInt32.self, capacity: 4)
        drawArguments[0] = UInt32(Self.membraneVertexCount * 3)
        drawArguments[1] = 0
        drawArguments[2] = 0
        drawArguments[3] = 0
        identityCounters.label = "Permanent identity and innovation counters"
        lineageEvents.label = "GPU lineage event ring"
        mechanicalForcing.label = "Cell contractile forcing"
        self.cellState = cellState
        self.reactionCellState = reactionCellState
        self.cellOccupancy = cellOccupancy
        self.cellIdentities = cellIdentities
        self.cellParentIDs = cellParentIDs
        self.programInteractions = programInteractions
        self.ownerCellHeads = ownerCellHeads
        self.ownerCellNext = ownerCellNext
        self.cellComponentParents = cellComponentParents
        self.cellComponentCounts = cellComponentCounts
        self.cellComponentAccumulation = cellComponentAccumulation
        self.cellComponentOwners = cellComponentOwners
        self.cellComponentPrograms = cellComponentPrograms
        self.cellComponentProgramSources = cellComponentProgramSources
        self.cellComponentProgramTargets = cellComponentProgramTargets
        self.ownerPrimaryRoots = ownerPrimaryRoots
        self.cellAggregates = cellAggregates
        self.heritablePrograms = heritablePrograms
        self.developmentalGenomes = developmentalGenomes
        self.regulatoryNodes = regulatoryNodes
        self.regulatoryEdges = regulatoryEdges
        self.regulatoryStates = regulatoryStates
        self.resonanceGenomes = resonanceGenomes
        self.membraneVertices = membraneVertices
        self.cellSpatialHashHeads = cellSpatialHashHeads
        self.cellSpatialHashNext = cellSpatialHashNext
        self.cellContactEffects = cellContactEffects
        self.visibleCellIndices = visibleCellIndices
        self.cellDrawArguments = cellDrawArguments
        self.identityCounters = identityCounters
        self.lineageEvents = lineageEvents
        self.mechanicalForcing = mechanicalForcing
        let observationLength = Self.maxAgentCount * MemoryLayout<AgentObservationRecord>.stride
        var observationBuffers: [MTLBuffer] = []
        var observedLineageEventBuffers: [MTLBuffer] = []
        var observedIdentityCounterBuffers: [MTLBuffer] = []
        for slot in 0..<Self.agentObservationRingSize {
            guard let observationBuffer = device.makeBuffer(
                length: observationLength,
                options: .storageModeShared
            ), let observedLineageEvents = device.makeBuffer(
                length: lineageEventLength,
                options: .storageModeShared
            ), let observedIdentityCounters = device.makeBuffer(
                length: identityCounterLength,
                options: .storageModeShared
            ) else {
                throw EvolutionRendererError.resourceAllocation("organism observation ring")
            }
            observationBuffer.label = "Compact organism observations \(slot)"
            observedLineageEvents.label = "Observed lineage events \(slot)"
            observedIdentityCounters.label = "Observed identity counters \(slot)"
            observationBuffers.append(observationBuffer)
            observedLineageEventBuffers.append(observedLineageEvents)
            observedIdentityCounterBuffers.append(observedIdentityCounters)
        }
        agentObservationBuffers = observationBuffers
        lineageEventObservationBuffers = observedLineageEventBuffers
        identityCounterObservationBuffers = observedIdentityCounterBuffers

        let metricsLength = Self.worldCount * Self.metricCount * MemoryLayout<UInt32>.stride
        let occupancyLength = Self.maxAgentCount * MemoryLayout<UInt32>.stride
        let programMetricLength = Self.maxAgentCount * MemoryLayout<ProgramMetricRecord>.stride
        var metricSlots: [MetricReadbackSlot] = []
        for slot in 0..<Self.metricReadbackRingSize {
            guard let metrics = device.makeBuffer(length: metricsLength, options: .storageModeShared),
                  let quantumNorm = device.makeBuffer(
                    length: MemoryLayout<UInt32>.stride,
                    options: .storageModeShared
                  ),
                  let observedAgents = device.makeBuffer(length: agentStateLength, options: .storageModeShared),
                  let observedOccupancy = device.makeBuffer(length: occupancyLength, options: .storageModeShared),
                  let observedCellAggregates = device.makeBuffer(
                    length: cellAggregateLength,
                    options: .storageModeShared
                  ),
                  let observedProgramRecords = device.makeBuffer(
                    length: programMetricLength,
                    options: .storageModeShared
                  ),
                  let observedMetricIdentityCounters = device.makeBuffer(
                    length: identityCounterLength,
                    options: .storageModeShared
                  ) else {
                throw EvolutionRendererError.resourceAllocation("the metric readback ring")
            }
            metrics.label = "Adaptive complexity metrics \(slot)"
            quantumNorm.label = "Conserved quantum norm \(slot)"
            observedAgents.label = "Metric organism state \(slot)"
            observedOccupancy.label = "Metric organism occupancy \(slot)"
            observedCellAggregates.label = "Metric cellular aggregates \(slot)"
            observedProgramRecords.label = "Compact metric program records \(slot)"
            observedMetricIdentityCounters.label = "Metric identity counters \(slot)"
            metricSlots.append(MetricReadbackSlot(
                metrics: metrics,
                quantumNorm: quantumNorm,
                agentState: observedAgents,
                agentOccupancy: observedOccupancy,
                cellAggregates: observedCellAggregates,
                programRecords: observedProgramRecords,
                identityCounters: observedMetricIdentityCounters
            ))
        }
        metricReadbackSlots = metricSlots

        super.init()
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.clearColor = MTLClearColorMake(0.004, 0.008, 0.010, 1)
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        try initializeSimulation()
    }

    func update(settings: RendererSettings) {
        stateLock.lock()
        self.settings = settings
        stateLock.unlock()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportAspect = size.height > 0 ? Float(size.width / size.height) : 1
    }

    func draw(in view: MTKView) {
        let frameSettings: RendererSettings
        stateLock.lock()
        frameSettings = settings
        stateLock.unlock()
        frameSerial &+= 1

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Numi Automata frame"

        if frameSettings.resetToken != appliedResetToken {
            totalSteps = 0
            quantumStep = 0
            generation = 0
            evaluator = AdaptiveComplexityEvaluator(seed: 0xA170_6E51 ^ frameSettings.resetToken, eliteCount: 1)
            lineageEventDeliveryState.reset()
            encodeInitialization(into: commandBuffer, settings: frameSettings)
            appliedResetToken = frameSettings.resetToken
            appliedExpansionToken = frameSettings.expansionToken
        }

        while appliedExpansionToken < frameSettings.expansionToken {
            encodeWorldExpansion(
                into: commandBuffer,
                settings: frameSettings,
                level: UInt32(truncatingIfNeeded: appliedExpansionToken + 1)
            )
            appliedExpansionToken &+= 1
        }

        if frameSettings.addColonyToken != appliedAddColonyToken {
            encodeBrush(
                BrushEvent(position: frameSettings.addColonyPosition),
                into: commandBuffer,
                settings: frameSettings
            )
            appliedAddColonyToken = frameSettings.addColonyToken
        }

        var pendingMetricObservation: PendingMetricObservation?
        if frameSettings.isRunning {
            for _ in 0..<max(frameSettings.stepsPerFrame, 1) {
                encodeSimulationStep(into: commandBuffer, settings: frameSettings)
                totalSteps &+= 1
                let epochPosition = Int(totalSteps % UInt64(Self.epochSteps))
                if epochPosition == Self.damageStep {
                    encodeCheckpointAndDamage(
                        into: commandBuffer,
                        settings: frameSettings,
                        applyDamage: generation >= 8 && generation.isMultiple(of: 8)
                    )
                } else if epochPosition == 0 {
                    let slotIndex = Int(generation % UInt32(Self.metricReadbackRingSize))
                    if !metricSlotsInFlight[slotIndex] {
                        metricSlotsInFlight[slotIndex] = true
                        let slot = metricReadbackSlots[slotIndex]
                        encodeMeasurements(into: commandBuffer, settings: frameSettings, slot: slot)
                        generation &+= 1
                        pendingMetricObservation = PendingMetricObservation(
                            slotIndex: slotIndex,
                            generation: generation,
                            totalSteps: totalSteps,
                            settings: frameSettings,
                            resetToken: appliedResetToken
                        )
                    }
                    break
                }
            }
            encodeQuantumStep(into: commandBuffer, settings: frameSettings)
            if let pendingMetricObservation {
                encodeQuantumMeasurement(
                    into: commandBuffer,
                    slot: metricReadbackSlots[pendingMetricObservation.slotIndex]
                )
            }
        }

        encodeRender(view: view, into: commandBuffer, settings: frameSettings)
        if let pendingMetricObservation {
            attachMetricObservation(pendingMetricObservation, to: commandBuffer)
        }
        attachGPUTiming(to: commandBuffer)
        commandBuffer.commit()
    }

    private func attachMetricObservation(
        _ pending: PendingMetricObservation,
        to commandBuffer: MTLCommandBuffer
    ) {
        commandBuffer.addCompletedHandler { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.completeMetricObservation(pending)
            }
        }
    }

    private func completeMetricObservation(_ pending: PendingMetricObservation) {
        metricSlotsInFlight[pending.slotIndex] = false
        guard pending.resetToken == appliedResetToken else { return }
        observeWorld(
            slot: metricReadbackSlots[pending.slotIndex],
            settings: pending.settings,
            completedGeneration: pending.generation,
            completedSteps: pending.totalSteps
        )
    }

    private func attachGPUTiming(to commandBuffer: MTLCommandBuffer) {
        guard Self.gpuTimingEnabled else { return }
        commandBuffer.addCompletedHandler { buffer in
            let milliseconds = max(buffer.gpuEndTime - buffer.gpuStartTime, 0) * 1_000
            let formattedMilliseconds = String(format: "%.4f", milliseconds)
            let label = buffer.label ?? "unlabeled"
            print("gpu_frame_ms=\(formattedMilliseconds) label=\(label)")
        }
    }

    private func initializeSimulation() throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw EvolutionRendererError.resourceAllocation("the initialization command buffer")
        }
        encodeInitialization(into: commandBuffer, settings: settings)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        appliedResetToken = settings.resetToken
    }

    private func encodeInitialization(into commandBuffer: MTLCommandBuffer, settings: RendererSettings) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Initialize prebiotic chemistry"
        var uniforms = makeUniforms(settings: settings)
        encoder.setComputePipelineState(initializePipeline)
        encoder.setTexture(state, index: 0)
        encoder.setTexture(genomeA, index: 1)
        encoder.setTexture(genomeB, index: 2)
        encoder.setTexture(ecology, index: 3)
        encoder.setTexture(genomeC, index: 4)
        encoder.setTexture(eventState, index: 5)
        encoder.setTexture(environmentState, index: 6)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
        dispatchWorlds(encoder, pipeline: initializePipeline)
        encoder.setComputePipelineState(initializeMechanicalPipeline)
        encoder.setTexture(mechanicalState, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
        dispatchWorlds(encoder, pipeline: initializeMechanicalPipeline)
        encoder.endEncoding()
        if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.label = "Initialize mechanical forcing"
            blitEncoder.fill(
                buffer: mechanicalForcing,
                range: 0..<mechanicalForcing.length,
                value: 0
            )
            blitEncoder.endEncoding()
        }
        encodeAgentInitialization(into: commandBuffer, settings: settings)
        encodeQuantumInitialization(into: commandBuffer, settings: settings)
        copyAllSlices(from: state, to: checkpointState, commandBuffer: commandBuffer)
    }

    private func encodeAgentInitialization(
        into commandBuffer: MTLCommandBuffer,
        settings: RendererSettings
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Prepare empty organism substrate"
        var uniforms = makeUniforms(settings: settings)
        encoder.setComputePipelineState(initializeAgentPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 2)
        encoder.setBuffer(cellState, offset: 0, index: 3)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 4)
        encoder.setBuffer(cellAggregates, offset: 0, index: 5)
        encoder.setBuffer(developmentalGenomes, offset: 0, index: 6)
        encoder.setBuffer(regulatoryNodes, offset: 0, index: 7)
        encoder.setBuffer(regulatoryEdges, offset: 0, index: 8)
        encoder.setBuffer(regulatoryStates, offset: 0, index: 9)
        encoder.setBuffer(resonanceGenomes, offset: 0, index: 10)
        encoder.setBuffer(membraneVertices, offset: 0, index: 11)
        encoder.setBuffer(identityCounters, offset: 0, index: 12)
        encoder.setBuffer(lineageEvents, offset: 0, index: 13)
        encoder.setBuffer(cellIdentities, offset: 0, index: 14)
        encoder.setBuffer(ownerCellHeads, offset: 0, index: 15)
        encoder.setBuffer(ownerCellNext, offset: 0, index: 16)
        encoder.setBuffer(cellComponentParents, offset: 0, index: 17)
        encoder.setBuffer(cellComponentCounts, offset: 0, index: 18)
        encoder.setBuffer(cellComponentAccumulation, offset: 0, index: 19)
        encoder.setBuffer(cellComponentOwners, offset: 0, index: 20)
        encoder.setBuffer(ownerPrimaryRoots, offset: 0, index: 21)
        encoder.setBuffer(heritablePrograms, offset: 0, index: 22)
        encoder.setBuffer(cellComponentPrograms, offset: 0, index: 23)
        encoder.setBuffer(cellParentIDs, offset: 0, index: 24)
        encoder.setBuffer(programInteractions, offset: 0, index: 25)
        dispatchAgents(encoder, pipeline: initializeAgentPipeline)
        encoder.endEncoding()
    }

    private func encodeFounderInjection(
        into commandBuffer: MTLCommandBuffer,
        settings: RendererSettings,
        position: SIMD2<Float>
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Introduce user-requested founder"
        var uniforms = makeUniforms(settings: settings, brushPosition: position)
        encoder.setComputePipelineState(injectFounderPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 2)
        encoder.setBuffer(cellState, offset: 0, index: 3)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 4)
        encoder.setBuffer(cellAggregates, offset: 0, index: 5)
        encoder.setBuffer(developmentalGenomes, offset: 0, index: 6)
        encoder.setBuffer(regulatoryNodes, offset: 0, index: 7)
        encoder.setBuffer(regulatoryEdges, offset: 0, index: 8)
        encoder.setBuffer(regulatoryStates, offset: 0, index: 9)
        encoder.setBuffer(resonanceGenomes, offset: 0, index: 10)
        encoder.setBuffer(identityCounters, offset: 0, index: 11)
        encoder.setBuffer(lineageEvents, offset: 0, index: 12)
        encoder.setBuffer(membraneVertices, offset: 0, index: 13)
        encoder.setBuffer(cellIdentities, offset: 0, index: 14)
        encoder.setBuffer(heritablePrograms, offset: 0, index: 15)
        encoder.setBuffer(cellParentIDs, offset: 0, index: 16)
        encoder.setBuffer(programInteractions, offset: 0, index: 17)
        encoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
        encoder.endEncoding()
    }

    private func encodeQuantumInitialization(
        into commandBuffer: MTLCommandBuffer,
        settings: RendererSettings
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Seed conserved quantum wavefunction"
        var uniforms = makeUniforms(settings: settings)
        encoder.setComputePipelineState(initializeQuantumPipeline)
        encoder.setTexture(quantumState, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
        dispatchQuantum(encoder, pipeline: initializeQuantumPipeline)
        encoder.endEncoding()
    }

    private func encodeWorldExpansion(
        into commandBuffer: MTLCommandBuffer,
        settings: RendererSettings,
        level: UInt32
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Expand colonizable world"
        var uniforms = makeUniforms(settings: settings)
        var expansionLevel = level
        encoder.setComputePipelineState(expandWorldPipeline)
        encoder.setTexture(state, index: 0)
        encoder.setTexture(genomeA, index: 1)
        encoder.setTexture(genomeB, index: 2)
        encoder.setTexture(ecology, index: 3)
        encoder.setTexture(genomeC, index: 4)
        encoder.setTexture(eventState, index: 5)
        encoder.setTexture(reactionState, index: 6)
        encoder.setTexture(reactionGenomeA, index: 7)
        encoder.setTexture(reactionGenomeB, index: 8)
        encoder.setTexture(reactionEcology, index: 9)
        encoder.setTexture(reactionGenomeC, index: 10)
        encoder.setTexture(reactionEventState, index: 11)
        encoder.setTexture(environmentState, index: 12)
        encoder.setTexture(reactionEnvironmentState, index: 13)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
        encoder.setBytes(&expansionLevel, length: MemoryLayout<UInt32>.stride, index: 1)
        dispatchWorlds(encoder, pipeline: expandWorldPipeline)
        encoder.endEncoding()
        swapWorldReactionState()
        swap(&environmentState, &reactionEnvironmentState)

        guard let mechanicalEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
        mechanicalEncoder.label = "Expand extracellular mechanical medium"
        mechanicalEncoder.setComputePipelineState(expandMechanicalPipeline)
        mechanicalEncoder.setTexture(mechanicalState, index: 0)
        mechanicalEncoder.setTexture(reactionMechanicalState, index: 1)
        mechanicalEncoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
        dispatchWorlds(mechanicalEncoder, pipeline: expandMechanicalPipeline)
        mechanicalEncoder.endEncoding()
        swap(&mechanicalState, &reactionMechanicalState)

        guard let quantumEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
        quantumEncoder.label = "Expand quantum field with world"
        quantumEncoder.setComputePipelineState(expandQuantumPipeline)
        quantumEncoder.setTexture(quantumState, index: 0)
        quantumEncoder.setTexture(reactionQuantumState, index: 1)
        dispatchQuantum(quantumEncoder, pipeline: expandQuantumPipeline)
        quantumEncoder.endEncoding()
        swap(&quantumState, &reactionQuantumState)
        encodeAgentExpansion(into: commandBuffer)
        copyAllSlices(from: state, to: checkpointState, commandBuffer: commandBuffer)
    }

    private func encodeAgentExpansion(into commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Keep organisms fixed in the expanding world"
        encoder.setComputePipelineState(expandAgentPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        dispatchAgents(encoder, pipeline: expandAgentPipeline)
        encoder.endEncoding()
    }

    private func encodeSimulationStep(into commandBuffer: MTLCommandBuffer, settings: RendererSettings) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Autogenic chemistry step"
        var uniforms = makeUniforms(settings: settings)

        encoder.setComputePipelineState(reactionPipeline)
        encoder.setTexture(state, index: 0)
        encoder.setTexture(genomeA, index: 1)
        encoder.setTexture(genomeB, index: 2)
        encoder.setTexture(ecology, index: 3)
        encoder.setTexture(genomeC, index: 4)
        encoder.setTexture(reactionState, index: 5)
        encoder.setTexture(reactionGenomeA, index: 6)
        encoder.setTexture(reactionGenomeB, index: 7)
        encoder.setTexture(reactionEcology, index: 8)
        encoder.setTexture(reactionGenomeC, index: 9)
        encoder.setTexture(eventState, index: 10)
        encoder.setTexture(reactionEventState, index: 11)
        encoder.setTexture(environmentState, index: 12)
        encoder.setTexture(quantumState, index: 13)
        encoder.setTexture(mechanicalState, index: 14)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
        dispatchWorlds(encoder, pipeline: reactionPipeline)
        encoder.endEncoding()
        swapWorldReactionState()
        encodeAgentStep(into: commandBuffer, settings: settings)
    }

    private func encodeAgentStep(into commandBuffer: MTLCommandBuffer, settings: RendererSettings) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Autogenic nucleation and cell-derived organism motion"
        var uniforms = makeUniforms(settings: settings)

        encoder.setComputePipelineState(nucleateFounderPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 2)
        encoder.setBuffer(cellState, offset: 0, index: 3)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 4)
        encoder.setBuffer(cellAggregates, offset: 0, index: 5)
        encoder.setBuffer(developmentalGenomes, offset: 0, index: 6)
        encoder.setBuffer(regulatoryNodes, offset: 0, index: 7)
        encoder.setBuffer(regulatoryEdges, offset: 0, index: 8)
        encoder.setBuffer(regulatoryStates, offset: 0, index: 9)
        encoder.setBuffer(resonanceGenomes, offset: 0, index: 10)
        encoder.setBuffer(identityCounters, offset: 0, index: 11)
        encoder.setBuffer(lineageEvents, offset: 0, index: 12)
        encoder.setBuffer(membraneVertices, offset: 0, index: 13)
        encoder.setBuffer(cellIdentities, offset: 0, index: 14)
        encoder.setBuffer(heritablePrograms, offset: 0, index: 15)
        encoder.setBuffer(cellParentIDs, offset: 0, index: 16)
        encoder.setBuffer(programInteractions, offset: 0, index: 17)
        encoder.setTexture(state, index: 0)
        encoder.setTexture(genomeA, index: 1)
        encoder.setTexture(genomeB, index: 2)
        encoder.setTexture(genomeC, index: 3)
        encoder.setTexture(ecology, index: 4)
        dispatch2D(encoder, pipeline: nucleateFounderPipeline)
        encoder.memoryBarrier(resources: [
            agentState, agentOccupancy, cellState, cellOccupancy, cellAggregates,
            developmentalGenomes, regulatoryNodes, regulatoryEdges, regulatoryStates,
            resonanceGenomes, identityCounters, lineageEvents, membraneVertices,
            cellIdentities, heritablePrograms
        ])

        encoder.setComputePipelineState(evolveAgentPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(reactionAgentState, offset: 0, index: 1)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 2)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 3)
        encoder.setBuffer(cellAggregates, offset: 0, index: 4)
        encoder.setBuffer(developmentalGenomes, offset: 0, index: 5)
        encoder.setBuffer(resonanceGenomes, offset: 0, index: 6)
        encoder.setBuffer(lineageEvents, offset: 0, index: 7)
        encoder.setBuffer(identityCounters, offset: 0, index: 8)
        encoder.setTexture(state, index: 0)
        encoder.setTexture(ecology, index: 1)
        encoder.setTexture(environmentState, index: 2)
        encoder.setTexture(mechanicalState, index: 3)
        dispatchAgents(encoder, pipeline: evolveAgentPipeline)
        encoder.memoryBarrier(resources: [reactionAgentState, agentOccupancy, lineageEvents, identityCounters])
        swap(&agentState, &reactionAgentState)
        encoder.endEncoding()
        encodeCellStep(into: commandBuffer, settings: settings)
    }

    private func encodeCellStep(into commandBuffer: MTLCommandBuffer, settings: RendererSettings) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Cell energetics, electrophysiology, oscillators, and mechanical waves"
        var uniforms = makeUniforms(settings: settings)
        encoder.setComputePipelineState(evolveCellPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBuffer(cellState, offset: 0, index: 2)
        encoder.setBuffer(reactionCellState, offset: 0, index: 3)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 4)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 5)
        encoder.setBuffer(mechanicalForcing, offset: 0, index: 6)
        encoder.setBuffer(developmentalGenomes, offset: 0, index: 7)
        encoder.setBuffer(regulatoryNodes, offset: 0, index: 8)
        encoder.setBuffer(regulatoryEdges, offset: 0, index: 9)
        encoder.setBuffer(regulatoryStates, offset: 0, index: 10)
        encoder.setBuffer(resonanceGenomes, offset: 0, index: 11)
        encoder.setBuffer(cellIdentities, offset: 0, index: 12)
        encoder.setBuffer(ownerCellHeads, offset: 0, index: 13)
        encoder.setBuffer(ownerCellNext, offset: 0, index: 14)
        encoder.setBuffer(heritablePrograms, offset: 0, index: 15)
        encoder.setBuffer(programInteractions, offset: 0, index: 16)
        encoder.setBuffer(cellAggregates, offset: 0, index: 17)
        encoder.setTexture(state, index: 0)
        encoder.setTexture(ecology, index: 1)
        encoder.setTexture(environmentState, index: 2)
        encoder.setTexture(eventState, index: 3)
        encoder.setTexture(mechanicalState, index: 4)
        dispatchCells(encoder, pipeline: evolveCellPipeline)
        encoder.memoryBarrier(resources: [reactionCellState, cellOccupancy, mechanicalForcing])
        swap(&cellState, &reactionCellState)

        encoder.setComputePipelineState(evolveMembranePipeline)
        encoder.setBuffer(cellState, offset: 0, index: 0)
        encoder.setBuffer(reactionCellState, offset: 0, index: 1)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 2)
        encoder.setBuffer(membraneVertices, offset: 0, index: 3)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 4)
        encoder.setBuffer(cellIdentities, offset: 0, index: 5)
        encoder.setBuffer(ownerCellHeads, offset: 0, index: 6)
        encoder.setBuffer(ownerCellNext, offset: 0, index: 7)
        dispatchCells(encoder, pipeline: evolveMembranePipeline)
        encoder.memoryBarrier(resources: [reactionCellState, membraneVertices])
        swap(&cellState, &reactionCellState)

        encodeCellNeighborhoodIndex(encoder, uniforms: &uniforms)

        encoder.setComputePipelineState(resolveCellContactsPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBuffer(cellState, offset: 0, index: 2)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 3)
        encoder.setBuffer(membraneVertices, offset: 0, index: 4)
        encoder.setBuffer(cellSpatialHashHeads, offset: 0, index: 5)
        encoder.setBuffer(cellSpatialHashNext, offset: 0, index: 6)
        encoder.setBuffer(cellContactEffects, offset: 0, index: 7)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 8)
        encoder.setBuffer(cellIdentities, offset: 0, index: 9)
        encoder.setBuffer(heritablePrograms, offset: 0, index: 10)
        dispatchCells(encoder, pipeline: resolveCellContactsPipeline)
        encoder.memoryBarrier(resources: [cellContactEffects])

        encoder.setComputePipelineState(applyCellContactEffectsPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(cellState, offset: 0, index: 1)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 2)
        encoder.setBuffer(membraneVertices, offset: 0, index: 3)
        encoder.setBuffer(cellContactEffects, offset: 0, index: 4)
        encoder.setBuffer(cellIdentities, offset: 0, index: 5)
        dispatchCells(encoder, pipeline: applyCellContactEffectsPipeline)
        encoder.memoryBarrier(resources: [cellState, membraneVertices])

        encodeCellConnectivity(encoder, uniforms: &uniforms)
        encodeOwnerCellLists(encoder)

        encoder.setComputePipelineState(divideAndReduceCellPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBuffer(cellState, offset: 0, index: 2)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 3)
        encoder.setBuffer(cellAggregates, offset: 0, index: 4)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 5)
        encoder.setBuffer(regulatoryStates, offset: 0, index: 6)
        encoder.setBuffer(membraneVertices, offset: 0, index: 7)
        encoder.setBuffer(resonanceGenomes, offset: 0, index: 8)
        encoder.setBuffer(cellIdentities, offset: 0, index: 9)
        encoder.setBuffer(ownerCellHeads, offset: 0, index: 10)
        encoder.setBuffer(ownerCellNext, offset: 0, index: 11)
        encoder.setBuffer(identityCounters, offset: 0, index: 12)
        encoder.setBuffer(cellParentIDs, offset: 0, index: 13)
        encoder.setBuffer(programInteractions, offset: 0, index: 14)
        dispatchAgents(encoder, pipeline: divideAndReduceCellPipeline)
        encoder.memoryBarrier(resources: [
            agentState, cellState, cellOccupancy, cellIdentities, cellAggregates,
            ownerCellHeads, ownerCellNext, regulatoryStates, membraneVertices,
            identityCounters, programInteractions
        ])

        encoder.setComputePipelineState(evolveMechanicalPipeline)
        encoder.setTexture(mechanicalState, index: 0)
        encoder.setTexture(reactionMechanicalState, index: 1)
        encoder.setTexture(environmentState, index: 2)
        encoder.setBuffer(mechanicalForcing, offset: 0, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 1)
        dispatchWorlds(encoder, pipeline: evolveMechanicalPipeline)
        encoder.endEncoding()
        swap(&mechanicalState, &reactionMechanicalState)
    }

    private func encodeCellNeighborhoodIndex(
        _ encoder: MTLComputeCommandEncoder,
        uniforms: inout SimulationUniforms
    ) {
        encoder.setComputePipelineState(clearCellSpatialHashPipeline)
        encoder.setBuffer(cellSpatialHashHeads, offset: 0, index: 0)
        encoder.setBuffer(cellContactEffects, offset: 0, index: 1)
        encoder.setBuffer(ownerCellHeads, offset: 0, index: 2)
        encoder.dispatchThreads(
            MTLSize(
                width: max(Self.cellSpatialHashBucketCount, Self.maxCellCount * 4),
                height: 1,
                depth: 1
            ),
            threadsPerThreadgroup: MTLSize(
                width: min(clearCellSpatialHashPipeline.maxTotalThreadsPerThreadgroup, 256),
                height: 1,
                depth: 1
            )
        )
        encoder.memoryBarrier(resources: [cellSpatialHashHeads, cellContactEffects, ownerCellHeads])

        encoder.setComputePipelineState(buildCellSpatialHashPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBuffer(cellState, offset: 0, index: 2)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 3)
        encoder.setBuffer(cellSpatialHashHeads, offset: 0, index: 4)
        encoder.setBuffer(cellSpatialHashNext, offset: 0, index: 5)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 6)
        encoder.setBuffer(cellIdentities, offset: 0, index: 7)
        encoder.setBuffer(ownerCellHeads, offset: 0, index: 8)
        encoder.setBuffer(ownerCellNext, offset: 0, index: 9)
        dispatchCells(encoder, pipeline: buildCellSpatialHashPipeline)
        encoder.memoryBarrier(resources: [
            cellSpatialHashHeads, cellSpatialHashNext, ownerCellHeads, ownerCellNext
        ])
    }

    private func encodeCellConnectivity(
        _ encoder: MTLComputeCommandEncoder,
        uniforms: inout SimulationUniforms
    ) {
        encoder.setComputePipelineState(initializeCellComponentsPipeline)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 0)
        encoder.setBuffer(cellIdentities, offset: 0, index: 1)
        encoder.setBuffer(cellComponentParents, offset: 0, index: 2)
        encoder.setBuffer(cellComponentCounts, offset: 0, index: 3)
        encoder.setBuffer(cellComponentAccumulation, offset: 0, index: 4)
        encoder.setBuffer(cellComponentOwners, offset: 0, index: 5)
        encoder.setBuffer(ownerPrimaryRoots, offset: 0, index: 6)
        encoder.setBuffer(cellComponentPrograms, offset: 0, index: 7)
        dispatchCells(encoder, pipeline: initializeCellComponentsPipeline)
        encoder.memoryBarrier(resources: [
            cellIdentities, cellComponentParents, cellComponentCounts,
            cellComponentAccumulation, cellComponentOwners, cellComponentPrograms,
            ownerPrimaryRoots
        ])

        encoder.setComputePipelineState(unionCellComponentsPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBuffer(cellState, offset: 0, index: 2)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 3)
        encoder.setBuffer(membraneVertices, offset: 0, index: 4)
        encoder.setBuffer(cellIdentities, offset: 0, index: 5)
        encoder.setBuffer(cellSpatialHashHeads, offset: 0, index: 6)
        encoder.setBuffer(cellSpatialHashNext, offset: 0, index: 7)
        encoder.setBuffer(cellComponentParents, offset: 0, index: 8)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 9)
        encoder.setBuffer(heritablePrograms, offset: 0, index: 10)
        dispatchCells(encoder, pipeline: unionCellComponentsPipeline)
        encoder.memoryBarrier(resources: [cellComponentParents])

        encoder.setComputePipelineState(compressCellComponentsPipeline)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 0)
        encoder.setBuffer(cellComponentParents, offset: 0, index: 1)
        encoder.setBuffer(cellIdentities, offset: 0, index: 2)
        dispatchCells(encoder, pipeline: compressCellComponentsPipeline)
        encoder.memoryBarrier(resources: [cellComponentParents, cellIdentities])

        encoder.setComputePipelineState(accumulateCellComponentsPipeline)
        encoder.setBuffer(cellState, offset: 0, index: 0)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 1)
        encoder.setBuffer(cellIdentities, offset: 0, index: 2)
        encoder.setBuffer(cellComponentCounts, offset: 0, index: 3)
        encoder.setBuffer(cellComponentAccumulation, offset: 0, index: 4)
        encoder.setBuffer(cellComponentOwners, offset: 0, index: 5)
        dispatchCells(encoder, pipeline: accumulateCellComponentsPipeline)
        encoder.memoryBarrier(resources: [
            cellComponentCounts, cellComponentAccumulation, cellComponentOwners
        ])

        encoder.setComputePipelineState(selectPrimaryCellComponentsPipeline)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 0)
        encoder.setBuffer(ownerCellHeads, offset: 0, index: 1)
        encoder.setBuffer(ownerCellNext, offset: 0, index: 2)
        encoder.setBuffer(cellIdentities, offset: 0, index: 3)
        encoder.setBuffer(cellComponentCounts, offset: 0, index: 4)
        encoder.setBuffer(ownerPrimaryRoots, offset: 0, index: 5)
        dispatchAgents(encoder, pipeline: selectPrimaryCellComponentsPipeline)
        encoder.memoryBarrier(resources: [ownerPrimaryRoots])

        encoder.setComputePipelineState(assignCellComponentOwnersPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 2)
        encoder.setBuffer(cellIdentities, offset: 0, index: 3)
        encoder.setBuffer(cellComponentCounts, offset: 0, index: 4)
        encoder.setBuffer(cellComponentAccumulation, offset: 0, index: 5)
        encoder.setBuffer(cellComponentOwners, offset: 0, index: 6)
        encoder.setBuffer(ownerPrimaryRoots, offset: 0, index: 7)
        encoder.setBuffer(cellAggregates, offset: 0, index: 8)
        encoder.setBuffer(developmentalGenomes, offset: 0, index: 9)
        encoder.setBuffer(regulatoryNodes, offset: 0, index: 10)
        encoder.setBuffer(regulatoryEdges, offset: 0, index: 11)
        encoder.setBuffer(resonanceGenomes, offset: 0, index: 12)
        encoder.setBuffer(identityCounters, offset: 0, index: 13)
        encoder.setBuffer(lineageEvents, offset: 0, index: 14)
        encoder.setBuffer(cellComponentPrograms, offset: 0, index: 15)
        encoder.setBuffer(heritablePrograms, offset: 0, index: 16)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 17)
        encoder.setBuffer(cellComponentProgramSources, offset: 0, index: 18)
        encoder.setBuffer(cellComponentProgramTargets, offset: 0, index: 19)
        dispatchCells(encoder, pipeline: assignCellComponentOwnersPipeline)
        encoder.memoryBarrier(resources: [
            agentState, agentOccupancy, cellComponentOwners, cellAggregates,
            developmentalGenomes, regulatoryNodes, regulatoryEdges,
            resonanceGenomes, identityCounters, lineageEvents,
            cellComponentPrograms, cellComponentProgramSources,
            cellComponentProgramTargets, heritablePrograms
        ])

        encoder.setComputePipelineState(reassignCellComponentsPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(cellState, offset: 0, index: 1)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 2)
        encoder.setBuffer(cellIdentities, offset: 0, index: 3)
        encoder.setBuffer(cellComponentOwners, offset: 0, index: 4)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 5)
        encoder.setBuffer(ownerPrimaryRoots, offset: 0, index: 6)
        encoder.setBuffer(cellComponentPrograms, offset: 0, index: 7)
        encoder.setBuffer(cellComponentProgramSources, offset: 0, index: 8)
        encoder.setBuffer(cellComponentProgramTargets, offset: 0, index: 9)
        dispatchCells(encoder, pipeline: reassignCellComponentsPipeline)
        encoder.memoryBarrier(resources: [cellState, cellOccupancy, cellIdentities])
    }

    private func encodeOwnerCellLists(_ encoder: MTLComputeCommandEncoder) {
        encoder.setComputePipelineState(clearOwnerCellListsPipeline)
        encoder.setBuffer(ownerCellHeads, offset: 0, index: 0)
        dispatchAgents(encoder, pipeline: clearOwnerCellListsPipeline)
        encoder.memoryBarrier(resources: [ownerCellHeads])

        encoder.setComputePipelineState(buildOwnerCellListsPipeline)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 0)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 1)
        encoder.setBuffer(cellIdentities, offset: 0, index: 2)
        encoder.setBuffer(ownerCellHeads, offset: 0, index: 3)
        encoder.setBuffer(ownerCellNext, offset: 0, index: 4)
        dispatchCells(encoder, pipeline: buildOwnerCellListsPipeline)
        encoder.memoryBarrier(resources: [ownerCellHeads, ownerCellNext])
    }

    private func encodeQuantumStep(into commandBuffer: MTLCommandBuffer, settings: RendererSettings) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Unitary 2D quantum walk"
        var uniforms = makeUniforms(settings: settings)
        encoder.setComputePipelineState(quantumPipeline)
        encoder.setTexture(quantumState, index: 0)
        encoder.setTexture(state, index: 1)
        encoder.setTexture(genomeA, index: 2)
        encoder.setTexture(ecology, index: 3)
        encoder.setTexture(reactionQuantumState, index: 4)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
        var step = quantumStep
        encoder.setBytes(&step, length: MemoryLayout<UInt32>.stride, index: 1)
        dispatchQuantum(encoder, pipeline: quantumPipeline)
        encoder.endEncoding()

        swap(&quantumState, &reactionQuantumState)
        quantumStep &+= 1
    }

    private func encodeQuantumMeasurement(into commandBuffer: MTLCommandBuffer, slot: MetricReadbackSlot) {
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.label = "Reset quantum norm reduction"
            blit.fill(buffer: slot.quantumNorm, range: 0..<slot.quantumNorm.length, value: 0)
            blit.endEncoding()
        }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Measure conserved probability"
        encoder.setComputePipelineState(quantumMeasurementPipeline)
        encoder.setTexture(quantumState, index: 0)
        encoder.setBuffer(slot.quantumNorm, offset: 0, index: 0)
        dispatchQuantum(encoder, pipeline: quantumMeasurementPipeline)
        encoder.endEncoding()
    }

    private func encodeCheckpointAndDamage(
        into commandBuffer: MTLCommandBuffer,
        settings: RendererSettings,
        applyDamage: Bool
    ) {
        copyAllSlices(from: state, to: checkpointState, commandBuffer: commandBuffer)
        guard applyDamage else { return }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Counterfactual damage trial"
        var uniforms = makeUniforms(settings: settings)
        encoder.setComputePipelineState(damagePipeline)
        encoder.setTexture(state, index: 0)
        encoder.setTexture(ecology, index: 1)
        encoder.setTexture(eventState, index: 2)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
        dispatchWorlds(encoder, pipeline: damagePipeline)
        encoder.endEncoding()
    }

    private func encodeMeasurements(
        into commandBuffer: MTLCommandBuffer,
        settings: RendererSettings,
        slot: MetricReadbackSlot
    ) {
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.label = "Reset metric reductions"
            blit.fill(buffer: slot.metrics, range: 0..<slot.metrics.length, value: 0)
            blit.endEncoding()
        }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Adaptive complexity measurement"
        var uniforms = makeUniforms(settings: settings)
        encoder.setComputePipelineState(measurementPipeline)
        encoder.setTexture(state, index: 0)
        encoder.setTexture(checkpointState, index: 1)
        encoder.setTexture(genomeA, index: 2)
        encoder.setTexture(ecology, index: 3)
        encoder.setTexture(genomeB, index: 4)
        encoder.setTexture(genomeC, index: 5)
        encoder.setBuffer(slot.metrics, offset: 0, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 1)
        dispatchWorlds(encoder, pipeline: measurementPipeline)

        encoder.setComputePipelineState(collectProgramMetricPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBuffer(developmentalGenomes, offset: 0, index: 2)
        encoder.setBuffer(resonanceGenomes, offset: 0, index: 3)
        encoder.setBuffer(slot.programRecords, offset: 0, index: 4)
        dispatchAgents(encoder, pipeline: collectProgramMetricPipeline)
        encoder.endEncoding()

        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.label = "Snapshot organisms for adaptive metrics"
            blit.copy(
                from: agentState,
                sourceOffset: 0,
                to: slot.agentState,
                destinationOffset: 0,
                size: slot.agentState.length
            )
            blit.copy(
                from: agentOccupancy,
                sourceOffset: 0,
                to: slot.agentOccupancy,
                destinationOffset: 0,
                size: slot.agentOccupancy.length
            )
            blit.copy(
                from: cellAggregates,
                sourceOffset: 0,
                to: slot.cellAggregates,
                destinationOffset: 0,
                size: slot.cellAggregates.length
            )
            blit.copy(
                from: identityCounters,
                sourceOffset: 0,
                to: slot.identityCounters,
                destinationOffset: 0,
                size: slot.identityCounters.length
            )
            blit.endEncoding()
        }
    }

    private func encodeBrush(_ brush: BrushEvent, into commandBuffer: MTLCommandBuffer, settings: RendererSettings) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Laboratory intervention"
        var uniforms = makeUniforms(
            settings: settings,
            brushPosition: brush.position,
            brushRadius: 0.014,
            brushStrength: 1
        )
        encoder.setComputePipelineState(brushPipeline)
        encoder.setTexture(state, index: 0)
        encoder.setTexture(genomeA, index: 1)
        encoder.setTexture(genomeB, index: 2)
        encoder.setTexture(ecology, index: 3)
        encoder.setTexture(genomeC, index: 4)
        encoder.setTexture(eventState, index: 5)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
        dispatch2D(encoder, pipeline: brushPipeline)
        encoder.endEncoding()
        encodeFounderInjection(into: commandBuffer, settings: settings, position: brush.position)
    }

    private func encodeVisibleCellCompaction(
        into commandBuffer: MTLCommandBuffer,
        settings: RendererSettings
    ) {
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.label = "Reset indirect living-cell count"
            blit.fill(
                buffer: cellDrawArguments,
                range: MemoryLayout<UInt32>.stride..<(2 * MemoryLayout<UInt32>.stride),
                value: 0
            )
            blit.endEncoding()
        }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Compact visible living cells"
        var uniforms = makeUniforms(settings: settings)
        encoder.setComputePipelineState(compactCellRenderPipeline)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 0)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 1)
        encoder.setBuffer(visibleCellIndices, offset: 0, index: 2)
        encoder.setBuffer(cellDrawArguments, offset: 0, index: 3)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 4)
        encoder.setBuffer(cellIdentities, offset: 0, index: 5)
        dispatchCells(encoder, pipeline: compactCellRenderPipeline)
        encoder.endEncoding()
    }

    private func encodeRender(view: MTKView, into commandBuffer: MTLCommandBuffer, settings: RendererSettings) {
        guard let drawable = view.currentDrawable,
              let drawableDescriptor = view.currentRenderPassDescriptor,
              ensureRenderTargets(width: drawable.texture.width, height: drawable.texture.height),
              let sceneColor,
              let bloomTextureA,
              let bloomTextureB else { return }

        let observationZoom = settings.cameraZoom / max(settings.worldScale, 1)
        if observationZoom > 5, observationZoom < 180 {
            encodeVisibleCellCompaction(into: commandBuffer, settings: settings)
        }

        let sceneDescriptor = MTLRenderPassDescriptor()
        let sceneAttachment = sceneDescriptor.colorAttachments[0]!
        sceneAttachment.texture = sceneColor
        sceneAttachment.loadAction = .clear
        sceneAttachment.storeAction = .store
        sceneAttachment.clearColor = MTLClearColorMake(0.0015, 0.003, 0.006, 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: sceneDescriptor) else { return }
        encoder.label = "Render linear HDR simulation state"
        var uniforms = makeUniforms(settings: settings)
        if observationZoom >= 64 {
            encoder.setRenderPipelineState(quantumRenderPipeline)
            encoder.setFragmentTexture(quantumState, index: 0)
            encoder.setFragmentTexture(state, index: 1)
            encoder.setFragmentTexture(ecology, index: 2)
        } else if observationZoom >= 18 {
            encoder.setRenderPipelineState(cellularSurfacePipeline)
            encoder.setFragmentTexture(state, index: 0)
            encoder.setFragmentTexture(ecology, index: 1)
            encoder.setFragmentTexture(environmentState, index: 2)
            encoder.setFragmentTexture(eventState, index: 3)
            encoder.setFragmentTexture(mechanicalState, index: 4)
        } else {
            encoder.setRenderPipelineState(renderPipeline)
            encoder.setFragmentTexture(state, index: 0)
            encoder.setFragmentTexture(ecology, index: 1)
            encoder.setFragmentTexture(environmentState, index: 2)
            encoder.setFragmentTexture(eventState, index: 3)
            encoder.setFragmentTexture(mechanicalState, index: 4)
        }
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        if observationZoom < 24 {
            encoder.setRenderPipelineState(agentRenderPipeline)
            encoder.setVertexBuffer(agentState, offset: 0, index: 0)
            encoder.setVertexBuffer(agentOccupancy, offset: 0, index: 1)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 2)
            encoder.setVertexBuffer(cellAggregates, offset: 0, index: 3)
            encoder.setFragmentTexture(state, index: 0)
            encoder.setFragmentTexture(ecology, index: 1)
            encoder.setFragmentTexture(quantumState, index: 2)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
            encoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 6,
                instanceCount: Self.maxAgentCount
            )
        }

        if observationZoom > 5, observationZoom < 180 {
            encoder.setRenderPipelineState(cellRenderPipeline)
            encoder.setVertexBuffer(agentState, offset: 0, index: 0)
            encoder.setVertexBuffer(agentOccupancy, offset: 0, index: 1)
            encoder.setVertexBuffer(cellState, offset: 0, index: 2)
            encoder.setVertexBuffer(cellOccupancy, offset: 0, index: 3)
            encoder.setVertexBuffer(membraneVertices, offset: 0, index: 4)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 5)
            encoder.setVertexBuffer(visibleCellIndices, offset: 0, index: 6)
            encoder.setVertexBuffer(cellIdentities, offset: 0, index: 7)
            encoder.setVertexBuffer(heritablePrograms, offset: 0, index: 8)
            encoder.setVertexBuffer(programInteractions, offset: 0, index: 9)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
            encoder.drawPrimitives(
                type: .triangle,
                indirectBuffer: cellDrawArguments,
                indirectBufferOffset: 0
            )
        }
        encoder.endEncoding()

        var postUniforms = PostProcessUniforms(
            sourceSize: SIMD2<Float>(Float(sceneColor.width), Float(sceneColor.height)),
            exposure: observationZoom >= 64 ? 1.06 :
                (observationZoom >= 18 ? 0.82 : (observationZoom >= 6 ? 0.92 : 1.16)),
            bloomIntensity: observationZoom >= 420 ? 0.0 :
                (observationZoom >= 64 ? 0.22 :
                    (observationZoom >= 18 ? 0.08 : (observationZoom >= 6 ? 0.16 : 0.24))),
            observationZoom: observationZoom,
            frameIndex: UInt32(truncatingIfNeeded: frameSerial)
        )
        if postUniforms.bloomIntensity > 0.001 {
            encodeBloom(
                source: sceneColor,
                textureA: bloomTextureA,
                textureB: bloomTextureB,
                uniforms: &postUniforms,
                into: commandBuffer
            )
        }

        guard let compositeEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: drawableDescriptor) else { return }
        compositeEncoder.label = "Composite HDR scene into display gamut"
        compositeEncoder.setRenderPipelineState(compositePipeline)
        compositeEncoder.setFragmentTexture(sceneColor, index: 0)
        compositeEncoder.setFragmentTexture(bloomTextureA, index: 1)
        compositeEncoder.setFragmentBytes(
            &postUniforms,
            length: MemoryLayout<PostProcessUniforms>.stride,
            index: 0
        )
        compositeEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        compositeEncoder.endEncoding()
        let observationInterval = settings.trackedAgentID == .max
            ? Self.agentObservationIntervalFrames
            : Self.trackedAgentObservationIntervalFrames
        if frameSerial.isMultiple(of: observationInterval) {
            encodeAgentObservation(into: commandBuffer)
        }
        commandBuffer.present(drawable)
    }

    private func encodeBloom(
        source: MTLTexture,
        textureA: MTLTexture,
        textureB: MTLTexture,
        uniforms: inout PostProcessUniforms,
        into commandBuffer: MTLCommandBuffer
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Quarter-resolution HDR bloom"
        encoder.setComputePipelineState(bloomPrefilterPipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(textureA, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<PostProcessUniforms>.stride, index: 0)
        dispatchTexture(encoder, pipeline: bloomPrefilterPipeline, texture: textureA)
        encoder.memoryBarrier(resources: [textureA])

        var direction = SIMD2<Float>(1, 0)
        encoder.setComputePipelineState(bloomBlurPipeline)
        encoder.setTexture(textureA, index: 0)
        encoder.setTexture(textureB, index: 1)
        encoder.setBytes(&direction, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        dispatchTexture(encoder, pipeline: bloomBlurPipeline, texture: textureB)
        encoder.memoryBarrier(resources: [textureB])

        direction = SIMD2<Float>(0, 1)
        encoder.setTexture(textureB, index: 0)
        encoder.setTexture(textureA, index: 1)
        encoder.setBytes(&direction, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        dispatchTexture(encoder, pipeline: bloomBlurPipeline, texture: textureA)
        encoder.endEncoding()
    }

    private func ensureRenderTargets(width: Int, height: Int) -> Bool {
        let size = MTLSize(width: width, height: height, depth: 1)
        if size.width == renderTargetSize.width,
           size.height == renderTargetSize.height,
           sceneColor != nil,
           bloomTextureA != nil,
           bloomTextureB != nil {
            return true
        }

        let sceneDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg11b10Float,
            width: max(width, 1),
            height: max(height, 1),
            mipmapped: false
        )
        sceneDescriptor.storageMode = .private
        sceneDescriptor.usage = [.renderTarget, .shaderRead]

        let bloomDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: max((width + 3) / 4, 1),
            height: max((height + 3) / 4, 1),
            mipmapped: false
        )
        bloomDescriptor.storageMode = .private
        bloomDescriptor.usage = [.shaderRead, .shaderWrite]

        guard let nextScene = device.makeTexture(descriptor: sceneDescriptor),
              let nextBloomA = device.makeTexture(descriptor: bloomDescriptor),
              let nextBloomB = device.makeTexture(descriptor: bloomDescriptor) else {
            return false
        }
        nextScene.label = "Linear HDR simulation scene"
        nextBloomA.label = "Quarter-resolution bloom A"
        nextBloomB.label = "Quarter-resolution bloom B"
        sceneColor = nextScene
        bloomTextureA = nextBloomA
        bloomTextureB = nextBloomB
        renderTargetSize = size
        return true
    }

    private func encodeAgentObservation(into commandBuffer: MTLCommandBuffer) {
        guard let slot = agentObservationRingState.acquire() else { return }
        let observedRecords = agentObservationBuffers[slot]
        let observedLineageEvents = lineageEventObservationBuffers[slot]
        let observedIdentityCounters = identityCounterObservationBuffers[slot]
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            agentObservationRingState.release(slot)
            return
        }
        encoder.label = "Collect compact organism observations"
        encoder.setComputePipelineState(collectAgentObservationPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBuffer(observedRecords, offset: 0, index: 2)
        encoder.setBuffer(cellAggregates, offset: 0, index: 3)
        encoder.setBuffer(developmentalGenomes, offset: 0, index: 4)
        encoder.setBuffer(resonanceGenomes, offset: 0, index: 5)
        dispatchAgents(encoder, pipeline: collectAgentObservationPipeline)
        encoder.endEncoding()

        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            let ringState = agentObservationRingState
            commandBuffer.addCompletedHandler { _ in ringState.release(slot) }
            return
        }
        blit.label = "Collect permanent lineage records"
        blit.copy(
            from: lineageEvents,
            sourceOffset: 0,
            to: observedLineageEvents,
            destinationOffset: 0,
            size: observedLineageEvents.length
        )
        blit.copy(
            from: identityCounters,
            sourceOffset: 0,
            to: observedIdentityCounters,
            destinationOffset: 0,
            size: observedIdentityCounters.length
        )
        blit.endEncoding()

        let callback = onObservationBatch
        let buffers = SendableAgentObservationBuffers(
            records: observedRecords,
            lineageEvents: observedLineageEvents,
            identityCounters: observedIdentityCounters
        )
        let ringState = agentObservationRingState
        let deliveryState = lineageEventDeliveryState
        let agentCapacity = Self.maxAgentCount
        let lineageCapacity = Self.lineageEventCapacity
        commandBuffer.addCompletedHandler { _ in
            defer { ringState.release(slot) }
            let records = buffers.records.contents().bindMemory(
                to: AgentObservationRecord.self,
                capacity: agentCapacity
            )
            var observations: [AgentObservation] = []
            observations.reserveCapacity(32)
            for index in 0..<agentCapacity where records[index].flags & 1 != 0 {
                let record = records[index]
                observations.append(AgentObservation(
                    id: index,
                    birthID: record.birthID,
                    parentBirthID: record.parentBirthID,
                    position: record.position,
                    generation: record.generation,
                    isHunter: record.flags & 2 != 0,
                    genomeHash: record.genomeHash,
                    topologyHash: record.topologyHash,
                    morphology: record.morphology,
                    dynamics: record.dynamics,
                    mutationDistance: record.mutationDistance
                ))
            }
            let eventRecords = buffers.lineageEvents.contents().bindMemory(
                to: LineageEventRecord.self,
                capacity: lineageCapacity
            )
            let counters = buffers.identityCounters.contents().bindMemory(to: UInt32.self, capacity: 5)
            let events = deliveryState.consume(
                records: eventRecords,
                writeSequence: counters[2],
                capacity: lineageCapacity
            )
            callback?(events, observations)
        }
    }

    private func observeWorld(
        slot: MetricReadbackSlot,
        settings: RendererSettings,
        completedGeneration: UInt32,
        completedSteps: UInt64
    ) {
        let raw = slot.metrics.contents().bindMemory(
            to: UInt32.self,
            capacity: Self.worldCount * Self.metricCount
        )
        let pixelCount = Double(Self.gridSize * Self.gridSize)
        let metricScale = Self.metricScale
        let quantumNormRaw = slot.quantumNorm.contents().load(as: UInt32.self)
        let quantumNorm = Double(quantumNormRaw) / Self.quantumMetricScale
        let occupancy = slot.agentOccupancy.contents().bindMemory(
            to: UInt32.self,
            capacity: Self.maxAgentCount
        )
        let agents = slot.agentState.contents().bindMemory(to: AgentState.self, capacity: Self.maxAgentCount)
        let cellular = slot.cellAggregates.contents().bindMemory(
            to: CellAggregate.self,
            capacity: Self.maxAgentCount
        )
        let programRecords = slot.programRecords.contents().bindMemory(
            to: ProgramMetricRecord.self,
            capacity: Self.maxAgentCount
        )
        let identityCounterValues = slot.identityCounters.contents().bindMemory(
            to: UInt32.self,
            capacity: 5
        )
        let heritableProgramCount = min(
            Int(identityCounterValues[4]), Self.maxHeritableProgramCount
        )
        let heritableProgramPoolUtilization = Double(heritableProgramCount) /
            Double(Self.maxHeritableProgramCount)
        let livingIndices = (0..<Self.maxAgentCount).filter { occupancy[$0] != 0 }
        let hunterCount = livingIndices.reduce(into: 0) { count, index in
            if agents[index].geneC.w >= 0.08 { count += 1 }
        }
        let lineageBins = Set(livingIndices.map {
            programRecords[$0].developmental.topology.z
        })
        let meanOrganismSpeed = livingIndices.isEmpty ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(simd_length(agents[index].velocity)) * Double(max(settings.worldScale, 1))
        } / Double(livingIndices.count)
        let cellCount = livingIndices.reduce(into: 0) { total, index in
            total += max(0, min(Self.maxCellCount, Int(cellular[index].physiology.x.rounded())))
        }
        let meanCellsPerOrganism = livingIndices.isEmpty
            ? 0
            : Double(cellCount) / Double(livingIndices.count)
        let largestTissueCellCount = livingIndices.reduce(into: 0) { largest, index in
            largest = max(
                largest,
                max(0, min(Self.maxCellCount, Int(cellular[index].physiology.x.rounded())))
            )
        }
        let cellPoolUtilization = Double(cellCount) / Double(Self.maxCellCount)
        let meanMixedProgramCellFraction = cellCount == 0 ? 0 : livingIndices.reduce(0.0) {
            total, index in
            total + Double(max(cellular[index].physiology.x, 0)) *
                Double(max(cellular[index].inheritance.y, 0))
        } / Double(cellCount)
        let maximumProgramRichness = livingIndices.reduce(into: 0) { maximum, index in
            maximum = max(maximum, Int(max(cellular[index].inheritance.z, 0).rounded()))
        }
        let meanProgramEcology: SIMD4<Double> = cellCount == 0
            ? .zero
            : livingIndices.reduce(into: SIMD4<Double>.zero) { total, index in
                let weight = Double(max(cellular[index].physiology.x, 0))
                total.x += Double(cellular[index].programEcology.x) * weight
                total.y += Double(cellular[index].programEcology.y) * weight
                total.w += Double(cellular[index].programEcology.w) * weight
            } / Double(cellCount)
        let recognitionWeight = livingIndices.reduce(0.0) { total, index in
            guard cellular[index].programEcology.z >= 0 else { return total }
            return total + Double(max(cellular[index].physiology.x, 0) *
                max(cellular[index].inheritance.y, 0))
        }
        let meanProgramRecognitionCompatibility = recognitionWeight > 0
            ? livingIndices.reduce(0.0) { total, index in
                guard cellular[index].programEcology.z >= 0 else { return total }
                let weight = Double(max(cellular[index].physiology.x, 0) *
                    max(cellular[index].inheritance.y, 0))
                return total + Double(cellular[index].programEcology.z) * weight
            } / recognitionWeight
            : -1
        let dividingCellCount = livingIndices.reduce(into: 0) { total, index in
            let count = max(0, min(Self.maxCellCount, Int(cellular[index].physiology.x.rounded())))
            total += Int((Float(count) * max(cellular[index].morphology.w, 0)).rounded())
        }
        let meanCellATP = cellCount == 0 ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].physiology.x, 0) * max(cellular[index].physiology.y, 0))
        } / Double(cellCount)
        let meanCellIntegrity = cellCount == 0 ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].physiology.x, 0) * max(cellular[index].physiology.z, 0))
        } / Double(cellCount)
        let meanCellStress = cellCount == 0 ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].physiology.x, 0) * max(cellular[index].physiology.w, 0))
        } / Double(cellCount)
        let meanMembraneVoltage = cellCount == 0 ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].physiology.x, 0) * cellular[index].dynamics.x)
        } / Double(cellCount)
        let meanPhaseCoherence = cellCount == 0 ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].physiology.x, 0) * max(cellular[index].dynamics.y, 0))
        } / Double(cellCount)
        let meanOscillationFrequency = cellCount == 0 ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].physiology.x, 0) * max(cellular[index].dynamics.z, 0))
        } / Double(cellCount)
        let meanTissueStrain = cellCount == 0 ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].physiology.x, 0) * max(cellular[index].mechanics.x, 0))
        } / Double(cellCount)
        let cellularEnergyHarvest = livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].energetics.x, 0))
        }
        let cellularEnergyDemand = livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].energetics.y + cellular[index].energetics.z, 0))
        }
        let cellularEnergyDissipation = livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].energetics.w, 0))
        }
        let meanDevelopmentalRegulation: SIMD4<Double> = livingIndices.isEmpty
            ? .zero
            : livingIndices.reduce(into: SIMD4<Double>.zero) { total, index in
                let weight = Double(max(cellular[index].physiology.x, 0))
                total += SIMD4<Double>(cellular[index].regulation) * weight
            } / Double(max(cellCount, 1))
        let meanCausalEffects: SIMD4<Double> = livingIndices.isEmpty
            ? .zero
            : livingIndices.reduce(into: SIMD4<Double>.zero) { total, index in
                let weight = Double(max(cellular[index].physiology.x, 0))
                total += SIMD4<Double>(cellular[index].causality) * weight
            } / Double(max(cellCount, 1))
        let meanSignaling: SIMD4<Double> = livingIndices.isEmpty
            ? .zero
            : livingIndices.reduce(into: SIMD4<Double>.zero) { total, index in
                let weight = Double(max(cellular[index].physiology.x, 0))
                total += SIMD4<Double>(cellular[index].signaling) * weight
            } / Double(max(cellCount, 1))
        let meanSignalCausality: SIMD4<Double> = livingIndices.isEmpty
            ? .zero
            : livingIndices.reduce(into: SIMD4<Double>.zero) { total, index in
                let weight = Double(max(cellular[index].physiology.x, 0))
                total += SIMD4<Double>(cellular[index].signalCausality) * weight
            } / Double(max(cellCount, 1))
        let developmentalNodeCount = livingIndices.reduce(into: 0) { total, index in
            total += Int(programRecords[index].developmental.topology.x)
        }
        let developmentalEdgeCount = livingIndices.reduce(into: 0) { total, index in
            total += Int(programRecords[index].developmental.topology.y)
        }
        let meanDevelopmentalNodeCount = livingIndices.isEmpty
            ? 0 : Double(developmentalNodeCount) / Double(livingIndices.count)
        let meanDevelopmentalEdgeCount = livingIndices.isEmpty
            ? 0 : Double(developmentalEdgeCount) / Double(livingIndices.count)
        let meanResonanceFrequency = livingIndices.isEmpty ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(programRecords[index].resonance.mechanics.x)
        } / Double(livingIndices.count)
        let meanResonanceDamping = livingIndices.isEmpty ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(programRecords[index].resonance.mechanics.y)
        } / Double(livingIndices.count)
        let meanResonanceBandwidth = livingIndices.isEmpty ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(programRecords[index].resonance.tuning.x)
        } / Double(livingIndices.count)
        let meanResonanceAmplitude = cellCount == 0 ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].physiology.x, 0) * max(cellular[index].resonance.y, 0))
        } / Double(cellCount)
        let meanMembraneArea = cellCount == 0 ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].physiology.x, 0) * max(cellular[index].shape.x, 0))
        } / Double(cellCount)
        let meanMembranePerimeter = cellCount == 0 ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].physiology.x, 0) * max(cellular[index].shape.y, 0))
        } / Double(cellCount)
        let meanMembraneShapeIndex = cellCount == 0 ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].physiology.x, 0) * max(cellular[index].shape.z, 0))
        } / Double(cellCount)
        let meanJunctionForce = cellCount == 0 ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].physiology.x, 0) * max(cellular[index].shape.w, 0))
        } / Double(cellCount)
        let meanTissueElongation = livingIndices.isEmpty ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].geometryBoundary.z, 0))
        } / Double(livingIndices.count)
        let meanExposedMembraneLength = livingIndices.isEmpty ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].geometryBoundary.w, 0))
        } / Double(livingIndices.count)
        let meanCellGeneratedForce = cellCount == 0 ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].physiology.x, 0) * max(cellular[index].tissueMotion.w, 0))
        } / Double(cellCount)
        let meanTissueTorque = livingIndices.isEmpty ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(abs(cellular[index].tissueMotion.z))
        } / Double(livingIndices.count)
        let cellularContactLoad = livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].trophic.x, 0))
        }
        let cellularTrophicGain = livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].trophic.y, 0))
        }
        let cellularTrophicLoss = livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].trophic.z, 0))
        }
        let meanDetachmentScore = livingIndices.isEmpty ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(max(cellular[index].trophic.w, 0))
        } / Double(livingIndices.count)
        let meanMechanochemistryA: SIMD4<Double> = livingIndices.isEmpty
            ? .zero
            : livingIndices.reduce(into: SIMD4<Double>.zero) { total, index in
                total += SIMD4<Double>(
                    programRecords[index].developmental.mechanochemistryA
                )
            } / Double(livingIndices.count)
        let meanMechanochemistryB: SIMD4<Double> = livingIndices.isEmpty
            ? .zero
            : livingIndices.reduce(into: SIMD4<Double>.zero) { total, index in
                total += SIMD4<Double>(
                    programRecords[index].developmental.mechanochemistryB
                )
            } / Double(livingIndices.count)
        let meanLineageMutationDistance = livingIndices.isEmpty ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(max(agents[index].mutationDistance, 0))
        } / Double(livingIndices.count)
        let worlds = (0..<Self.worldCount).map { world -> WorldMetrics in
            let base = world * Self.metricCount
            func mean(_ metric: Int) -> Double {
                Double(raw[base + metric]) / (metricScale * pixelCount)
            }
            let biomass = mean(0)
            let recoveryTarget = Double(raw[base + 8])
            let lineageMasses = (16..<32).map { Double(raw[base + $0]) }
            let lineageTotal = lineageMasses.reduce(0, +)
            let lineageEntropy: Double
            if lineageTotal > 0 {
                lineageEntropy = -lineageMasses.reduce(0.0) { partial, mass in
                    guard mass > 0 else { return partial }
                    let probability = mass / lineageTotal
                    return partial + probability * log(probability)
                } / log(16.0)
            } else {
                lineageEntropy = 0
            }
            return WorldMetrics(
                biomassDensity: biomass,
                resourceDensity: mean(1),
                energyDensity: mean(2),
                occupiedFraction: mean(3),
                temporalActivity: mean(4),
                boundaryCoherence: mean(5),
                multiscaleDivergence: mean(6),
                recovery: recoveryTarget > 0 ? min(Double(raw[base + 7]) / recoveryTarget, 1) : 0.5,
                geneticDiversity: mean(9),
                lineageDiversity: min(max(lineageEntropy, 0), 1),
                nicheDifferentiation: mean(12),
                trophicActivity: mean(14),
                centroidX: biomass > 1e-9 ? min(max(mean(10) / biomass, 0), 1) : 0.5,
                centroidY: biomass > 1e-9 ? min(max(mean(11) / biomass, 0), 1) : 0.5
            )
        }

        let decision = evaluator.evaluate(worlds)
        if let champion = decision.rankedWorlds.first {
            latestSnapshot = EvolutionSnapshot(
                generation: Int(completedGeneration),
                totalSteps: completedSteps,
                selectedWorld: champion.worldIndex,
                archiveCount: decision.archiveCount,
                quantumNorm: quantumNorm,
                organismCount: livingIndices.count,
                hunterCount: hunterCount,
                organismLineageCount: lineageBins.count,
                meanOrganismSpeed: meanOrganismSpeed,
                cellCount: cellCount,
                dividingCellCount: dividingCellCount,
                meanCellATP: meanCellATP,
                meanCellIntegrity: meanCellIntegrity,
                meanCellStress: meanCellStress,
                meanMembraneVoltage: meanMembraneVoltage,
                meanPhaseCoherence: meanPhaseCoherence,
                meanOscillationFrequency: meanOscillationFrequency,
                meanTissueStrain: meanTissueStrain,
                cellularEnergyHarvest: cellularEnergyHarvest,
                cellularEnergyDemand: cellularEnergyDemand,
                cellularEnergyDissipation: cellularEnergyDissipation,
                meanProliferationProgram: meanDevelopmentalRegulation.x,
                meanAdhesiveProgram: meanDevelopmentalRegulation.y,
                meanContractileProgram: meanDevelopmentalRegulation.z,
                meanRepairProgram: meanDevelopmentalRegulation.w,
                meanDevelopmentalNodeCount: meanDevelopmentalNodeCount,
                meanDevelopmentalEdgeCount: meanDevelopmentalEdgeCount,
                meanResonanceFrequency: meanResonanceFrequency,
                meanResonanceDamping: meanResonanceDamping,
                meanResonanceBandwidth: meanResonanceBandwidth,
                meanResonanceAmplitude: meanResonanceAmplitude,
                meanMembraneArea: meanMembraneArea,
                meanMembranePerimeter: meanMembranePerimeter,
                meanMembraneShapeIndex: meanMembraneShapeIndex,
                meanJunctionForce: meanJunctionForce,
                meanLineageMutationDistance: meanLineageMutationDistance,
                meanMechanotransductionEffect: meanCausalEffects.x,
                meanProliferativeDrive: meanCausalEffects.y,
                meanContactSuppression: meanCausalEffects.z,
                meanRepairEffect: meanCausalEffects.w,
                meanCalciumActivity: meanSignaling.x,
                meanERKActivity: meanSignaling.y,
                meanSignalRefractory: meanSignaling.z,
                meanMechanicsCalciumEffect: meanSignalCausality.x,
                meanCalciumERKEffect: meanSignalCausality.y,
                meanERKTractionEffect: meanSignalCausality.z,
                cellularSignalingCost: meanSignalCausality.w,
                meanTissueElongation: meanTissueElongation,
                meanExposedMembraneLength: meanExposedMembraneLength,
                meanCellGeneratedForce: meanCellGeneratedForce,
                meanTissueTorque: meanTissueTorque,
                cellularContactLoad: cellularContactLoad,
                cellularTrophicGain: cellularTrophicGain,
                cellularTrophicLoss: cellularTrophicLoss,
                meanDetachmentScore: meanDetachmentScore,
                meanMechanicsCalciumGain: meanMechanochemistryA.x,
                meanJunctionTransmissionGain: meanMechanochemistryA.y,
                meanCalciumERKGain: meanMechanochemistryA.z,
                meanRefractoryRecoveryGain: meanMechanochemistryA.w,
                meanInheritedSignalingCost: meanMechanochemistryB.x,
                meanInheritedTractionGain: meanMechanochemistryB.y,
                meanDetachmentThreshold: meanMechanochemistryB.z,
                meanPropaguleInvestment: meanMechanochemistryB.w,
                meanCellsPerOrganism: meanCellsPerOrganism,
                largestTissueCellCount: largestTissueCellCount,
                cellPoolUtilization: cellPoolUtilization,
                heritableProgramCount: heritableProgramCount,
                heritableProgramPoolUtilization: heritableProgramPoolUtilization,
                meanMixedProgramCellFraction: meanMixedProgramCellFraction,
                maximumProgramRichness: maximumProgramRichness,
                meanProgramATPExchange: meanProgramEcology.x,
                meanProgramRejection: meanProgramEcology.y,
                meanProgramRecognitionCompatibility: meanProgramRecognitionCompatibility,
                meanProgramNetContribution: meanProgramEcology.w,
                metrics: champion.metrics,
                fitness: champion.fitness
            )
#if DEBUG
            let netCellularPower = cellularEnergyHarvest - cellularEnergyDemand -
                cellularEnergyDissipation
            let developmentalProgramSummary = String(
                format: "%.2f/%.2f/%.2f/%.2f",
                meanDevelopmentalRegulation.x,
                meanDevelopmentalRegulation.y,
                meanDevelopmentalRegulation.z,
                meanDevelopmentalRegulation.w
            )
            print(
                "generation=\(latestSnapshot.generation) world=\(champion.worldIndex) " +
                "viability=\(String(format: "%.3f", champion.fitness.viability)) " +
                "complexity=\(String(format: "%.3f", champion.fitness.adaptiveComplexity)) " +
                "recovery=\(String(format: "%.3f", champion.fitness.recovery)) " +
                "diversification=\(String(format: "%.3f", champion.fitness.diversification)) " +
                "novelty=\(String(format: "%.3f", champion.fitness.novelty)) " +
                "occupied=\(String(format: "%.4f", champion.metrics.occupiedFraction)) " +
                "biomass=\(String(format: "%.5f", champion.metrics.biomassDensity)) " +
                "energy=\(String(format: "%.4f", champion.metrics.energyDensity)) " +
                "resource=\(String(format: "%.4f", champion.metrics.resourceDensity)) " +
                "activity=\(String(format: "%.4f", champion.metrics.temporalActivity)) " +
                "boundary=\(String(format: "%.6f", champion.metrics.boundaryCoherence)) " +
                "multiscale=\(String(format: "%.4f", champion.metrics.multiscaleDivergence)) " +
                "lineages=\(String(format: "%.3f", champion.metrics.lineageDiversity)) " +
                "niches=\(String(format: "%.4f", champion.metrics.nicheDifferentiation)) " +
                "quantum_norm=\(String(format: "%.6f", quantumNorm)) " +
                "cells=\(cellCount) max_component=\(largestTissueCellCount) " +
                "pool=\(String(format: "%.5f", cellPoolUtilization)) " +
                "program_pool=\(heritableProgramCount)/\(Self.maxHeritableProgramCount) " +
                "mixed_programs=\(String(format: "%.4f", meanMixedProgramCellFraction))/" +
                "\(maximumProgramRichness) " +
                "program_ecology=\(String(format: "%.6f/%.4f/%+.4f/%+.6f", meanProgramEcology.x, meanProgramEcology.y, meanProgramRecognitionCompatibility, meanProgramEcology.w)) " +
                "dividing=\(dividingCellCount) " +
                "grn=\(String(format: "%.1f/%.1f", meanDevelopmentalNodeCount, meanDevelopmentalEdgeCount)) " +
                "programs=\(developmentalProgramSummary) " +
                "causal=\(String(format: "%+.2e/%+.2e/%+.2e/%+.2e", meanCausalEffects.x, meanCausalEffects.y, meanCausalEffects.z, meanCausalEffects.w)) " +
                "signals=\(String(format: "%.3f/%.3f/%.3f", meanSignaling.x, meanSignaling.y, meanSignaling.z)) " +
                "signal_causal=\(String(format: "%+.2e/%+.2e/%+.2e/%+.2e", meanSignalCausality.x, meanSignalCausality.y, meanSignalCausality.z, meanSignalCausality.w)) " +
                "cell_atp=\(String(format: "%.3f", meanCellATP)) " +
                "cell_integrity=\(String(format: "%.3f", meanCellIntegrity)) " +
                "cell_voltage=\(String(format: "%+.4f", meanMembraneVoltage)) " +
                "phase_coherence=\(String(format: "%.4f", meanPhaseCoherence)) " +
                "cell_frequency=\(String(format: "%.5f", meanOscillationFrequency)) " +
                "tissue_strain=\(String(format: "%.5f", meanTissueStrain)) " +
                "elongation=\(String(format: "%.4f", meanTissueElongation)) " +
                "exposed_membrane=\(String(format: "%.4f", meanExposedMembraneLength)) " +
                "cell_force=\(String(format: "%.7f", meanCellGeneratedForce)) " +
                "tissue_torque=\(String(format: "%.7f", meanTissueTorque)) " +
                "contact=\(String(format: "%.7f", cellularContactLoad)) " +
                "trophic=\(String(format: "%.7f/%.7f", cellularTrophicGain, cellularTrophicLoss)) " +
                "detach=\(String(format: "%.4f", meanDetachmentScore)) " +
                "cell_power=\(String(format: "%+.6f", netCellularPower))"
            )
            if let firstIndex = livingIndices.first {
                let first = agents[firstIndex]
                print(
                    "agents=\(livingIndices.count) id=\(firstIndex) " +
                    "position=(\(String(format: "%.5f", first.position.x))," +
                    "\(String(format: "%.5f", first.position.y))) " +
                    "speed=\(String(format: "%.7f", simd_length(first.velocity))) " +
                    "energy=\(String(format: "%.4f", first.energy)) " +
                    "biomass=\(String(format: "%.4f", first.biomass)) " +
                    "agent_generation=\(first.generation)"
                )
            } else {
                print("agents=0")
            }
#endif
            onSnapshot?(latestSnapshot)
        }
    }

    private func makeUniforms(
        settings: RendererSettings,
        brushPosition: SIMD2<Float> = SIMD2<Float>(0.5, 0.5),
        brushRadius: Float = 0,
        brushStrength: Float = 0
    ) -> SimulationUniforms {
        SimulationUniforms(
            width: UInt32(Self.gridSize),
            height: UInt32(Self.gridSize),
            worldCount: UInt32(Self.worldCount),
            step: UInt32(truncatingIfNeeded: totalSteps),
            dt: 0.18,
            resourceFlux: settings.resourceFlux,
            mutationScale: settings.mutationScale,
            transportScale: settings.transportScale,
            displayMode: settings.displayMode,
            trackedAgentID: settings.trackedAgentID,
            generation: generation,
            epochSteps: UInt32(Self.epochSteps),
            damageStep: UInt32(Self.damageStep),
            brushPosition: brushPosition,
            brushRadius: brushRadius,
            brushStrength: brushStrength,
            cameraCenter: settings.cameraCenter,
            cameraZoom: max(settings.cameraZoom, 0.000_000_001),
            worldScale: max(settings.worldScale, 1),
            viewportAspect: viewportAspect,
            intervention: SIMD4<Float>(settings.mechanosensingGain, 1, 1, 1)
        )
    }

    private func dispatchWorlds(_ encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState) {
        let threadgroup = threadsPerThreadgroup2D(pipeline: pipeline, gridWidth: Self.gridSize)
        encoder.dispatchThreads(
            MTLSize(width: Self.gridSize, height: Self.gridSize, depth: Self.worldCount),
            threadsPerThreadgroup: threadgroup
        )
    }

    private func dispatch2D(_ encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState) {
        let threadgroup = threadsPerThreadgroup2D(pipeline: pipeline, gridWidth: Self.gridSize)
        encoder.dispatchThreads(
            MTLSize(width: Self.gridSize, height: Self.gridSize, depth: 1),
            threadsPerThreadgroup: threadgroup
        )
    }

    private func dispatchQuantum(_ encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState) {
        let threadgroup = threadsPerThreadgroup2D(pipeline: pipeline, gridWidth: Self.quantumGridSize)
        encoder.dispatchThreads(
            MTLSize(width: Self.quantumGridSize, height: Self.quantumGridSize, depth: 1),
            threadsPerThreadgroup: threadgroup
        )
    }

    private func dispatchAgents(_ encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState) {
        let width = threadsPerThreadgroup1D(pipeline: pipeline, count: Self.maxAgentCount)
        encoder.dispatchThreads(
            MTLSize(width: Self.maxAgentCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
    }

    private func dispatchCells(_ encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState) {
        let width = threadsPerThreadgroup1D(pipeline: pipeline, count: Self.maxCellCount)
        encoder.dispatchThreads(
            MTLSize(width: Self.maxCellCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
    }

    private func dispatchTexture(
        _ encoder: MTLComputeCommandEncoder,
        pipeline: MTLComputePipelineState,
        texture: MTLTexture
    ) {
        let threadgroup = threadsPerThreadgroup2D(pipeline: pipeline, gridWidth: texture.width)
        encoder.dispatchThreads(
            MTLSize(width: texture.width, height: texture.height, depth: 1),
            threadsPerThreadgroup: threadgroup
        )
    }

    private func threadsPerThreadgroup2D(
        pipeline: MTLComputePipelineState,
        gridWidth: Int
    ) -> MTLSize {
        let width = max(1, min(pipeline.threadExecutionWidth, gridWidth))
        let availableRows = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)
        return MTLSize(width: width, height: min(availableRows, 8), depth: 1)
    }

    private func threadsPerThreadgroup1D(
        pipeline: MTLComputePipelineState,
        count: Int
    ) -> Int {
        let executionWidth = max(pipeline.threadExecutionWidth, 1)
        let limit = max(1, min(pipeline.maxTotalThreadsPerThreadgroup, min(count, 256)))
        return limit >= executionWidth
            ? max(executionWidth, (limit / executionWidth) * executionWidth)
            : limit
    }

    private func copyAllSlices(from source: MTLTexture, to destination: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        for slice in 0..<Self.worldCount {
            copySlice(from: source, sourceSlice: slice, to: destination, destinationSlice: slice, encoder: blit)
        }
        blit.endEncoding()
    }

    private func swapWorldReactionState() {
        swap(&state, &reactionState)
        swap(&genomeA, &reactionGenomeA)
        swap(&genomeB, &reactionGenomeB)
        swap(&ecology, &reactionEcology)
        swap(&genomeC, &reactionGenomeC)
        swap(&eventState, &reactionEventState)
    }

    private func copySlice(
        from source: MTLTexture,
        sourceSlice: Int,
        to destination: MTLTexture,
        destinationSlice: Int,
        encoder: MTLBlitCommandEncoder
    ) {
        encoder.copy(
            from: source,
            sourceSlice: sourceSlice,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: Self.gridSize, height: Self.gridSize, depth: 1),
            to: destination,
            destinationSlice: destinationSlice,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
    }

    private static func makeLibrary(device: MTLDevice) throws -> MTLLibrary {
        guard let url = Bundle.module.url(
            forResource: "Replicator",
            withExtension: "metal",
            subdirectory: "Shaders"
        ) else {
            throw EvolutionRendererError.missingShader
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        return try device.makeLibrary(source: source, options: nil)
    }

    private static func computePipeline(
        named name: String,
        library: MTLLibrary,
        device: MTLDevice
    ) throws -> MTLComputePipelineState {
        guard let function = library.makeFunction(name: name) else {
            throw EvolutionRendererError.missingFunction(name)
        }
        return try device.makeComputePipelineState(function: function)
    }

    private static func makeWorldTexture(device: MTLDevice, label: String) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = .rgba16Float
        descriptor.width = gridSize
        descriptor.height = gridSize
        descriptor.arrayLength = worldCount
        descriptor.mipmapLevelCount = 1
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw EvolutionRendererError.resourceAllocation(label)
        }
        texture.label = label
        return texture
    }

    private static func makeQuantumTexture(device: MTLDevice, label: String) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: quantumGridSize,
            height: quantumGridSize,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw EvolutionRendererError.resourceAllocation(label)
        }
        texture.label = label
        return texture
    }

}
