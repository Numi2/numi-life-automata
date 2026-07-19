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
}

private struct AgentState {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var geneA: SIMD4<Float>
    var geneB: SIMD4<Float>
    var geneC: SIMD4<Float>
    var energy: Float
    var biomass: Float
    var age: Float
    var generation: UInt32
}

struct AgentObservation: Sendable, Equatable {
    let id: Int
    let position: SIMD2<Float>
    let generation: UInt32
    let isHunter: Bool
}

private struct SendableAgentObservationBuffers: @unchecked Sendable {
    let state: MTLBuffer
    let occupancy: MTLBuffer
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
    private static let agentObservationRingSize = 8
    private static let metricCount = 32
    private static let metricScale = 4096.0
    private static let quantumMetricScale = 1_000_000_000.0

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let initializePipeline: MTLComputePipelineState
    private let initializeQuantumPipeline: MTLComputePipelineState
    private let expandWorldPipeline: MTLComputePipelineState
    private let expandQuantumPipeline: MTLComputePipelineState
    private let reactionPipeline: MTLComputePipelineState
    private let quantumPipeline: MTLComputePipelineState
    private let damagePipeline: MTLComputePipelineState
    private let brushPipeline: MTLComputePipelineState
    private let measurementPipeline: MTLComputePipelineState
    private let quantumMeasurementPipeline: MTLComputePipelineState
    private let initializeAgentPipeline: MTLComputePipelineState
    private let nucleateFounderPipeline: MTLComputePipelineState
    private let evolveAgentPipeline: MTLComputePipelineState
    private let spawnAgentPipeline: MTLComputePipelineState
    private let injectFounderPipeline: MTLComputePipelineState
    private let expandAgentPipeline: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState
    private let quantumRenderPipeline: MTLRenderPipelineState
    private let agentRenderPipeline: MTLRenderPipelineState
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
    private var quantumState: MTLTexture
    private var reactionQuantumState: MTLTexture
    private var agentState: MTLBuffer
    private var reactionAgentState: MTLBuffer
    private let agentOccupancy: MTLBuffer
    private let agentObservationStates: [MTLBuffer]
    private let agentObservationOccupancies: [MTLBuffer]
    private let metricsBuffer: MTLBuffer
    private let quantumMetricsBuffer: MTLBuffer
    private let stateLock = NSLock()
    private var settings = RendererSettings(
        isRunning: true,
        stepsPerFrame: 3,
        resourceFlux: 1,
        mutationScale: 1,
        transportScale: 1,
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
    private var evaluator = AdaptiveComplexityEvaluator(seed: 0xA170_6E51, eliteCount: 1)
    private var latestSnapshot = EvolutionSnapshot()

    var onSnapshot: (@Sendable (EvolutionSnapshot) -> Void)?
    var onAgentObservations: (@Sendable ([AgentObservation]) -> Void)?

    init(view: MTKView) throws {
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
        reactionPipeline = try Self.computePipeline(named: "reactWorld", library: library, device: device)
        quantumPipeline = try Self.computePipeline(named: "evolveQuantumField", library: library, device: device)
        damagePipeline = try Self.computePipeline(named: "damageWorld", library: library, device: device)
        brushPipeline = try Self.computePipeline(named: "applyBrush", library: library, device: device)
        measurementPipeline = try Self.computePipeline(named: "measureWorld", library: library, device: device)
        quantumMeasurementPipeline = try Self.computePipeline(named: "measureQuantumField", library: library, device: device)
        initializeAgentPipeline = try Self.computePipeline(named: "initializeAgents", library: library, device: device)
        nucleateFounderPipeline = try Self.computePipeline(named: "nucleateAutogenicFounder", library: library, device: device)
        evolveAgentPipeline = try Self.computePipeline(named: "evolveAgents", library: library, device: device)
        spawnAgentPipeline = try Self.computePipeline(named: "spawnAgents", library: library, device: device)
        injectFounderPipeline = try Self.computePipeline(named: "injectFounder", library: library, device: device)
        expandAgentPipeline = try Self.computePipeline(named: "expandAgents", library: library, device: device)

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
        renderDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        renderPipeline = try device.makeRenderPipelineState(descriptor: renderDescriptor)

        guard let quantumFragment = library.makeFunction(name: "quantumSurfaceFragment") else {
            throw EvolutionRendererError.missingFunction("quantumSurfaceFragment")
        }
        let quantumRenderDescriptor = MTLRenderPipelineDescriptor()
        quantumRenderDescriptor.label = "Bottom-up quantum scale renderer"
        quantumRenderDescriptor.vertexFunction = vertex
        quantumRenderDescriptor.fragmentFunction = quantumFragment
        quantumRenderDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
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
        agentAttachment.pixelFormat = .bgra8Unorm_srgb
        agentAttachment.isBlendingEnabled = true
        agentAttachment.rgbBlendOperation = .add
        agentAttachment.alphaBlendOperation = .add
        agentAttachment.sourceRGBBlendFactor = .sourceAlpha
        agentAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        agentAttachment.sourceAlphaBlendFactor = .one
        agentAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        agentRenderPipeline = try device.makeRenderPipelineState(descriptor: agentRenderDescriptor)

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
        quantumState = try Self.makeQuantumTexture(device: device, label: "Quantum wavefunction")
        reactionQuantumState = try Self.makeQuantumTexture(device: device, label: "Reaction quantum wavefunction")

        let agentStateLength = Self.maxAgentCount * MemoryLayout<AgentState>.stride
        guard let agentState = device.makeBuffer(length: agentStateLength, options: .storageModeShared),
              let reactionAgentState = device.makeBuffer(length: agentStateLength, options: .storageModeShared),
              let agentOccupancy = device.makeBuffer(
                length: Self.maxAgentCount * MemoryLayout<UInt32>.stride,
                options: .storageModeShared
              ) else {
            throw EvolutionRendererError.resourceAllocation("persistent organism state")
        }
        agentState.label = "Persistent organisms"
        reactionAgentState.label = "Reaction organism state"
        agentOccupancy.label = "Organism occupancy"
        self.agentState = agentState
        self.reactionAgentState = reactionAgentState
        self.agentOccupancy = agentOccupancy
        var observationStates: [MTLBuffer] = []
        var observationOccupancies: [MTLBuffer] = []
        for slot in 0..<Self.agentObservationRingSize {
            guard let stateBuffer = device.makeBuffer(length: agentStateLength, options: .storageModeShared),
                  let occupancyBuffer = device.makeBuffer(
                    length: Self.maxAgentCount * MemoryLayout<UInt32>.stride,
                    options: .storageModeShared
                  ) else {
                throw EvolutionRendererError.resourceAllocation("organism observation ring")
            }
            stateBuffer.label = "Observed organisms \(slot)"
            occupancyBuffer.label = "Observed occupancy \(slot)"
            observationStates.append(stateBuffer)
            observationOccupancies.append(occupancyBuffer)
        }
        agentObservationStates = observationStates
        agentObservationOccupancies = observationOccupancies

        let metricsLength = Self.worldCount * Self.metricCount * MemoryLayout<UInt32>.stride
        guard let metricsBuffer = device.makeBuffer(length: metricsLength, options: .storageModeShared) else {
            throw EvolutionRendererError.resourceAllocation("the metric reduction buffer")
        }
        metricsBuffer.label = "Adaptive complexity metrics"
        self.metricsBuffer = metricsBuffer
        guard let quantumMetricsBuffer = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else {
            throw EvolutionRendererError.resourceAllocation("the quantum norm buffer")
        }
        quantumMetricsBuffer.label = "Conserved quantum norm"
        self.quantumMetricsBuffer = quantumMetricsBuffer

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

        var evaluateGeneration = false
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
                    encodeMeasurements(into: commandBuffer, settings: frameSettings)
                    evaluateGeneration = true
                    break
                }
            }
            encodeQuantumStep(into: commandBuffer, settings: frameSettings)
            if evaluateGeneration {
                encodeQuantumMeasurement(into: commandBuffer)
            }
        }

        if evaluateGeneration {
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            observeWorld(settings: frameSettings)
            guard let evolutionBuffer = commandQueue.makeCommandBuffer() else { return }
            evolutionBuffer.label = "Numi Automata observation cycle"
            generation &+= 1
            encodeRender(view: view, into: evolutionBuffer, settings: frameSettings)
            evolutionBuffer.commit()
        } else {
            encodeRender(view: view, into: commandBuffer, settings: frameSettings)
            commandBuffer.commit()
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
        encoder.endEncoding()
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
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
        dispatchWorlds(encoder, pipeline: reactionPipeline)
        encoder.endEncoding()
        swapWorldReactionState()
        encodeAgentStep(into: commandBuffer, settings: settings)
    }

    private func encodeAgentStep(into commandBuffer: MTLCommandBuffer, settings: RendererSettings) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Autogenic nucleation, organism decisions, movement, and reproduction"
        var uniforms = makeUniforms(settings: settings)

        encoder.setComputePipelineState(nucleateFounderPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 2)
        encoder.setTexture(state, index: 0)
        encoder.setTexture(genomeA, index: 1)
        encoder.setTexture(genomeB, index: 2)
        encoder.setTexture(genomeC, index: 3)
        encoder.setTexture(ecology, index: 4)
        dispatch2D(encoder, pipeline: nucleateFounderPipeline)
        encoder.memoryBarrier(resources: [agentState, agentOccupancy])

        encoder.setComputePipelineState(evolveAgentPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(reactionAgentState, offset: 0, index: 1)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 2)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 3)
        encoder.setTexture(state, index: 0)
        encoder.setTexture(ecology, index: 1)
        encoder.setTexture(environmentState, index: 2)
        dispatchAgents(encoder, pipeline: evolveAgentPipeline)
        encoder.memoryBarrier(resources: [reactionAgentState])
        swap(&agentState, &reactionAgentState)

        encoder.setComputePipelineState(spawnAgentPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 2)
        dispatchAgents(encoder, pipeline: spawnAgentPipeline)
        encoder.endEncoding()
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

    private func encodeQuantumMeasurement(into commandBuffer: MTLCommandBuffer) {
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.label = "Reset quantum norm reduction"
            blit.fill(buffer: quantumMetricsBuffer, range: 0..<quantumMetricsBuffer.length, value: 0)
            blit.endEncoding()
        }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Measure conserved probability"
        encoder.setComputePipelineState(quantumMeasurementPipeline)
        encoder.setTexture(quantumState, index: 0)
        encoder.setBuffer(quantumMetricsBuffer, offset: 0, index: 0)
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

    private func encodeMeasurements(into commandBuffer: MTLCommandBuffer, settings: RendererSettings) {
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.label = "Reset metric reductions"
            blit.fill(buffer: metricsBuffer, range: 0..<metricsBuffer.length, value: 0)
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
        encoder.setBuffer(metricsBuffer, offset: 0, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 1)
        dispatchWorlds(encoder, pipeline: measurementPipeline)
        encoder.endEncoding()
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

    private func encodeRender(view: MTKView, into commandBuffer: MTLCommandBuffer, settings: RendererSettings) {
        guard let descriptor = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.label = "Render evolving fields"
        var uniforms = makeUniforms(settings: settings)
        let observationZoom = settings.cameraZoom / max(settings.worldScale, 1)
        if observationZoom >= 24 {
            encoder.setRenderPipelineState(quantumRenderPipeline)
            encoder.setFragmentTexture(quantumState, index: 0)
            encoder.setFragmentTexture(state, index: 1)
            encoder.setFragmentTexture(ecology, index: 2)
        } else {
            encoder.setRenderPipelineState(renderPipeline)
            encoder.setFragmentTexture(state, index: 0)
            encoder.setFragmentTexture(ecology, index: 1)
            encoder.setFragmentTexture(environmentState, index: 2)
        }
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        encoder.setRenderPipelineState(agentRenderPipeline)
        encoder.setVertexBuffer(agentState, offset: 0, index: 0)
        encoder.setVertexBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 2)
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
        encoder.endEncoding()
        encodeAgentObservation(into: commandBuffer)
        commandBuffer.present(drawable)
    }

    private func encodeAgentObservation(into commandBuffer: MTLCommandBuffer) {
        let slot = Int(frameSerial % UInt64(Self.agentObservationRingSize))
        let observedState = agentObservationStates[slot]
        let observedOccupancy = agentObservationOccupancies[slot]
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.label = "Snapshot persistent organism positions"
        blit.copy(
            from: agentState,
            sourceOffset: 0,
            to: observedState,
            destinationOffset: 0,
            size: observedState.length
        )
        blit.copy(
            from: agentOccupancy,
            sourceOffset: 0,
            to: observedOccupancy,
            destinationOffset: 0,
            size: observedOccupancy.length
        )
        blit.endEncoding()

        let callback = onAgentObservations
        let buffers = SendableAgentObservationBuffers(
            state: observedState,
            occupancy: observedOccupancy
        )
        let agentCapacity = Self.maxAgentCount
        commandBuffer.addCompletedHandler { _ in
            guard let callback else { return }
            let occupancy = buffers.occupancy.contents().bindMemory(
                to: UInt32.self,
                capacity: agentCapacity
            )
            let agents = buffers.state.contents().bindMemory(
                to: AgentState.self,
                capacity: agentCapacity
            )
            var observations: [AgentObservation] = []
            observations.reserveCapacity(32)
            for index in 0..<agentCapacity where occupancy[index] != 0 {
                let agent = agents[index]
                observations.append(AgentObservation(
                    id: index,
                    position: agent.position,
                    generation: agent.generation,
                    isHunter: agent.geneC.w >= 0.08
                ))
            }
            callback(observations)
        }
    }

    private func observeWorld(settings: RendererSettings) {
        let raw = metricsBuffer.contents().bindMemory(
            to: UInt32.self,
            capacity: Self.worldCount * Self.metricCount
        )
        let pixelCount = Double(Self.gridSize * Self.gridSize)
        let metricScale = Self.metricScale
        let quantumNormRaw = quantumMetricsBuffer.contents().load(as: UInt32.self)
        let quantumNorm = Double(quantumNormRaw) / Self.quantumMetricScale
        let occupancy = agentOccupancy.contents().bindMemory(to: UInt32.self, capacity: Self.maxAgentCount)
        let agents = agentState.contents().bindMemory(to: AgentState.self, capacity: Self.maxAgentCount)
        let livingIndices = (0..<Self.maxAgentCount).filter { occupancy[$0] != 0 }
        let hunterCount = livingIndices.reduce(into: 0) { count, index in
            if agents[index].geneC.w >= 0.08 { count += 1 }
        }
        let lineageBins = Set(livingIndices.map { index in
            Int((agents[index].geneB.w - floor(agents[index].geneB.w)) * 32)
        })
        let meanOrganismSpeed = livingIndices.isEmpty ? 0 : livingIndices.reduce(0.0) { total, index in
            total + Double(simd_length(agents[index].velocity)) * Double(max(settings.worldScale, 1))
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
                generation: Int(generation + 1),
                totalSteps: totalSteps,
                selectedWorld: champion.worldIndex,
                archiveCount: decision.archiveCount,
                quantumNorm: quantumNorm,
                organismCount: livingIndices.count,
                hunterCount: hunterCount,
                organismLineageCount: lineageBins.count,
                meanOrganismSpeed: meanOrganismSpeed,
                metrics: champion.metrics,
                fitness: champion.fitness
            )
#if DEBUG
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
                "niches=\(String(format: "%.4f", champion.metrics.nicheDifferentiation))"
                + " quantum_norm=\(String(format: "%.6f", quantumNorm))"
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
            viewportAspect: viewportAspect
        )
    }

    private func dispatchWorlds(_ encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState) {
        let width = max(1, min(pipeline.threadExecutionWidth, 16))
        let height = max(1, min(pipeline.maxTotalThreadsPerThreadgroup / width, 16))
        encoder.dispatchThreads(
            MTLSize(width: Self.gridSize, height: Self.gridSize, depth: Self.worldCount),
            threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1)
        )
    }

    private func dispatch2D(_ encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState) {
        let width = max(1, min(pipeline.threadExecutionWidth, 16))
        let height = max(1, min(pipeline.maxTotalThreadsPerThreadgroup / width, 16))
        encoder.dispatchThreads(
            MTLSize(width: Self.gridSize, height: Self.gridSize, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1)
        )
    }

    private func dispatchQuantum(_ encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState) {
        let width = max(1, min(pipeline.threadExecutionWidth, 16))
        let height = max(1, min(pipeline.maxTotalThreadsPerThreadgroup / width, 16))
        encoder.dispatchThreads(
            MTLSize(width: Self.quantumGridSize, height: Self.quantumGridSize, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1)
        )
    }

    private func dispatchAgents(_ encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState) {
        let width = max(1, min(pipeline.threadExecutionWidth, pipeline.maxTotalThreadsPerThreadgroup))
        encoder.dispatchThreads(
            MTLSize(width: Self.maxAgentCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
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
