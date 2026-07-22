import Foundation
import Metal
import QuartzCore

struct Metal4PipelineBuildTelemetry: Sendable {
    let archiveLoaded: Bool
    let archiveHits: Int
    let archiveMisses: Int
    let pipelineCount: Int
    let compilationMilliseconds: Double
    let archiveURL: URL?
    let archiveErrorDescription: String?
}

final class Metal4PipelineFactory {
    private let library: MTLLibrary
    private let compiler: MTL4Compiler
    private let serializer: MTL4PipelineDataSetSerializer
    private let taskOptions: MTL4CompilerTaskOptions
    private let pipelineScriptURL: URL
    private let archive: (any MTL4Archive)?
    private let archiveURL: URL?
    private let startedAt = CFAbsoluteTimeGetCurrent()
    private(set) var pipelineCount = 0
    private(set) var archiveLoaded = false
    private(set) var archiveHits = 0
    private(set) var archiveMisses = 0

    init(device: MTLDevice, library: MTLLibrary) throws {
        self.library = library

        let cacheRoot = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("science.numi.automata/Metal4", isDirectory: true)
        try FileManager.default.createDirectory(
            at: cacheRoot,
            withIntermediateDirectories: true
        )
        pipelineScriptURL = cacheRoot.appendingPathComponent(
            "Replicator-\(device.registryID).mtl4-json"
        )

        let serializerDescriptor = MTL4PipelineDataSetSerializerDescriptor()
        serializerDescriptor.configuration = [.captureDescriptors]
        serializer = device.makePipelineDataSetSerializer(descriptor: serializerDescriptor)

        let compilerDescriptor = MTL4CompilerDescriptor()
        compilerDescriptor.label = "Numi Metal 4 pipeline compiler"
        compilerDescriptor.pipelineDataSetSerializer = serializer
        compiler = try device.makeCompiler(descriptor: compilerDescriptor)

        taskOptions = MTL4CompilerTaskOptions()
        let bundledArchiveURL = Self.packagedResourceURL(
            name: "Replicator",
            extension: "mtl4archive"
        )
        // The packaged archive remains opt-in until every captured perspective pipeline
        // passes the M4 corruption soak. Runtime compilation still uses the packaged metallib.
        let archiveEnabled = ProcessInfo.processInfo.environment[
            "NUMI_ENABLE_METAL4_ARCHIVE"
        ] == "1"
        if archiveEnabled,
           let bundledArchiveURL,
           let loadedArchive = try? device.makeArchive(url: bundledArchiveURL) {
            archive = loadedArchive
            archiveURL = bundledArchiveURL
            archiveLoaded = true
        } else {
            archive = nil
            archiveURL = nil
        }
    }

    func makeComputePipeline(named name: String) throws -> MTLComputePipelineState {
        let function = MTL4LibraryFunctionDescriptor()
        function.library = library
        function.name = name
        let descriptor = MTL4ComputePipelineDescriptor()
        descriptor.label = name
        descriptor.computeFunctionDescriptor = function
        if let pipeline = try? archive?.makeComputePipelineState(descriptor: descriptor) {
            archiveHits += 1
            pipelineCount += 1
            return pipeline
        }
        archiveMisses += 1
        let pipeline = try compiler.makeComputePipelineState(
            descriptor: descriptor,
            compilerTaskOptions: taskOptions
        )
        pipelineCount += 1
        return pipeline
    }

    func makeRenderPipeline(
        label: String,
        vertex: String,
        fragment: String,
        pixelFormat: MTLPixelFormat,
        blending: Bool = false
    ) throws -> MTLRenderPipelineState {
        let vertexFunction = MTL4LibraryFunctionDescriptor()
        vertexFunction.library = library
        vertexFunction.name = vertex
        let fragmentFunction = MTL4LibraryFunctionDescriptor()
        fragmentFunction.library = library
        fragmentFunction.name = fragment

        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunctionDescriptor = vertexFunction
        descriptor.fragmentFunctionDescriptor = fragmentFunction
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = pixelFormat
        if blending {
            attachment.blendingState = .enabled
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        if let pipeline = try? archive?.makeRenderPipelineState(descriptor: descriptor) {
            archiveHits += 1
            pipelineCount += 1
            return pipeline
        }
        archiveMisses += 1
        let pipeline = try compiler.makeRenderPipelineState(
            descriptor: descriptor,
            compilerTaskOptions: taskOptions
        )
        pipelineCount += 1
        return pipeline
    }

    func makeMeshRenderPipeline(
        label: String,
        mesh: String,
        fragment: String,
        pixelFormat: MTLPixelFormat,
        blending: Bool = false
    ) throws -> MTLRenderPipelineState {
        let meshFunction = MTL4LibraryFunctionDescriptor()
        meshFunction.library = library
        meshFunction.name = mesh
        let fragmentFunction = MTL4LibraryFunctionDescriptor()
        fragmentFunction.library = library
        fragmentFunction.name = fragment

        let descriptor = MTL4MeshRenderPipelineDescriptor()
        descriptor.label = label
        descriptor.meshFunctionDescriptor = meshFunction
        descriptor.fragmentFunctionDescriptor = fragmentFunction
        descriptor.maxTotalThreadsPerMeshThreadgroup = 64
        descriptor.requiredThreadsPerMeshThreadgroup = MTLSize(width: 64, height: 1, depth: 1)
        descriptor.meshThreadgroupSizeIsMultipleOfThreadExecutionWidth = true
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = pixelFormat
        if blending {
            attachment.blendingState = .enabled
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        if let pipeline = try? archive?.makeRenderPipelineState(descriptor: descriptor) {
            archiveHits += 1
            pipelineCount += 1
            return pipeline
        }
        archiveMisses += 1
        let pipeline = try compiler.makeRenderPipelineState(
            descriptor: descriptor,
            compilerTaskOptions: taskOptions
        )
        pipelineCount += 1
        return pipeline
    }

    func finalize() -> Metal4PipelineBuildTelemetry {
        let captureScript = ProcessInfo.processInfo.environment[
            "NUMI_CAPTURE_METAL4_PIPELINES"
        ] == "1"
        var archiveErrorDescription: String?
        if captureScript {
            do {
                let data = try serializer.serializeAsPipelinesScript()
                try data.write(to: pipelineScriptURL, options: .atomic)
            } catch {
                archiveErrorDescription = error.localizedDescription
                FileHandle.standardError.write(Data(
                    "metal4_pipeline_capture_error=\(error.localizedDescription)\n".utf8
                ))
            }
        }
        let telemetry = Metal4PipelineBuildTelemetry(
            archiveLoaded: archiveLoaded,
            archiveHits: archiveHits,
            archiveMisses: archiveMisses,
            pipelineCount: pipelineCount,
            compilationMilliseconds: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000,
            archiveURL: archiveURL,
            archiveErrorDescription: archiveErrorDescription
        )
        if ProcessInfo.processInfo.environment["NUMI_METAL4_PIPELINE_TELEMETRY"] == "1" {
            print(
                "metal4_archive_loaded=\(archiveLoaded ? 1 : 0) " +
                "hits=\(archiveHits) misses=\(archiveMisses) " +
                "pipelines=\(pipelineCount) compile_ms=" +
                String(format: "%.3f", telemetry.compilationMilliseconds)
            )
        }
        return telemetry
    }

    private static func packagedResourceURL(name: String, extension fileExtension: String) -> URL? {
        let packagedBundle = Bundle.main.resourceURL
            .map { $0.appendingPathComponent("NumiAutomata_NumiAutomata.bundle", isDirectory: true) }
            .flatMap(Bundle.init(url:))
        return packagedBundle?.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "Shaders"
        ) ?? Bundle.module.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "Shaders"
        )
    }
}

struct Metal4SubmissionFeedback: Sendable {
    let errorDescription: String?
    let gpuStartTime: CFTimeInterval
    let gpuEndTime: CFTimeInterval
    let phaseSamples: [Metal4PhaseSample]

    var succeeded: Bool { errorDescription == nil }
}

struct Metal4PhaseSample: Sendable {
    let phase: String
    let milliseconds: Double
}

enum Metal4CommandStatus: String, Sendable, CustomStringConvertible {
    case notEnqueued
    case committed
    case completed
    case error

    var description: String { rawValue }
}

final class Metal4UniformArena: @unchecked Sendable {
    private static let alignment = 256

    let buffer: MTLBuffer
    private(set) var usedBytes = 0

    init(device: MTLDevice, capacity: Int, label: String) throws {
        guard let buffer = device.makeBuffer(length: capacity, options: .storageModeShared) else {
            throw EvolutionRendererError.resourceAllocation(label)
        }
        buffer.label = label
        self.buffer = buffer
    }

    func reset() {
        usedBytes = 0
    }

    func copy(bytes: UnsafeRawPointer, length: Int) -> MTLGPUAddress {
        let alignedOffset = (usedBytes + Self.alignment - 1) & ~(Self.alignment - 1)
        precondition(
            alignedOffset + length <= buffer.length,
            "Metal 4 uniform arena exhausted; increase the per-submission capacity"
        )
        buffer.contents().advanced(by: alignedOffset).copyMemory(from: bytes, byteCount: length)
        usedBytes = alignedOffset + length
        return buffer.gpuAddress + MTLGPUAddress(alignedOffset)
    }
}

final class Metal4SubmissionSlot: @unchecked Sendable {
    static let counterCapacity = 256
    private static let renderEncoderCapacity = 6

    let index: Int
    var allocator: MTL4CommandAllocator
    let uniformArena: Metal4UniformArena
    let counterHeap: any MTL4CounterHeap
    let computeArgumentTable: MTL4ArgumentTable
    private let vertexArgumentTables: [MTL4ArgumentTable]
    private let meshArgumentTables: [MTL4ArgumentTable]
    private let fragmentArgumentTables: [MTL4ArgumentTable]
    private var renderArgumentTableIndex = 0
    var isInFlight = false
    var submissionEpoch: UInt64 = 0
    var firstStep: UInt64 = 0
    var lastStep: UInt64 = 0
    var checkpointStep: UInt64 = 0

    init(index: Int, device: MTLDevice) throws {
        self.index = index
        guard let allocator = device.makeCommandAllocator() else {
            throw EvolutionRendererError.resourceAllocation("Metal 4 command allocator \(index)")
        }
        self.allocator = allocator
        let counterDescriptor = MTL4CounterHeapDescriptor()
        counterDescriptor.type = .timestamp
        counterDescriptor.count = Self.counterCapacity
        let counterHeap = try device.makeCounterHeap(descriptor: counterDescriptor)
        counterHeap.label = "Numi Metal 4 timestamp heap \(index)"
        self.counterHeap = counterHeap
        uniformArena = try Metal4UniformArena(
            device: device,
            capacity: 4 * 1_024 * 1_024,
            label: "Numi Metal 4 uniform arena \(index)"
        )
        computeArgumentTable = try Self.makeArgumentTable(
            device: device,
            label: "Numi compute arguments \(index)"
        )
        vertexArgumentTables = try (0..<Self.renderEncoderCapacity).map {
            try Self.makeArgumentTable(
                device: device,
                label: "Numi vertex arguments \(index).\($0)"
            )
        }
        meshArgumentTables = try (0..<Self.renderEncoderCapacity).map {
            try Self.makeArgumentTable(
                device: device,
                label: "Numi mesh arguments \(index).\($0)"
            )
        }
        fragmentArgumentTables = try (0..<Self.renderEncoderCapacity).map {
            try Self.makeArgumentTable(
                device: device,
                label: "Numi fragment arguments \(index).\($0)"
            )
        }
    }

    func resetArgumentTables() {
        renderArgumentTableIndex = 0
    }

    func nextRenderArgumentTables() -> (
        vertex: MTL4ArgumentTable,
        mesh: MTL4ArgumentTable,
        fragment: MTL4ArgumentTable
    ) {
        precondition(
            renderArgumentTableIndex < Self.renderEncoderCapacity,
            "Metal 4 submission exceeded its render-encoder argument-table capacity"
        )
        let index = renderArgumentTableIndex
        renderArgumentTableIndex += 1
        return (
            vertexArgumentTables[index], meshArgumentTables[index], fragmentArgumentTables[index]
        )
    }

    private static func makeArgumentTable(
        device: MTLDevice,
        label: String
    ) throws -> MTL4ArgumentTable {
        let descriptor = MTL4ArgumentTableDescriptor()
        descriptor.label = label
        descriptor.maxBufferBindCount = 31
        descriptor.maxTextureBindCount = 128
        descriptor.maxSamplerStateBindCount = 16
        descriptor.initializeBindings = true
        return try device.makeArgumentTable(descriptor: descriptor)
    }
}

final class Metal4ExecutionContext: @unchecked Sendable {
    static let maximumInFlightSubmissions = 3

    let device: MTLDevice
    private(set) var commandQueue: MTL4CommandQueue
    private(set) var stableResidencySet: MTLResidencySet
    private(set) var slots: [Metal4SubmissionSlot]
    private var presentationResidencySets: [MTLResidencySet] = []
    private var registeredStableAllocations: [any MTLAllocation] = []

    private let lock = NSLock()
    private var nextSlotIndex = 0
    private var maximumObservedInFlight = 0
    private var maximumUniformArenaBytes = 0
    private var transientResidentBytes: UInt64 = 0
    private var claimedDrawableIDs: Set<ObjectIdentifier> = []

    init(device: MTLDevice) throws {
        self.device = device

        let queueDescriptor = MTL4CommandQueueDescriptor()
        queueDescriptor.label = "Numi Metal 4 command queue"
        commandQueue = try device.makeMTL4CommandQueue(descriptor: queueDescriptor)

        let residencyDescriptor = MTLResidencySetDescriptor()
        residencyDescriptor.label = "Numi stable causal residency"
        residencyDescriptor.initialCapacity = 192
        stableResidencySet = try device.makeResidencySet(descriptor: residencyDescriptor)

        slots = try (0..<Self.maximumInFlightSubmissions).map {
            try Metal4SubmissionSlot(index: $0, device: device)
        }
        for slot in slots {
            stableResidencySet.addAllocation(slot.uniformArena.buffer)
        }
        stableResidencySet.commit()
        stableResidencySet.requestResidency()
        commandQueue.addResidencySet(stableResidencySet)
    }

    var residentBytes: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return stableResidencySet.allocatedSize + transientResidentBytes
    }

    var unfinishedSubmissionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return slots.reduce(into: 0) { $0 += $1.isInFlight ? 1 : 0 }
    }

    var allocatorHighWatermark: Int {
        lock.lock()
        defer { lock.unlock() }
        return maximumObservedInFlight
    }

    var uniformArenaHighWaterBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return maximumUniformArenaBytes
    }

    func register(_ allocations: [any MTLAllocation]) {
        guard !allocations.isEmpty else { return }
        registeredStableAllocations.append(contentsOf: allocations)
        stableResidencySet.addAllocations(allocations)
        stableResidencySet.commit()
    }

    func reportTransientResidentBytes(_ bytes: UInt64) {
        lock.lock()
        transientResidentBytes = bytes
        lock.unlock()
    }

    func registerPresentationResidency(_ residencySet: MTLResidencySet) {
        guard !presentationResidencySets.contains(where: { $0 === residencySet }) else { return }
        presentationResidencySets.append(residencySet)
        commandQueue.addResidencySet(residencySet)
    }

    func claimDrawable(_ drawable: CAMetalDrawable) -> Bool {
        let identifier = ObjectIdentifier(drawable as AnyObject)
        lock.lock()
        defer { lock.unlock() }
        guard claimedDrawableIDs.count < Self.maximumInFlightSubmissions else {
            return false
        }
        return claimedDrawableIDs.insert(identifier).inserted
    }

    func releaseDrawable(identifier: ObjectIdentifier) {
        lock.lock()
        claimedDrawableIDs.remove(identifier)
        lock.unlock()
    }

    func acquireSubmission(
        label: String,
        epoch: UInt64,
        firstStep: UInt64,
        lastStep: UInt64,
        checkpointStep: UInt64
    ) -> Metal4CommandBufferContext? {
        lock.lock()
        let selectedIndex = (0..<slots.count).lazy
            .map { (self.nextSlotIndex + $0) % self.slots.count }
            .first { !self.slots[$0].isInFlight }
        guard let selectedIndex else {
            lock.unlock()
            return nil
        }
        let slot = slots[selectedIndex]
        slot.isInFlight = true
        slot.submissionEpoch = epoch
        slot.firstStep = firstStep
        slot.lastStep = lastStep
        slot.checkpointStep = checkpointStep
        slot.uniformArena.reset()
        slot.resetArgumentTables()
        slot.counterHeap.invalidateCounterRange(0..<Metal4SubmissionSlot.counterCapacity)
        nextSlotIndex = (selectedIndex + 1) % slots.count
        maximumObservedInFlight = max(
            maximumObservedInFlight,
            slots.reduce(into: 0) { $0 += $1.isInFlight ? 1 : 0 }
        )
        lock.unlock()

        guard let commandBuffer = device.makeCommandBuffer() else {
            release(slot: slot, resetAllocator: false)
            return nil
        }
        commandBuffer.label = label
        commandBuffer.beginCommandBuffer(allocator: slot.allocator)
        return Metal4CommandBufferContext(
            owner: self,
            commandBuffer: commandBuffer,
            slot: slot
        )
    }

    func makeCommandBuffer() -> Metal4CommandBufferContext? {
        acquireSubmission(
            label: "Numi Metal 4 submission",
            epoch: 0,
            firstStep: 0,
            lastStep: 0,
            checkpointStep: 0
        )
    }

    func commit(
        _ context: Metal4CommandBufferContext,
        completion: @escaping @Sendable (Metal4SubmissionFeedback) -> Void
    ) {
        context.finishEncoding()
        lock.lock()
        maximumUniformArenaBytes = max(
            maximumUniformArenaBytes,
            context.slot.uniformArena.usedBytes
        )
        lock.unlock()
        context.commandBuffer.endCommandBuffer()

        let drawable = context.drawable
        let drawableIdentifier = drawable.map { ObjectIdentifier($0 as AnyObject) }
        let options = MTL4CommitOptions()
        let slot = context.slot
        options.addFeedbackHandler { [weak self] feedback in
            let gpuMilliseconds = max(feedback.gpuEndTime - feedback.gpuStartTime, 0) * 1_000
            let result = Metal4SubmissionFeedback(
                errorDescription: feedback.error.map {
                    "\($0.localizedDescription) [\(String(describing: $0))]"
                },
                gpuStartTime: feedback.gpuStartTime,
                gpuEndTime: feedback.gpuEndTime,
                phaseSamples: context.resolvePhaseSamples(
                    totalGPUMilliseconds: gpuMilliseconds
                )
            )
            if let drawableIdentifier {
                self?.releaseDrawable(identifier: drawableIdentifier)
            }
            self?.release(slot: slot, resetAllocator: true)
            completion(result)
        }
        if let drawable {
            commandQueue.waitForDrawable(drawable)
        }
        commandQueue.commit([context.commandBuffer], options: options)

        if let drawable {
            commandQueue.signalDrawable(drawable)
            drawable.present()
        }
    }

    func commitAndWait(_ context: Metal4CommandBufferContext) throws -> Metal4SubmissionFeedback {
        let semaphore = DispatchSemaphore(value: 0)
        let resultLock = NSLock()
        nonisolated(unsafe) var result: Metal4SubmissionFeedback?
        commit(context) { feedback in
            resultLock.lock()
            result = feedback
            resultLock.unlock()
            semaphore.signal()
        }
        semaphore.wait()
        resultLock.lock()
        let feedback = result
        resultLock.unlock()
        guard let feedback else {
            throw EvolutionRendererError.resourceAllocation("Metal 4 commit feedback")
        }
        if let errorDescription = feedback.errorDescription {
            throw EvolutionRendererError.executionFailure(errorDescription)
        }
        return feedback
    }

    func rebuildQueueAndAllocators() throws {
        let queueDescriptor = MTL4CommandQueueDescriptor()
        queueDescriptor.label = "Numi Metal 4 recovery command queue"
        let nextQueue = try device.makeMTL4CommandQueue(descriptor: queueDescriptor)
        let nextSlots = try (0..<Self.maximumInFlightSubmissions).map {
            try Metal4SubmissionSlot(index: $0, device: device)
        }
        let stableDescriptor = MTLResidencySetDescriptor()
        stableDescriptor.label = "Numi recovered stable causal residency"
        stableDescriptor.initialCapacity = max(registeredStableAllocations.count + 3, 192)
        let nextStableResidencySet = try device.makeResidencySet(descriptor: stableDescriptor)
        nextStableResidencySet.addAllocations(
            registeredStableAllocations + nextSlots.map { $0.uniformArena.buffer }
        )
        nextStableResidencySet.commit()
        nextStableResidencySet.requestResidency()
        nextQueue.addResidencySet(nextStableResidencySet)
        for residencySet in presentationResidencySets {
            nextQueue.addResidencySet(residencySet)
        }

        lock.lock()
        defer { lock.unlock() }
        commandQueue = nextQueue
        stableResidencySet = nextStableResidencySet
        slots = nextSlots
        nextSlotIndex = 0
        claimedDrawableIDs.removeAll(keepingCapacity: true)
    }

    private func release(slot: Metal4SubmissionSlot, resetAllocator: Bool) {
        lock.lock()
        if resetAllocator {
            slot.allocator.reset()
        }
        slot.isInFlight = false
        lock.unlock()
    }
}

final class Metal4CommandBufferContext: @unchecked Sendable {
    fileprivate unowned let owner: Metal4ExecutionContext
    fileprivate let commandBuffer: MTL4CommandBuffer
    fileprivate let slot: Metal4SubmissionSlot
    fileprivate var drawable: CAMetalDrawable?

    private var computeEncoder: MTL4ComputeCommandEncoder?
    private var priorEncoderStages: MTLStages = []
    private let computeTable: MTL4ArgumentTable
    private let completionLock = NSLock()
    private let completionSemaphore = DispatchSemaphore(value: 0)
    private var completionHandlers: [@Sendable (Metal4CommandBufferContext) -> Void] = []
    private var completionFeedback: Metal4SubmissionFeedback?
    private var didCommit = false
    private var timestampLabels: [String] = []
    private var phaseTimingEnabled = false
    private var retainedResources: [AnyObject] = []

    init(
        owner: Metal4ExecutionContext,
        commandBuffer: MTL4CommandBuffer,
        slot: Metal4SubmissionSlot
    ) {
        self.owner = owner
        self.commandBuffer = commandBuffer
        self.slot = slot
        computeTable = slot.computeArgumentTable
    }

    var label: String? {
        get { commandBuffer.label }
        set { commandBuffer.label = newValue }
    }

    var uniformBytesUsed: Int { slot.uniformArena.usedBytes }
    var submissionSlotIndex: Int { slot.index }

    var status: Metal4CommandStatus {
        completionLock.lock()
        defer { completionLock.unlock() }
        guard let completionFeedback else { return didCommit ? .committed : .notEnqueued }
        return completionFeedback.succeeded ? .completed : .error
    }

    var error: Error? {
        completionLock.lock()
        defer { completionLock.unlock() }
        guard let description = completionFeedback?.errorDescription else { return nil }
        return NSError(
            domain: MTL4CommandQueueErrorDomain,
            code: MTL4CommandQueueError.internal.rawValue,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }

    var gpuStartTime: CFTimeInterval {
        completionLock.lock()
        defer { completionLock.unlock() }
        return completionFeedback?.gpuStartTime ?? 0
    }

    var gpuEndTime: CFTimeInterval {
        completionLock.lock()
        defer { completionLock.unlock() }
        return completionFeedback?.gpuEndTime ?? 0
    }

    var phaseSamples: [Metal4PhaseSample] {
        completionLock.lock()
        defer { completionLock.unlock() }
        return completionFeedback?.phaseSamples ?? []
    }

    func makeComputeCommandEncoder() -> Metal4ComputeCommandEncoderAdapter? {
        guard let encoder = activeComputeEncoder() else { return nil }
        return Metal4ComputeCommandEncoderAdapter(
            encoder: encoder,
            table: computeTable,
            uniformArena: slot.uniformArena,
            timestampRecorder: { [unowned self] encoder, label in
                self.recordTimestamp(encoder: encoder, ending: label)
            }
        )
    }

    func makeBlitCommandEncoder() -> Metal4BlitCommandEncoderAdapter? {
        guard let encoder = activeComputeEncoder() else { return nil }
        return Metal4BlitCommandEncoderAdapter(encoder: encoder)
    }

    func makeRenderCommandEncoder(
        descriptor: MTL4RenderPassDescriptor
    ) -> Metal4RenderCommandEncoderAdapter? {
        closeComputeEncoder()
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return nil
        }
        encoder.barrier(
            afterQueueStages: priorEncoderStages.isEmpty
                ? [.dispatch, .blit, .vertex, .mesh, .fragment]
                : priorEncoderStages,
            beforeStages: [.vertex, .mesh, .fragment],
            visibilityOptions: .device
        )
        priorEncoderStages = [.vertex, .mesh, .fragment]
        let tables = slot.nextRenderArgumentTables()
        return Metal4RenderCommandEncoderAdapter(
            encoder: encoder,
            vertexTable: tables.vertex,
            meshTable: tables.mesh,
            fragmentTable: tables.fragment,
            uniformArena: slot.uniformArena,
            timestampRecorder: { [unowned self] encoder, label in
                self.recordTimestamp(encoder: encoder, ending: label)
            }
        )
    }

    func claimPresentation(_ drawable: CAMetalDrawable) -> Bool {
        guard owner.claimDrawable(drawable) else { return false }
        self.drawable = drawable
        return true
    }

    func cancelPresentation() {
        guard let drawable else { return }
        owner.releaseDrawable(identifier: ObjectIdentifier(drawable as AnyObject))
        self.drawable = nil
    }

    func retainResources(_ resources: [AnyObject]) {
        retainedResources.append(contentsOf: resources)
    }

    func useResidencySet(_ residencySet: MTLResidencySet) {
        commandBuffer.useResidencySet(residencySet)
        retainedResources.append(residencySet)
    }

    func enablePhaseTiming() {
        phaseTimingEnabled = true
    }

    func writeTimestamp(ending phase: String) {
        guard phaseTimingEnabled else { return }
        guard timestampLabels.count < Metal4SubmissionSlot.counterCapacity else { return }
        if let computeEncoder {
            recordTimestamp(encoder: computeEncoder, ending: phase)
        } else {
            let index = timestampLabels.count
            commandBuffer.writeTimestamp(counterHeap: slot.counterHeap, index: index)
            timestampLabels.append(phase)
        }
    }

    func addCompletedHandler(
        _ handler: @escaping @Sendable (Metal4CommandBufferContext) -> Void
    ) {
        completionLock.lock()
        if completionFeedback != nil {
            completionLock.unlock()
            handler(self)
            return
        }
        completionHandlers.append(handler)
        completionLock.unlock()
    }

    func commit() {
        completionLock.lock()
        precondition(!didCommit, "A Metal 4 command buffer can only be committed once")
        didCommit = true
        completionLock.unlock()
        owner.commit(self) { [weak self] feedback in
            self?.complete(feedback)
        }
    }

    func waitUntilCompleted() {
        completionLock.lock()
        let completed = completionFeedback != nil
        completionLock.unlock()
        if !completed {
            completionSemaphore.wait()
        }
    }

    fileprivate func finishEncoding() {
        closeComputeEncoder()
    }

    fileprivate func resolvePhaseSamples(
        totalGPUMilliseconds: Double
    ) -> [Metal4PhaseSample] {
        guard timestampLabels.count > 1,
              let data = try? slot.counterHeap.resolveCounterRange(0..<timestampLabels.count)
        else { return [] }
        let timestamps = data.withUnsafeBytes { bytes -> [UInt64] in
            Array(bytes.bindMemory(to: UInt64.self).prefix(timestampLabels.count))
        }
        guard timestamps.count == timestampLabels.count,
              let first = timestamps.first,
              let last = timestamps.last,
              last > first else { return [] }
        let conversion = totalGPUMilliseconds / Double(last - first)
        var accumulated: [String: Double] = [:]
        var order: [String] = []
        for index in 1..<timestamps.count where timestamps[index] >= timestamps[index - 1] {
            let phase = timestampLabels[index]
            if accumulated[phase] == nil { order.append(phase) }
            let milliseconds = Double(
                timestamps[index] - timestamps[index - 1]
            ) * conversion
            guard milliseconds <= totalGPUMilliseconds * 1.05 + 0.001 else {
                continue
            }
            accumulated[phase, default: 0] += milliseconds
        }
        return order.compactMap { phase in
            accumulated[phase].map { Metal4PhaseSample(phase: phase, milliseconds: $0) }
        }
    }

    private func complete(_ feedback: Metal4SubmissionFeedback) {
        completionLock.lock()
        completionFeedback = feedback
        let handlers = completionHandlers
        completionHandlers.removeAll(keepingCapacity: false)
        completionLock.unlock()
        for handler in handlers {
            handler(self)
        }
        // A completed context can remain reachable briefly through client telemetry.
        // Release drawable and transient resource ownership immediately at GPU completion.
        retainedResources.removeAll(keepingCapacity: false)
        drawable = nil
        timestampLabels.removeAll(keepingCapacity: false)
        completionSemaphore.signal()
    }

    private func activeComputeEncoder() -> MTL4ComputeCommandEncoder? {
        if let computeEncoder { return computeEncoder }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        encoder.barrier(
            afterQueueStages: priorEncoderStages.isEmpty
                ? [.dispatch, .blit, .vertex, .mesh, .fragment]
                : priorEncoderStages,
            beforeStages: [.dispatch, .blit],
            visibilityOptions: .device
        )
        computeEncoder = encoder
        priorEncoderStages = [.dispatch, .blit]
        return encoder
    }

    private func recordTimestamp(
        encoder: MTL4ComputeCommandEncoder,
        ending phase: String
    ) {
        guard phaseTimingEnabled else { return }
        guard timestampLabels.count < Metal4SubmissionSlot.counterCapacity else { return }
        let index = timestampLabels.count
        encoder.writeTimestamp(
            granularity: .precise,
            counterHeap: slot.counterHeap,
            index: index
        )
        timestampLabels.append(phase)
    }

    private func recordTimestamp(
        encoder: MTL4RenderCommandEncoder,
        ending phase: String
    ) {
        guard phaseTimingEnabled else { return }
        guard timestampLabels.count < Metal4SubmissionSlot.counterCapacity else { return }
        let index = timestampLabels.count
        encoder.writeTimestamp(
            granularity: .precise,
            after: .fragment,
            counterHeap: slot.counterHeap,
            index: index
        )
        timestampLabels.append(phase)
    }

    private func closeComputeEncoder() {
        computeEncoder?.endEncoding()
        computeEncoder = nil
    }

}

final class Metal4ComputeCommandEncoderAdapter {
    private let encoder: MTL4ComputeCommandEncoder
    private let table: MTL4ArgumentTable
    private let uniformArena: Metal4UniformArena
    private let timestampRecorder: (MTL4ComputeCommandEncoder, String) -> Void
    private var hasUnbarrieredCommands = false

    init(
        encoder: MTL4ComputeCommandEncoder,
        table: MTL4ArgumentTable,
        uniformArena: Metal4UniformArena,
        timestampRecorder: @escaping (MTL4ComputeCommandEncoder, String) -> Void
    ) {
        self.encoder = encoder
        self.table = table
        self.uniformArena = uniformArena
        self.timestampRecorder = timestampRecorder
    }

    var label: String? {
        get { encoder.label }
        set { encoder.label = newValue }
    }

    func setComputePipelineState(_ state: MTLComputePipelineState) {
        encoder.setComputePipelineState(state)
    }

    func setBuffer(_ buffer: MTLBuffer?, offset: Int, index: Int) {
        table.setAddress(
            buffer.map { $0.gpuAddress + MTLGPUAddress(offset) } ?? 0,
            index: index
        )
    }

    func setTexture(_ texture: MTLTexture?, index: Int) {
        table.setTexture(texture?.gpuResourceID ?? MTLResourceID(), index: index)
    }

    func setBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) {
        table.setAddress(uniformArena.copy(bytes: bytes, length: length), index: index)
    }

    func fill(buffer: MTLBuffer, value: UInt8) {
        encoder.fill(buffer: buffer, range: 0..<buffer.length, value: value)
        hasUnbarrieredCommands = true
    }

    func dispatchThreads(_ threads: MTLSize, threadsPerThreadgroup: MTLSize) {
        encoder.setArgumentTable(table)
        encoder.dispatchThreads(
            threadsPerGrid: threads,
            threadsPerThreadgroup: threadsPerThreadgroup
        )
        hasUnbarrieredCommands = true
    }

    func dispatchThreadgroups(_ groups: MTLSize, threadsPerThreadgroup: MTLSize) {
        encoder.setArgumentTable(table)
        encoder.dispatchThreadgroups(
            threadgroupsPerGrid: groups,
            threadsPerThreadgroup: threadsPerThreadgroup
        )
        hasUnbarrieredCommands = true
    }

    func dispatchThreadgroups(
        indirectBuffer: MTLBuffer,
        indirectBufferOffset: Int,
        threadsPerThreadgroup: MTLSize
    ) {
        encoder.setArgumentTable(table)
        encoder.dispatchThreadgroups(
            indirectBuffer: indirectBuffer.gpuAddress + MTLGPUAddress(indirectBufferOffset),
            threadsPerThreadgroup: threadsPerThreadgroup
        )
        hasUnbarrieredCommands = true
    }

    func memoryBarrier(resources: [MTLResource]) {
        guard !resources.isEmpty else { return }
        encoder.barrier(
            afterEncoderStages: [.dispatch, .blit],
            beforeEncoderStages: [.dispatch, .blit],
            visibilityOptions: .device
        )
        hasUnbarrieredCommands = false
    }

    func writeTimestamp(ending phase: String) {
        timestampRecorder(encoder, phase)
    }

    func endEncoding() {
        guard hasUnbarrieredCommands else { return }
        encoder.barrier(
            afterEncoderStages: [.dispatch, .blit],
            beforeEncoderStages: [.dispatch, .blit],
            visibilityOptions: .device
        )
        hasUnbarrieredCommands = false
    }
}

final class Metal4BlitCommandEncoderAdapter {
    private let encoder: MTL4ComputeCommandEncoder
    private var hasUnbarrieredCommands = false

    init(encoder: MTL4ComputeCommandEncoder) {
        self.encoder = encoder
    }

    var label: String? {
        get { encoder.label }
        set { encoder.label = newValue }
    }

    func fill(buffer: MTLBuffer, range: Range<Int>, value: UInt8) {
        encoder.fill(buffer: buffer, range: range, value: value)
        hasUnbarrieredCommands = true
    }

    func copy(
        from source: MTLBuffer,
        sourceOffset: Int,
        to destination: MTLBuffer,
        destinationOffset: Int,
        size: Int
    ) {
        encoder.copy(
            sourceBuffer: source,
            sourceOffset: sourceOffset,
            destinationBuffer: destination,
            destinationOffset: destinationOffset,
            size: size
        )
        hasUnbarrieredCommands = true
    }

    func copy(
        from source: MTLTexture,
        sourceSlice: Int,
        sourceLevel: Int,
        sourceOrigin: MTLOrigin,
        sourceSize: MTLSize,
        to destination: MTLTexture,
        destinationSlice: Int,
        destinationLevel: Int,
        destinationOrigin: MTLOrigin
    ) {
        encoder.copy(
            sourceTexture: source,
            sourceSlice: sourceSlice,
            sourceLevel: sourceLevel,
            sourceOrigin: sourceOrigin,
            sourceSize: sourceSize,
            destinationTexture: destination,
            destinationSlice: destinationSlice,
            destinationLevel: destinationLevel,
            destinationOrigin: destinationOrigin
        )
        hasUnbarrieredCommands = true
    }

    func endEncoding() {
        guard hasUnbarrieredCommands else { return }
        encoder.barrier(
            afterEncoderStages: .blit,
            beforeEncoderStages: [.dispatch, .blit],
            visibilityOptions: .device
        )
        hasUnbarrieredCommands = false
    }
}

final class Metal4RenderCommandEncoderAdapter {
    private let encoder: MTL4RenderCommandEncoder
    private let vertexTable: MTL4ArgumentTable
    private let meshTable: MTL4ArgumentTable
    private let fragmentTable: MTL4ArgumentTable
    private let uniformArena: Metal4UniformArena
    private let timestampRecorder: (MTL4RenderCommandEncoder, String) -> Void

    init(
        encoder: MTL4RenderCommandEncoder,
        vertexTable: MTL4ArgumentTable,
        meshTable: MTL4ArgumentTable,
        fragmentTable: MTL4ArgumentTable,
        uniformArena: Metal4UniformArena,
        timestampRecorder: @escaping (MTL4RenderCommandEncoder, String) -> Void
    ) {
        self.encoder = encoder
        self.vertexTable = vertexTable
        self.meshTable = meshTable
        self.fragmentTable = fragmentTable
        self.uniformArena = uniformArena
        self.timestampRecorder = timestampRecorder
    }

    var label: String? {
        get { encoder.label }
        set { encoder.label = newValue }
    }

    func setRenderPipelineState(_ state: MTLRenderPipelineState) {
        encoder.setRenderPipelineState(state)
    }

    func setVertexBuffer(_ buffer: MTLBuffer?, offset: Int, index: Int) {
        vertexTable.setAddress(
            buffer.map { $0.gpuAddress + MTLGPUAddress(offset) } ?? 0,
            index: index
        )
    }

    func setVertexBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) {
        vertexTable.setAddress(uniformArena.copy(bytes: bytes, length: length), index: index)
    }

    func setMeshBuffer(_ buffer: MTLBuffer?, offset: Int, index: Int) {
        meshTable.setAddress(
            buffer.map { $0.gpuAddress + MTLGPUAddress(offset) } ?? 0,
            index: index
        )
    }

    func setMeshBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) {
        meshTable.setAddress(uniformArena.copy(bytes: bytes, length: length), index: index)
    }

    func setFragmentTexture(_ texture: MTLTexture?, index: Int) {
        fragmentTable.setTexture(texture?.gpuResourceID ?? MTLResourceID(), index: index)
    }

    func setFragmentBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) {
        fragmentTable.setAddress(uniformArena.copy(bytes: bytes, length: length), index: index)
    }

    func drawPrimitives(type: MTLPrimitiveType, vertexStart: Int, vertexCount: Int) {
        bindTables()
        encoder.drawPrimitives(
            primitiveType: type,
            vertexStart: vertexStart,
            vertexCount: vertexCount
        )
    }

    func drawPrimitives(
        type: MTLPrimitiveType,
        indirectBuffer: MTLBuffer,
        indirectBufferOffset: Int
    ) {
        bindTables()
        encoder.drawPrimitives(
            primitiveType: type,
            indirectBuffer: indirectBuffer.gpuAddress + MTLGPUAddress(indirectBufferOffset)
        )
    }

    func drawMeshThreadgroups(
        indirectBuffer: MTLBuffer,
        indirectBufferOffset: Int,
        threadsPerMeshThreadgroup: MTLSize
    ) {
        bindTables()
        encoder.drawMeshThreadgroups(
            indirectBuffer: indirectBuffer.gpuAddress + MTLGPUAddress(indirectBufferOffset),
            threadsPerObjectThreadgroup: MTLSize(width: 1, height: 1, depth: 1),
            threadsPerMeshThreadgroup: threadsPerMeshThreadgroup
        )
    }

    func writeTimestamp(ending phase: String) {
        timestampRecorder(encoder, phase)
    }

    func endEncoding() {
        encoder.endEncoding()
    }

    private func bindTables() {
        encoder.setArgumentTable(vertexTable, stages: .vertex)
        encoder.setArgumentTable(meshTable, stages: .mesh)
        encoder.setArgumentTable(fragmentTable, stages: .fragment)
    }
}
