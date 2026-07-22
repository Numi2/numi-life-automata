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
    var seed: UInt32
    var brushPosition: SIMD2<Float>
    var brushRadius: Float
    var brushStrength: Float
    var cameraCenter: SIMD2<Float>
    var cameraZoom: Float
    var worldScale: Float
    var viewportAspect: Float
    var intervention: SIMD4<Float>
}

private struct HeadlessReadbackBuffers {
    let agentState: MTLBuffer
    let agentOccupancy: MTLBuffer
    let cellAggregates: MTLBuffer
    let cellState: MTLBuffer
    let cellOccupancy: MTLBuffer
    let cellIdentities: MTLBuffer
    let heritablePrograms: MTLBuffer
    let programInteractions: MTLBuffer
    let developmentalGenomes: MTLBuffer
    let programSlots: MTLBuffer
    let identityCounters: MTLBuffer
    let lineageEvents: MTLBuffer
    let energyAudit: MTLBuffer
    let invariantState: MTLBuffer
    let qualificationTargetMeasurement: MTLBuffer
}

private struct QualificationTargetMeasurement {
    var identity: SIMD4<UInt32>
    var developmental: SIMD4<Float>
}

private struct ComponentProgramKey: Hashable {
    let componentID: UInt64
    let programID: UInt64
}

private struct ProgramRepresentationAccumulator {
    var parentProgramID: UInt64?
    var cellCount: Int
    var inheritedTrait: Double
    var collectiveTrait: Double
}

private func permanentProgramID(index: UInt32, generation: UInt32) -> UInt64 {
    (UInt64(generation) << 32) | UInt64(index)
}

private let permanentProgramSlotCapacity: UInt32 = 4_096
private let identityReadbackCounterCount = 19

extension EvolutionRenderer {
    func runHeadlessExperiment(
        configuration: HeadlessExperimentConfiguration,
        journal: ExperimentJournal,
        resultRetention: HeadlessResultRetention,
        reportProgress: Bool = true
    ) throws -> HeadlessExperimentResult {
        var runSettings = settings
        runSettings.isRunning = true
        runSettings.resetToken = UInt64(configuration.seed)
        runSettings.stepsPerFrame = 1
        runSettings.mechanosensingGain = configuration.mechanosensing.baselineGain
        runSettings.resourceFlux = configuration.environmentalScaffold.baselineResourceFlux
        runSettings.barrierGain = configuration.environmentalScaffold.baselineBarrierGain
        totalSteps = 0
        quantumStep = 0
        generation = 0
        frameSerial = 0
        evaluator = AdaptiveComplexityEvaluator(
            seed: 0xA170_6E51 ^ UInt64(configuration.seed),
            eliteCount: 1
        )
        lineageEventDeliveryState.reset()

        guard let initialization = commandQueue.makeCommandBuffer() else {
            throw EvolutionRendererError.resourceAllocation("headless initialization")
        }
        initialization.label = "Numi seeded experiment initialization"
        encodeInitialization(into: initialization, settings: runSettings)
        initialization.commit()
        initialization.waitUntilCompleted()
        if let error = initialization.error { throw error }
        appliedResetToken = runSettings.resetToken
        appliedExpansionToken = runSettings.expansionToken

        if !configuration.initialFounders.isEmpty {
            guard let introduction = commandQueue.makeCommandBuffer() else {
                throw EvolutionRendererError.resourceAllocation(
                    "headless founder introduction"
                )
            }
            introduction.label = "Numi controlled founder introduction"
            for founder in configuration.initialFounders {
                encodeFounderInjection(
                    into: introduction,
                    settings: runSettings,
                    position: founder.position
                )
            }
            introduction.commit()
            introduction.waitUntilCompleted()
            if let error = introduction.error { throw error }
        }

        let readback = try makeHeadlessReadbackBuffers()
        let startedAt = ISO8601DateFormatter().string(from: Date())
        try journal.append("header", ExperimentHeader(
            schemaVersion: 16,
            startedAt: startedAt,
            device: device.name,
            configuration: configuration
        ))

        let startTime = CFAbsoluteTimeGetCurrent()
        var nextSample = min(configuration.sampleInterval, configuration.steps)
        var lastEventSequence: UInt32 = 0
        var births: UInt64 = 0
        var deaths: UInt64 = 0
        var fissions: UInt64 = 0
        var fusions: UInt64 = 0
        var cellDivisions: UInt64 = 0
        var programMutations: UInt64 = 0
        var crossbreedings: UInt64 = 0
        var latestSample: ExperimentSample?
        var interventionSample: ExperimentSample?
        var recordedSamples: [ExperimentSample] = []
        var recordedEvents: [ExperimentEvent] = []
        var recordedComponentSnapshots: [ExperimentComponentSnapshot] = []
        var maximumObservedComponentDescentDepth: UInt32 = 0
        var maximumObservedLivingDescendants = 0
        var maximumObservedRegenerativeDescendants = 0
        var maximumObservedChallengedDescendants = 0
        var maximumObservedHomeostaticDescendants = 0
        var lastAccumulatedObservationStep: UInt64?
        var componentContributions: Set<ComponentContribution> = []
        var previousProgramRepresentations: [ProgramRepresentation] = []
        var selectionIntervals: [MultilevelSelectionInterval] = []
        var observedSelectionIntervalCount: UInt64 = 0
        var individualityObserver = IndividualityObserverEngine()
        var latestObserverResult: IndividualityObserverResult?
        var componentMorphologyArchive: [UInt32: MorphologyDescriptor] = [:]
        var componentMorphologyOrder: [UInt32] = []

        while totalSteps < configuration.steps {
            let remaining = configuration.steps - totalSteps
            let untilSample = nextSample > totalSteps ? nextSample - totalSteps : 1
            let untilIntervention: UInt64
            if let interventionStep = configuration.interventionStep,
               interventionStep > totalSteps {
                untilIntervention = interventionStep - totalSteps
            } else {
                untilIntervention = .max
            }
            let damageObservationStep = configuration.damageChallenge.interventionStep.map {
                $0 &+ 1
            }
            let untilDamageObservation: UInt64
            if let damageObservationStep, damageObservationStep > totalSteps {
                untilDamageObservation = damageObservationStep - totalSteps
            } else {
                untilDamageObservation = .max
            }
            let encodedStepCount = Int(min(
                UInt64(configuration.batchSize),
                min(
                    remaining,
                    min(untilSample, min(untilIntervention, untilDamageObservation))
                )
            ))
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                throw EvolutionRendererError.resourceAllocation("headless simulation batch")
            }
            commandBuffer.label = "Numi seeded experiment batch"
            var auditedInBatch = false
            for _ in 0..<encodedStepCount {
                let completedStep = totalSteps + 1
                let sampleBoundary = completedStep == nextSample ||
                    completedStep == configuration.steps ||
                    completedStep == configuration.interventionStep ||
                    completedStep == damageObservationStep
                let audit = completedStep.isMultiple(of: configuration.auditInterval) ||
                    sampleBoundary
                runSettings.mechanosensingGain = configuration.mechanosensing
                    .gain(forCompletedStep: completedStep)
                runSettings.resourceFlux = configuration.environmentalScaffold
                    .resourceFlux(forCompletedStep: completedStep)
                runSettings.barrierGain = configuration.environmentalScaffold
                    .barrierGain(forCompletedStep: completedStep)
                encodeSimulationStep(
                    into: commandBuffer,
                    settings: runSettings,
                    auditInvariants: audit
                )
                auditedInBatch = auditedInBatch || audit
                totalSteps = completedStep

                let epochPosition = Int(totalSteps % UInt64(Self.epochSteps))
                if configuration.damageChallenge.mode == .ambient &&
                    epochPosition == Self.damageStep {
                    encodeCheckpointAndDamage(
                        into: commandBuffer,
                        settings: runSettings,
                        applyDamage: generation >= 8 && generation.isMultiple(of: 8)
                    )
                }
                if epochPosition == 0 {
                    generation &+= 1
                }
                if let interventionStep = configuration.damageChallenge.interventionStep,
                   totalSteps == interventionStep,
                   configuration.damageChallenge.mode == .shamRegenerativeTarget ||
                    configuration.damageChallenge.mode == .targetedRegenerativeWound {
                    encodeQualificationTargetSelection(
                        into: commandBuffer,
                        settings: runSettings
                    )
                }
                if let interventionStep = configuration.damageChallenge.interventionStep,
                   totalSteps == interventionStep &+ 1,
                   configuration.damageChallenge.mode == .targetedRegenerativeWound {
                    encodeSelectedTargetDamage(
                        into: commandBuffer,
                        settings: runSettings
                    )
                }
                if totalSteps.isMultiple(of: configuration.quantumStride) {
                    encodeQuantumStep(into: commandBuffer, settings: runSettings)
                }
            }

            let periodicSampleBoundary = totalSteps == nextSample
            let interventionBoundary = totalSteps ==
                configuration.interventionStep
            let damageObservationBoundary = totalSteps == damageObservationStep
            let fullReadback = periodicSampleBoundary ||
                interventionBoundary || damageObservationBoundary ||
                totalSteps == configuration.steps
            if fullReadback {
                encodeHeadlessReadback(readback, into: commandBuffer, full: true)
            } else if auditedInBatch && configuration.strictInvariants {
                encodeHeadlessReadback(readback, into: commandBuffer, full: false)
            }
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            if let error = commandBuffer.error { throw error }

            let invariantWasReadBack = fullReadback ||
                (auditedInBatch && configuration.strictInvariants)
            var batchReport = invariantWasReadBack
                ? invariantReport(from: readback.invariantState)
                : nil
            if fullReadback {
                latestSample = try consumeHeadlessSample(
                    readback,
                    journal: journal,
                    startTime: startTime,
                    lastEventSequence: &lastEventSequence,
                    births: &births,
                    deaths: &deaths,
                    fissions: &fissions,
                    fusions: &fusions,
                    cellDivisions: &cellDivisions,
                    programMutations: &programMutations,
                    crossbreedings: &crossbreedings,
                    componentContributions: &componentContributions,
                    previousProgramRepresentations: &previousProgramRepresentations,
                    selectionIntervals: &selectionIntervals,
                    observedSelectionIntervalCount: &observedSelectionIntervalCount,
                    individualityObserver: &individualityObserver,
                    latestObserverResult: &latestObserverResult,
                    componentMorphologyArchive: &componentMorphologyArchive,
                    componentMorphologyOrder: &componentMorphologyOrder,
                    resultRetention: resultRetention,
                    recordedEvents: &recordedEvents,
                    recordedComponentSnapshots: &recordedComponentSnapshots
                )
                if let latestSample {
                    if resultRetention.contains(.samples) {
                        recordedSamples.append(latestSample)
                    }
                    maximumObservedComponentDescentDepth = max(
                        maximumObservedComponentDescentDepth,
                        latestSample.maximumComponentDescentDepth
                    )
                    maximumObservedLivingDescendants = max(
                        maximumObservedLivingDescendants,
                        latestSample.livingDescendants
                    )
                    maximumObservedRegenerativeDescendants = max(
                        maximumObservedRegenerativeDescendants,
                        latestSample.regenerativeDescendants
                    )
                    maximumObservedChallengedDescendants = max(
                        maximumObservedChallengedDescendants,
                        latestSample.challengedDescendants
                    )
                    maximumObservedHomeostaticDescendants = max(
                        maximumObservedHomeostaticDescendants,
                        latestSample.homeostaticDescendants
                    )
                    lastAccumulatedObservationStep = latestSample.step
                }
                if interventionBoundary {
                    interventionSample = latestSample
                }
                batchReport = latestSample?.invariantReport ?? batchReport
                if reportProgress {
                    print(
                        "experiment_step=\(totalSteps) components=" +
                        "\(latestSample?.physicalComponents ?? 0) cells=" +
                        "\(latestSample?.livingCells ?? 0) steps_per_second=" +
                        String(format: "%.1f", latestSample?.stepsPerSecond ?? 0) +
                        " invariants=0x\(String(batchReport?.flags ?? 0, radix: 16))"
                    )
                }
                if periodicSampleBoundary {
                    nextSample = min(
                        configuration.steps,
                        totalSteps &+ configuration.sampleInterval
                    )
                }
            }

            if configuration.strictInvariants,
               let flaggedReport = batchReport,
               flaggedReport.flags != 0 {
                var report = flaggedReport
                if !fullReadback {
                    guard let failureReadback = commandQueue.makeCommandBuffer() else {
                        throw EvolutionRendererError.resourceAllocation("invariant failure readback")
                    }
                    encodeHeadlessReadback(readback, into: failureReadback, full: true)
                    failureReadback.commit()
                    failureReadback.waitUntilCompleted()
                    if let error = failureReadback.error { throw error }
                    latestSample = try consumeHeadlessSample(
                        readback,
                        journal: journal,
                        startTime: startTime,
                        lastEventSequence: &lastEventSequence,
                        births: &births,
                        deaths: &deaths,
                        fissions: &fissions,
                        fusions: &fusions,
                        cellDivisions: &cellDivisions,
                        programMutations: &programMutations,
                        crossbreedings: &crossbreedings,
                        componentContributions: &componentContributions,
                        previousProgramRepresentations: &previousProgramRepresentations,
                        selectionIntervals: &selectionIntervals,
                        observedSelectionIntervalCount: &observedSelectionIntervalCount,
                        individualityObserver: &individualityObserver,
                        latestObserverResult: &latestObserverResult,
                        componentMorphologyArchive: &componentMorphologyArchive,
                        componentMorphologyOrder: &componentMorphologyOrder,
                        resultRetention: resultRetention,
                        recordedEvents: &recordedEvents,
                        recordedComponentSnapshots: &recordedComponentSnapshots
                    )
                    if let latestSample,
                       lastAccumulatedObservationStep != latestSample.step {
                        maximumObservedComponentDescentDepth = max(
                            maximumObservedComponentDescentDepth,
                            latestSample.maximumComponentDescentDepth
                        )
                        maximumObservedLivingDescendants = max(
                            maximumObservedLivingDescendants,
                            latestSample.livingDescendants
                        )
                        maximumObservedRegenerativeDescendants = max(
                            maximumObservedRegenerativeDescendants,
                            latestSample.regenerativeDescendants
                        )
                        maximumObservedChallengedDescendants = max(
                            maximumObservedChallengedDescendants,
                            latestSample.challengedDescendants
                        )
                        maximumObservedHomeostaticDescendants = max(
                            maximumObservedHomeostaticDescendants,
                            latestSample.homeostaticDescendants
                        )
                        lastAccumulatedObservationStep = latestSample.step
                    }
                    report = latestSample?.invariantReport ?? report
                }
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                let summary = ExperimentSummary(
                    completed: false,
                    step: totalSteps,
                    elapsedSeconds: elapsed,
                    meanStepsPerSecond: Double(totalSteps) / max(elapsed, 0.000_001),
                    births: births,
                    deaths: deaths,
                    fissions: fissions,
                    fusions: fusions,
                    cellDivisions: cellDivisions,
                    programMutations: programMutations,
                    crossbreedings: crossbreedings,
                    invariantReport: report,
                    individualityEvidence: individualityEvidence(
                        observerResult: latestObserverResult,
                        maximumComponentDescentDepth:
                            maximumObservedComponentDescentDepth,
                        livingSeparatedDescendantCount:
                            maximumObservedLivingDescendants,
                        selection: MultilevelPriceAnalysis.summarize(selectionIntervals),
                        invariantReport: report
                    ),
                    regenerativeReproductionEvidence:
                        RegenerativeReproductionAssessment.evaluate(
                            separatedDescendantCount: maximumObservedLivingDescendants,
                            regenerativeDescendantCount:
                                maximumObservedRegenerativeDescendants,
                            challengedDescendantCount:
                                maximumObservedChallengedDescendants,
                            homeostaticDescendantCount:
                                maximumObservedHomeostaticDescendants,
                            conservationValid: report.flags == 0 &&
                                report.maximumEnergyResidual <= 0.001
                        ),
                    finalSample: latestSample,
                    outputPath: journal.outputURL.path
                )
                try journal.append("summary", summary)
                throw HeadlessExperimentError.invariantViolation(
                    step: UInt64(report.firstFailureStep ?? UInt32(truncatingIfNeeded: totalSteps)),
                    names: report.names
                )
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let finalReport = latestSample?.invariantReport ??
            invariantReport(from: readback.invariantState)
        let summary = ExperimentSummary(
            completed: true,
            step: totalSteps,
            elapsedSeconds: elapsed,
            meanStepsPerSecond: Double(totalSteps) / max(elapsed, 0.000_001),
            births: births,
            deaths: deaths,
            fissions: fissions,
            fusions: fusions,
            cellDivisions: cellDivisions,
            programMutations: programMutations,
            crossbreedings: crossbreedings,
            invariantReport: finalReport,
            individualityEvidence: individualityEvidence(
                observerResult: latestObserverResult,
                maximumComponentDescentDepth:
                    maximumObservedComponentDescentDepth,
                livingSeparatedDescendantCount:
                    maximumObservedLivingDescendants,
                selection: MultilevelPriceAnalysis.summarize(selectionIntervals),
                invariantReport: finalReport
            ),
            regenerativeReproductionEvidence:
                RegenerativeReproductionAssessment.evaluate(
                    separatedDescendantCount: maximumObservedLivingDescendants,
                    regenerativeDescendantCount:
                        maximumObservedRegenerativeDescendants,
                    challengedDescendantCount:
                        maximumObservedChallengedDescendants,
                    homeostaticDescendantCount:
                        maximumObservedHomeostaticDescendants,
                    conservationValid: finalReport.flags == 0 &&
                        finalReport.maximumEnergyResidual <= 0.001
                ),
            finalSample: latestSample,
            outputPath: journal.outputURL.path
        )
        try journal.append("summary", summary)
        return HeadlessExperimentResult(
            summary: summary,
            interventionSample: interventionSample,
            samples: recordedSamples,
            events: recordedEvents,
            componentSnapshots: recordedComponentSnapshots
        )
    }

    private func makeHeadlessReadbackBuffers() throws -> HeadlessReadbackBuffers {
        if let headlessReadbackBuffers { return headlessReadbackBuffers }

        func sharedCopy(of source: MTLBuffer, label: String) throws -> MTLBuffer {
            guard let buffer = device.makeBuffer(
                length: source.length,
                options: .storageModeShared
            ) else {
                throw EvolutionRendererError.resourceAllocation(label)
            }
            buffer.label = label
            return buffer
        }
        let readback = try HeadlessReadbackBuffers(
            agentState: sharedCopy(of: agentState, label: "Experiment agent state"),
            agentOccupancy: sharedCopy(of: agentOccupancy, label: "Experiment agent occupancy"),
            cellAggregates: sharedCopy(of: cellAggregates, label: "Experiment tissue aggregates"),
            cellState: sharedCopy(of: cellState, label: "Experiment cell state"),
            cellOccupancy: sharedCopy(of: cellOccupancy, label: "Experiment cell occupancy"),
            cellIdentities: sharedCopy(of: cellIdentities, label: "Experiment cell identities"),
            heritablePrograms: sharedCopy(
                of: heritablePrograms,
                label: "Experiment heritable programs"
            ),
            programInteractions: sharedCopy(
                of: programInteractions,
                label: "Experiment cellular program interactions"
            ),
            developmentalGenomes: sharedCopy(
                of: developmentalGenomes,
                label: "Experiment developmental genomes"
            ),
            programSlots: sharedCopy(of: programSlots, label: "Experiment program slots"),
            identityCounters: sharedCopy(of: identityCounters, label: "Experiment identity counters"),
            lineageEvents: sharedCopy(of: lineageEvents, label: "Experiment lineage events"),
            energyAudit: sharedCopy(of: energyAudit, label: "Experiment energy audit"),
            invariantState: sharedCopy(of: invariantState, label: "Experiment invariant state"),
            qualificationTargetMeasurement: sharedCopy(
                of: qualificationTargetMeasurement,
                label: "Experiment regenerative qualification target"
            )
        )
        commandQueue.register([
            readback.agentState, readback.agentOccupancy, readback.cellAggregates,
            readback.cellState, readback.cellOccupancy, readback.cellIdentities,
            readback.heritablePrograms, readback.programInteractions,
            readback.developmentalGenomes, readback.programSlots,
            readback.identityCounters, readback.lineageEvents, readback.energyAudit,
            readback.invariantState, readback.qualificationTargetMeasurement
        ])
        headlessReadbackBuffers = readback
        return readback
    }

    private func encodeHeadlessReadback(
        _ readback: HeadlessReadbackBuffers,
        into commandBuffer: Metal4CommandBufferContext,
        full: Bool
    ) {
        if full, let measurementEncoder = commandBuffer.makeComputeCommandEncoder() {
            measurementEncoder.label = "Measure regenerative qualification target"
            var uniforms = makeUniforms(settings: settings)
            measurementEncoder.setComputePipelineState(measureQualificationTargetPipeline)
            measurementEncoder.setBuffer(agentState, offset: 0, index: 0)
            measurementEncoder.setBuffer(agentOccupancy, offset: 0, index: 1)
            measurementEncoder.setBuffer(cellAggregates, offset: 0, index: 2)
            measurementEncoder.setBuffer(qualificationTargetState, offset: 0, index: 3)
            measurementEncoder.setBuffer(cellState, offset: 0, index: 4)
            measurementEncoder.setBuffer(cellOccupancy, offset: 0, index: 5)
            measurementEncoder.setBuffer(cellIdentities, offset: 0, index: 6)
            measurementEncoder.setBuffer(
                qualificationTargetMeasurement, offset: 0, index: 7
            )
            measurementEncoder.setTexture(developmentalField, index: 0)
            measurementEncoder.setBytes(
                &uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 8
            )
            measurementEncoder.dispatchThreads(
                MTLSize(width: 1, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
            )
            measurementEncoder.endEncoding()
        }
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.label = full ? "Record headless experiment state" : "Check headless invariants"
        blit.copy(
            from: invariantState,
            sourceOffset: 0,
            to: readback.invariantState,
            destinationOffset: 0,
            size: invariantState.length
        )
        if full {
            let copies: [(MTLBuffer, MTLBuffer)] = [
                (agentState, readback.agentState),
                (agentOccupancy, readback.agentOccupancy),
                (cellAggregates, readback.cellAggregates),
                (cellState, readback.cellState),
                (cellOccupancy, readback.cellOccupancy),
                (cellIdentities, readback.cellIdentities),
                (heritablePrograms, readback.heritablePrograms),
                (programInteractions, readback.programInteractions),
                (developmentalGenomes, readback.developmentalGenomes),
                (programSlots, readback.programSlots),
                (identityCounters, readback.identityCounters),
                (lineageEvents, readback.lineageEvents),
                (energyAudit, readback.energyAudit),
                (qualificationTargetMeasurement, readback.qualificationTargetMeasurement)
            ]
            for (source, destination) in copies {
                blit.copy(
                    from: source,
                    sourceOffset: 0,
                    to: destination,
                    destinationOffset: 0,
                    size: source.length
                )
            }
        }
        blit.endEncoding()
    }

    private func invariantReport(from buffer: MTLBuffer) -> ExperimentInvariantReport {
        let values = buffer.contents().bindMemory(
            to: UInt32.self,
            capacity: Self.invariantStateCount
        )
        let flags = values[0]
        let definitions: [(UInt32, String)] = [
            (1 << 0, "nonzero_contact_momentum"),
            (1 << 1, "energy_drift"),
            (1 << 2, "stale_program_generation"),
            (1 << 3, "program_reference_count"),
            (1 << 4, "orphaned_junction"),
            (1 << 5, "invalid_membrane"),
            (1 << 6, "disconnected_ownership"),
            (1 << 7, "contact_pair_queue_overflow")
        ]
        return ExperimentInvariantReport(
            flags: flags,
            names: definitions.compactMap { flags & $0.0 == 0 ? nil : $0.1 },
            firstFailureStep: values[1] == UInt32.max ? nil : values[1] &+ 1,
            auditCount: values[2],
            contactMomentumViolations: values[3],
            energyDriftViolations: values[4],
            staleProgramViolations: values[5],
            referenceCountViolations: values[6],
            orphanedJunctionViolations: values[7],
            invalidMembraneViolations: values[8],
            disconnectedOwnershipViolations: values[9],
            maximumContactMomentumResidual: values[10],
            maximumEnergyResidual: Double(values[16]) / Self.energyAuditScale
        )
    }

    private func individualityEvidence(
        observerResult: IndividualityObserverResult?,
        maximumComponentDescentDepth: UInt32,
        livingSeparatedDescendantCount: Int,
        selection: SelectionPartition,
        invariantReport: ExperimentInvariantReport
    ) -> IndividualityEvidence {
        let conservationFailure = invariantReport.flags != 0 ||
            invariantReport.maximumEnergyResidual > 0.001
        let evolutionary = EvolutionaryEvidence.evaluate(
            selection: selection,
            maximumComponentDescentDepth: maximumComponentDescentDepth,
            livingSeparatedDescendantCount: livingSeparatedDescendantCount,
            conservationValid: !conservationFailure
        )
        let collectiveSupport = selection.covarianceSampleCount >= 8 &&
            (selection.betweenComponentConfidence?.lower ?? -.infinity) > 0 &&
            (selection.collectiveHeritability?.lower ?? -.infinity) > 0
        let collectiveClaim = EvidenceClaim(
            state: conservationFailure ? .notSupported :
                (collectiveSupport ? .supported : .inconclusive),
            estimate: selection.betweenComponentConfidence,
            nullUpperBound: 0,
            reason: conservationFailure
                ? "Invariant or energy-conservation failure invalidates collective inference."
                : collectiveSupport
                    ? "Between-component Price covariance and parent-descendant collective resemblance have positive 95% bootstrap intervals."
                    : "Collective support requires at least eight transmitted parent components plus positive 95% intervals for between-component covariance and collective resemblance.",
            timeBasis: .accumulatedHistory
        )
        return IndividualityEvidence(
            endogenousPredictability: observerResult?.endogenousPredictabilityClaim ??
                IndividualityEvidence.inconclusive.endogenousPredictability,
            mechanochemicalAutonomy: observerResult?.autonomyClaim ??
                IndividualityEvidence.inconclusive.mechanochemicalAutonomy,
            physicalDescent: evolutionary.physicalDescent,
            heritableVariation: evolutionary.heritableVariation,
            differentialTransmission: evolutionary.differentialTransmission,
            darwinianEvolution: evolutionary.darwinianEvolution,
            collectiveLevelIndividuality: collectiveClaim,
            selection: selection,
            autocorrelationTime: observerResult?.autocorrelationTime ?? 0,
            observationWindows: observerResult?.observationWindows ?? 0
        )
    }

    private func consumeHeadlessSample(
        _ readback: HeadlessReadbackBuffers,
        journal: ExperimentJournal,
        startTime: CFAbsoluteTime,
        lastEventSequence: inout UInt32,
        births: inout UInt64,
        deaths: inout UInt64,
        fissions: inout UInt64,
        fusions: inout UInt64,
        cellDivisions: inout UInt64,
        programMutations: inout UInt64,
        crossbreedings: inout UInt64,
        componentContributions: inout Set<ComponentContribution>,
        previousProgramRepresentations: inout [ProgramRepresentation],
        selectionIntervals: inout [MultilevelSelectionInterval],
        observedSelectionIntervalCount: inout UInt64,
        individualityObserver: inout IndividualityObserverEngine,
        latestObserverResult: inout IndividualityObserverResult?,
        componentMorphologyArchive: inout [UInt32: MorphologyDescriptor],
        componentMorphologyOrder: inout [UInt32],
        resultRetention: HeadlessResultRetention,
        recordedEvents: inout [ExperimentEvent],
        recordedComponentSnapshots: inout [ExperimentComponentSnapshot]
    ) throws -> ExperimentSample {
        let counters = readback.identityCounters.contents().bindMemory(
            to: UInt32.self,
            capacity: Self.identityCounterCount
        )
        let writeSequence = counters[2]
        guard writeSequence >= lastEventSequence else {
            throw HeadlessExperimentError.output("Lineage event sequence moved backwards.")
        }
        let unreadEventCount = writeSequence - lastEventSequence
        guard unreadEventCount <= UInt32(Self.lineageEventCapacity) else {
            throw HeadlessExperimentError.output(
                "Lineage event ring overflow: \(unreadEventCount) unread records exceed " +
                "capacity \(Self.lineageEventCapacity). Reduce --sample-every."
            )
        }
        let records = readback.lineageEvents.contents().bindMemory(
            to: LineageEventRecord.self,
            capacity: Self.lineageEventCapacity
        )
        if writeSequence > lastEventSequence {
            for sequence in (lastEventSequence + 1)...writeSequence {
                let record = records[Int((sequence - 1) % UInt32(Self.lineageEventCapacity))]
                guard record.sequence == sequence,
                      let kind = RecordedLineageEvent.Kind(rawValue: record.kind) else {
                    throw HeadlessExperimentError.output(
                        "Missing lineage record for sequence \(sequence)."
                    )
                }
                let type: String
                switch kind {
                case .birth:
                    births &+= 1
                    if record.parentBirthID == UInt32.max {
                        type = "birth"
                    } else {
                        fissions &+= 1
                        type = "fission"
                        componentContributions.insert(ComponentContribution(
                            descendantID: UInt64(record.birthID),
                            contributorID: UInt64(record.parentBirthID)
                        ))
                    }
                case .death:
                    deaths &+= 1
                    type = "death"
                case .fusion:
                    fusions &+= 1
                    type = "fusion"
                    componentContributions.insert(ComponentContribution(
                        descendantID: UInt64(record.birthID),
                        contributorID: UInt64(record.parentBirthID)
                    ))
                case .cellDivision:
                    cellDivisions &+= 1
                    type = "cell_division"
                case .programMutation:
                    programMutations &+= 1
                    type = "program_mutation"
                case .crossbreeding:
                    crossbreedings &+= 1
                    type = "crossbreeding"
                }
                let event = ExperimentEvent(
                    sequence: sequence,
                    type: type,
                    step: record.step,
                    birthID: record.birthID,
                    parentBirthID: record.parentBirthID == UInt32.max
                        ? nil : record.parentBirthID,
                    generation: record.generation,
                    programID: permanentProgramID(
                        index: record.programAncestry.x,
                        generation: record.programAncestry.y
                    ),
                    parentProgramID: record.programAncestry.z <
                        UInt32(Self.maxHeritableProgramCount)
                        ? permanentProgramID(
                            index: record.programAncestry.z,
                            generation: record.programAncestry.w
                        ) : nil,
                    genomeHash: record.genomeHash,
                    topologyHash: record.topologyHash,
                    mutationDistance: record.mutationDistance,
                    resonanceFrequency: record.resonanceFrequency,
                    energy: record.energy,
                    morphology: [
                        record.morphology.x, record.morphology.y,
                        record.morphology.z, record.morphology.w
                    ]
                )
                if resultRetention.contains(.events) {
                    recordedEvents.append(event)
                }
                try journal.append("event", event)
            }
            lastEventSequence = writeSequence
        }

        let occupancy = readback.agentOccupancy.contents().bindMemory(
            to: UInt32.self,
            capacity: Self.maxAgentCount
        )
        let agents = readback.agentState.contents().bindMemory(
            to: AgentState.self,
            capacity: Self.maxAgentCount
        )
        let aggregates = readback.cellAggregates.contents().bindMemory(
            to: CellAggregate.self,
            capacity: Self.maxAgentCount
        )
        let qualificationMeasurement = readback.qualificationTargetMeasurement.contents()
            .bindMemory(to: QualificationTargetMeasurement.self, capacity: 1).pointee
        let qualificationOwner = Int(qualificationMeasurement.identity.x)
        let qualificationTargetPresent = qualificationOwner >= 0 &&
            qualificationOwner < Self.maxAgentCount && occupancy[qualificationOwner] == 1
        let qualificationAggregate: CellAggregate? = qualificationTargetPresent
            ? aggregates[qualificationOwner] : nil
        let qualificationFlags = qualificationTargetPresent
            ? qualificationMeasurement.identity.w : 0
        let living = (0..<Self.maxAgentCount).filter { occupancy[$0] == 1 }
        let descendants = living.filter { agents[$0].generation > 0 }
        let regenerativeDescendants = descendants.filter {
            agents[$0].componentFlags & 2 != 0
        }
        let challengedDescendants = descendants.filter {
            agents[$0].componentFlags & 8 != 0
        }
        let homeostaticDescendants = descendants.filter {
            agents[$0].componentFlags & 4 != 0
        }
        let maximumComponentDescentDepth = living.map { agents[$0].generation }.max() ?? 0
        let maximumProgramReplicationGeneration = living.map {
            agents[$0].programReplicationGeneration
        }.max() ?? 0
        let livingCellCount = living.reduce(0) {
            $0 + max(Int(aggregates[$1].physiology.x.rounded()), 0)
        }
        let inverseOrganisms = 1.0 / Double(max(living.count, 1))
        let inverseCells = 1.0 / Double(max(livingCellCount, 1))
        let meanCells = Double(livingCellCount) * inverseOrganisms
        let largestTissueCellCount = living.reduce(into: 0) { largest, index in
            largest = max(largest, max(Int(aggregates[index].physiology.x.rounded()), 0))
        }
        let descendantCellCount = descendants.reduce(0) {
            $0 + max(Int(aggregates[$1].physiology.x.rounded()), 0)
        }
        let largestDescendantTissueCellCount = descendants.reduce(into: 0) {
            largest, index in
            largest = max(largest, max(Int(aggregates[index].physiology.x.rounded()), 0))
        }
        let meanRadius = living.reduce(0.0) {
            $0 + Double(max(aggregates[$1].morphology.z, 0))
        } * inverseOrganisms
        let meanShape = living.reduce(0.0) {
            $0 + Double(max(aggregates[$1].shape.z, 0))
        } * inverseOrganisms
        let meanElongation = living.reduce(0.0) {
            $0 + Double(max(aggregates[$1].geometryBoundary.z, 0))
        } * inverseOrganisms
        let meanExposedMembrane = living.reduce(0.0) {
            $0 + Double(max(aggregates[$1].geometryBoundary.w, 0))
        } * inverseOrganisms
        let trophicGain = living.reduce(0.0) {
            $0 + Double(max(aggregates[$1].trophic.y, 0))
        }
        let trophicLoss = living.reduce(0.0) {
            $0 + Double(max(aggregates[$1].trophic.z, 0))
        }
        func cellWeightedMean(_ value: (CellAggregate) -> Float) -> Double {
            living.reduce(0.0) { total, index in
                let aggregate = aggregates[index]
                let cellCount = Double(max(aggregate.physiology.x, 0))
                return total + Double(value(aggregate)) * cellCount
            } * inverseCells
        }
        let inverseDescendantCells = 1.0 / Double(max(descendantCellCount, 1))
        func descendantCellWeightedMean(_ value: (CellAggregate) -> Float) -> Double {
            descendants.reduce(0.0) { total, index in
                let aggregate = aggregates[index]
                let cellCount = Double(max(aggregate.physiology.x, 0))
                return total + Double(value(aggregate)) * cellCount
            } * inverseDescendantCells
        }

        let slots = readback.programSlots.contents().bindMemory(
            to: ProgramSlotState.self,
            capacity: Self.maxHeritableProgramCount
        )
        let developmental = readback.developmentalGenomes.contents().bindMemory(
            to: DevelopmentalGenome.self,
            capacity: Self.maxHeritableProgramCount
        )
        let programRecords = readback.heritablePrograms.contents().bindMemory(
            to: HeritableProgram.self,
            capacity: Self.maxHeritableProgramCount
        )
        let cellOccupancyValues = readback.cellOccupancy.contents().bindMemory(
            to: UInt32.self,
            capacity: Self.maxCellCount
        )
        let cells = readback.cellState.contents().bindMemory(
            to: CellState.self,
            capacity: Self.maxCellCount
        )
        let cellIdentities = readback.cellIdentities.contents().bindMemory(
            to: CellIdentity.self,
            capacity: Self.maxCellCount
        )
        let interactions = readback.programInteractions.contents().bindMemory(
            to: SIMD4<Float>.self,
            capacity: Self.maxCellCount
        )
        func mechanochemicalTrait(programIndex: Int) -> Double {
            let developmentalProgram = developmental[programIndex]
            let gains = [
                developmentalProgram.mechanochemistryA.x,
                developmentalProgram.mechanochemistryA.y,
                developmentalProgram.mechanochemistryA.z,
                developmentalProgram.mechanochemistryB.y
            ].map { value -> Double in
                let magnitude = Double(abs(value))
                return magnitude / (1 + magnitude)
            }
            return gains.contains(0) ? 0 : pow(gains.reduce(1, *), 0.25)
        }
        func coordinatedTractionStrain(_ aggregate: CellAggregate) -> Float {
            let cellCount = max(aggregate.physiology.x, 1)
            let forceCoherence = min(max(
                simd_length(SIMD2<Float>(aggregate.tissueMotion.x, aggregate.tissueMotion.y)) /
                    max(aggregate.tissueMotion.w * cellCount, 0.0000001),
                0
            ), 1)
            return max(aggregate.mechanics.x, 0) * forceCoherence
        }
        func morphologyDescriptor(owner: Int) -> MorphologyDescriptor {
            let aggregate = aggregates[owner]
            return MorphologyDescriptor(values: [
                Double(aggregate.physiology.x / 24),
                Double(aggregate.morphology.z / 0.86),
                Double((aggregate.shape.z - 1) / 2.5),
                Double(aggregate.morphology.w),
                Double((aggregate.resonance.z - 0.0008) / 0.0082),
                Double(aggregate.resonance.y * 18),
                Double(aggregate.dynamics.y),
                Double(aggregate.mechanics.y)
            ])
        }
        func collectiveTrait(owner: Int) -> Double {
            let aggregate = aggregates[owner]
            return pow(Double(max(
                aggregate.signalCausality.x * aggregate.signalCausality.y *
                aggregate.signalCausality.z * coordinatedTractionStrain(aggregate),
                0
            )), 0.25)
        }

        if resultRetention.contains(.componentSnapshots) {
            for owner in living {
                let agent = agents[owner]
                let aggregate = aggregates[owner]
                recordedComponentSnapshots.append(ExperimentComponentSnapshot(
                    step: totalSteps,
                    birthID: agent.birthID,
                    parentBirthID: agent.parentBirthID == .max ? nil : agent.parentBirthID,
                    generation: agent.generation,
                    cellCount: max(Int(aggregate.physiology.x.rounded()), 0),
                    atp: Double(max(aggregate.physiology.y, 0)),
                    integrity: Double(max(aggregate.physiology.z, 0)),
                    stress: Double(max(aggregate.physiology.w, 0)),
                    shapeIndex: Double(max(aggregate.shape.z, 0)),
                    regeneratedDevelopment: agent.componentFlags & 2 != 0,
                    challenged: agent.componentFlags & 8 != 0,
                    homeostatic: agent.componentFlags & 4 != 0,
                    morphology: morphologyDescriptor(owner: owner).values
                ))
            }
        }

        var observerCandidates: [IndividualityCandidate] = []
        observerCandidates.reserveCapacity(living.count + livingCellCount)
        let componentAutonomyVectors = living.map { owner -> AutonomyVector in
            let aggregate = aggregates[owner]
            let currentMorphology = morphologyDescriptor(owner: owner)
            let parentResemblance: Double
            if agents[owner].parentBirthID != .max,
               let parentMorphology = componentMorphologyArchive[
                agents[owner].parentBirthID
               ] {
                let morphologyResemblance = exp(
                    -4 * currentMorphology.distance(to: parentMorphology)
                )
                let programResemblance = exp(-Double(max(agents[owner].mutationDistance, 0)))
                parentResemblance = sqrt(morphologyResemblance * programResemblance)
            } else {
                parentResemblance = 0
            }
            let observation = ComponentObservation(
                    step: totalSteps,
                    candidateID: UInt64(agents[owner].birthID),
                    partitionLevel: .membraneConnectedComponent,
                    cellCount: max(Int(aggregate.physiology.x.rounded()), 1),
                    harvestedATP: Double(max(aggregate.energetics.x, 0)),
                    importedATP: Double(max(aggregate.programEcology.x, 0)),
                    repairFlux: Double(max(aggregate.causality.w, 0)),
                    membraneIntegrity: Double(max(aggregate.physiology.z, 0)),
                    exposedPerimeter: Double(max(aggregate.geometryBoundary.w, 0)),
                    damageFlux: Double(max(aggregate.trophic.z, 0)),
                    membraneTurnover: Double(max(aggregate.energetics.w, 0)),
                    strainToCalcium: Double(max(aggregate.signalCausality.x, 0)),
                    calciumToERK: Double(max(aggregate.signalCausality.y, 0)),
                    erkToTraction: Double(max(aggregate.signalCausality.z, 0)),
                    tractionToStrain: Double(coordinatedTractionStrain(aggregate)),
                    junctionTransmission: Double(max(aggregate.development.w, 0)),
                    atpSharing: Double(max(aggregate.programEcology.x, 0)),
                    rejection: Double(max(aggregate.programEcology.y, 0)),
                    withinComponentReplicationAdvantage: Double(max(
                        aggregate.programEcology.w, 0
                    )),
                    descendantRepresentation: agents[owner].generation > 0 ? 1 : 0,
                    parentResemblance: parentResemblance
                )
            observerCandidates.append(IndividualityCandidate(
                observation: observation,
                positionX: Double(agents[owner].position.x),
                positionY: Double(agents[owner].position.y),
                isSeparatedDescendant: agents[owner].generation > 0,
                environmentalDependence: Double(
                    abs(aggregate.environment.x) + abs(aggregate.environment.y) +
                    (1 - min(max(aggregate.environment.w, 0), 1))
                ),
                parentComponentID: nil
            ))
            return AutonomyVector.measured(
                from: observation,
                conditionalSelfPredictiveInformation: 0
            )
        }
        var cellAutonomyVectors: [AutonomyVector] = []
        var representationCounts: [ComponentProgramKey: ProgramRepresentationAccumulator] = [:]
        cellAutonomyVectors.reserveCapacity(livingCellCount)
        for cellIndex in 0..<Self.maxCellCount where cellOccupancyValues[cellIndex] == 1 {
            let identity = cellIdentities[cellIndex]
            let owner = Int(identity.owner)
            let programIndex = Int(identity.programIndex)
            guard owner < Self.maxAgentCount,
                  occupancy[owner] == 1,
                  programIndex < Self.maxHeritableProgramCount,
                  slots[programIndex].occupied == 1,
                  slots[programIndex].generation == identity.programGeneration else { continue }
            let cell = cells[cellIndex]
            let interaction = interactions[cellIndex]
            let exposedPerimeter = max(cell.membrane.y, 0) *
                min(max(cell.tissueGeometry.z, 0), 1)
            let cellObservation = ComponentObservation(
                    step: totalSteps,
                    candidateID: UInt64(identity.persistentID),
                    partitionLevel: .cell,
                    cellCount: 1,
                    harvestedATP: Double(max(cell.energetics.x, 0)),
                    importedATP: Double(abs(interaction.x)),
                    repairFlux: Double(max(cell.regulation.w * cell.energetics.y, 0)),
                    membraneIntegrity: Double(min(max(cell.physiology.w, 0), 1)),
                    exposedPerimeter: Double(exposedPerimeter),
                    damageFlux: Double(max(cell.tissueForce.z, 0)),
                    membraneTurnover: Double(max(cell.regulationB.x * cell.energetics.y, 0)),
                    strainToCalcium: Double(max(cell.signalCausality.x, 0)),
                    calciumToERK: Double(max(cell.signalCausality.y, 0)),
                    erkToTraction: Double(max(cell.signalCausality.z, 0)),
                    tractionToStrain: Double(max(cell.mechanics.x * cell.mechanics.y, 0)),
                    junctionTransmission: Double(max(cell.development.w, 0)),
                    atpSharing: Double(abs(interaction.x)),
                    rejection: Double(max(interaction.y, 0)),
                    withinComponentReplicationAdvantage: Double(max(interaction.w, 0)),
                    descendantRepresentation: 0,
                    parentResemblance: 0
                )
            observerCandidates.append(IndividualityCandidate(
                observation: cellObservation,
                positionX: Double(cell.position.x),
                positionY: Double(cell.position.y),
                isSeparatedDescendant: agents[owner].generation > 0,
                environmentalDependence: Double(
                    abs(cell.environment.x) + abs(cell.environment.y) +
                    (1 - min(max(cell.environment.w, 0), 1))
                ),
                parentComponentID: UInt64(agents[owner].birthID)
            ))
            cellAutonomyVectors.append(AutonomyVector.measured(
                from: cellObservation,
                conditionalSelfPredictiveInformation: 0
            ))

            let program = programRecords[programIndex]
            let programID = permanentProgramID(
                index: identity.programIndex,
                generation: identity.programGeneration
            )
            let key = ComponentProgramKey(
                componentID: UInt64(agents[owner].birthID),
                programID: programID
            )
            var accumulator = representationCounts[key] ?? ProgramRepresentationAccumulator(
                parentProgramID: program.parentProgramIndex <
                    UInt32(Self.maxHeritableProgramCount)
                    ? permanentProgramID(
                        index: program.parentProgramIndex,
                        generation: program.parentProgramGeneration
                    ) : nil,
                cellCount: 0,
                inheritedTrait: mechanochemicalTrait(programIndex: programIndex),
                collectiveTrait: collectiveTrait(owner: owner)
            )
            accumulator.cellCount += 1
            representationCounts[key] = accumulator
        }
        if let observerResult = individualityObserver.observe(
            observerCandidates,
            evaluationStride: 1,
            resamples: 48
        ) {
            latestObserverResult = observerResult
        }
        for owner in living {
            let birthID = agents[owner].birthID
            if componentMorphologyArchive[birthID] == nil {
                componentMorphologyOrder.append(birthID)
            }
            componentMorphologyArchive[birthID] = morphologyDescriptor(owner: owner)
        }
        let morphologyArchiveCapacity = 8_192
        if componentMorphologyOrder.count > morphologyArchiveCapacity {
            let excess = componentMorphologyOrder.count - morphologyArchiveCapacity
            for birthID in componentMorphologyOrder.prefix(excess) {
                componentMorphologyArchive.removeValue(forKey: birthID)
            }
            componentMorphologyOrder.removeFirst(excess)
        }
        let currentProgramRepresentations = representationCounts.map { key, value in
            ProgramRepresentation(
                componentID: key.componentID,
                programID: key.programID,
                parentProgramID: value.parentProgramID,
                cellCount: value.cellCount,
                inheritedTrait: value.inheritedTrait,
                collectiveTrait: value.collectiveTrait
            )
        }.sorted {
            ($0.componentID, $0.programID) < ($1.componentID, $1.programID)
        }
        let selectionInterval: MultilevelSelectionInterval?
        if previousProgramRepresentations.isEmpty {
            selectionInterval = nil
        } else {
            let interval = MultilevelPriceAnalysis.interval(
                parent: previousProgramRepresentations,
                descendant: currentProgramRepresentations,
                contributions: componentContributions
            )
            retainSelectionInterval(
                interval,
                history: &selectionIntervals,
                observedCount: &observedSelectionIntervalCount
            )
            selectionInterval = interval
        }
        previousProgramRepresentations = currentProgramRepresentations
        componentContributions.removeAll(keepingCapacity: true)
        let maximumDetachmentScore = living.map {
            Double(max(aggregates[$0].trophic.w, 0))
        }.max() ?? 0
        var detachmentThresholdTotal = 0.0
        var effectiveDetachmentThresholdTotal = 0.0
        var propaguleInvestmentTotal = 0.0
        var inheritedReproductionSamples = 0
        for index in living {
            let programIndex = Int(agents[index].dominantProgramIndex)
            guard programIndex < Self.maxHeritableProgramCount,
                  slots[programIndex].occupied == 1,
                  slots[programIndex].generation ==
                    agents[index].dominantProgramGeneration else { continue }
            let reproduction = developmental[programIndex].mechanochemistryB
            detachmentThresholdTotal += Double(reproduction.z)
            effectiveDetachmentThresholdTotal += Double(
                reproduction.z * (1.18 - 0.46 * agents[index].social.w)
            )
            propaguleInvestmentTotal += Double(reproduction.w)
            inheritedReproductionSamples += 1
        }
        let inverseReproductionSamples = 1.0 / Double(max(inheritedReproductionSamples, 1))
        let recycledProgramClaims = (0..<Self.maxHeritableProgramCount).reduce(UInt64(0)) {
            $0 + UInt64(slots[$1].generation > 1 ? slots[$1].generation - 1 : 0)
        }
        let invariant = invariantReport(from: readback.invariantState)
        let activeJunctions = readback.invariantState.contents()
            .bindMemory(to: UInt32.self, capacity: Self.invariantStateCount)[11]
        let fixedJunctionLoad = readback.invariantState.contents()
            .bindMemory(to: UInt32.self, capacity: Self.invariantStateCount)[12]
        let invariantValues = readback.invariantState.contents()
            .bindMemory(to: UInt32.self, capacity: Self.invariantStateCount)
        let audit = readback.energyAudit.contents().bindMemory(
            to: Int32.self,
            capacity: Self.energyAuditChannelCount
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let sample = ExperimentSample(
            step: totalSteps,
            generation: generation,
            elapsedSeconds: elapsed,
            stepsPerSecond: Double(totalSteps) / max(elapsed, 0.000_001),
            physicalComponents: living.count,
            livingCells: livingCellCount,
            maximumComponentDescentDepth: maximumComponentDescentDepth,
            maximumProgramReplicationGeneration: maximumProgramReplicationGeneration,
            largestTissueCellCount: largestTissueCellCount,
            livingDescendants: descendants.count,
            regenerativeDescendants: regenerativeDescendants.count,
            challengedDescendants: challengedDescendants.count,
            homeostaticDescendants: homeostaticDescendants.count,
            qualificationTargetPresent: qualificationTargetPresent,
            qualificationTargetBirthID: qualificationTargetPresent
                ? qualificationMeasurement.identity.y : nil,
            qualificationTargetCellCount: qualificationTargetPresent
                ? Int(qualificationMeasurement.identity.z) : 0,
            qualificationTargetATP: Double(qualificationAggregate?.physiology.y ?? 0),
            qualificationTargetIntegrity: Double(
                qualificationAggregate?.physiology.z ?? 0
            ),
            qualificationTargetStress: Double(qualificationAggregate?.physiology.w ?? 0),
            qualificationTargetShapeIndex: Double(qualificationAggregate?.shape.z ?? 0),
            qualificationTargetMatrix: qualificationTargetPresent
                ? Double(qualificationMeasurement.developmental.z) : 0,
            qualificationTargetWoundCue: qualificationTargetPresent
                ? Double(qualificationMeasurement.developmental.w) : 0,
            qualificationTargetChallenged: qualificationFlags & 8 != 0,
            qualificationTargetHomeostatic: qualificationFlags & 4 != 0,
            descendantCellCount: descendantCellCount,
            largestDescendantTissueCellCount: largestDescendantTissueCellCount,
            meanDescendantCellATP: descendantCellWeightedMean { $0.physiology.y },
            meanDescendantCellBiomass: descendantCellWeightedMean { $0.morphology.x },
            meanDescendantCellCycleState: descendantCellWeightedMean { $0.morphology.y },
            meanDescendantCellIntegrity: descendantCellWeightedMean { $0.physiology.z },
            meanDescendantCellStress: descendantCellWeightedMean { $0.physiology.w },
            descendantDividingCellFraction: descendantCellWeightedMean { $0.morphology.w },
            meanDescendantCycleDrive: descendantCellWeightedMean { $0.causality.y },
            meanDescendantContactBrake: descendantCellWeightedMean { $0.causality.z },
            births: births,
            deaths: deaths,
            fissions: fissions,
            fusions: fusions,
            cellDivisions: cellDivisions,
            programMutations: programMutations,
            crossbreedings: crossbreedings,
            crossComponentContactSamples: counters[5],
            membraneBreachSamples: counters[6],
            resistedAttackSamples: counters[7],
            trophicTransferSamples: counters[8],
            transferredEnergy: Double(counters[9]) / Self.energyAuditScale,
            deflectedAttackImpulse: Double(counters[10]) / Self.energyAuditScale,
            fusionContactSamples: counters[11],
            successfulFusionContactSamples: counters[12],
            fusionEligibleContactSamples: counters[16],
            maximumFusionDrive: Double(counters[17]) / 1_000_000,
            distinctProgramSuccessfulFusionSamples: counters[18],
            crossbreedingCandidateDivisions: counters[13],
            crossbreedingStochasticAttempts: counters[14],
            maximumCrossbreedingScore: Double(counters[15]) / 1_000_000,
            resolvedIndividuals: latestObserverResult?.resolvedIndividuals.count ?? 0,
            resolvedCellIndividuals: latestObserverResult?.resolvedCellCount ?? 0,
            resolvedCollectiveIndividuals:
                latestObserverResult?.resolvedCollectiveCount ?? 0,
            observerAutocorrelationTime:
                latestObserverResult?.autocorrelationTime ?? 0,
            observerWindows: latestObserverResult?.observationWindows ?? 0,
            activePrograms: invariantValues[14],
            livingProgramReferences: invariantValues[15],
            recycledProgramClaims: recycledProgramClaims,
            activeJunctions: activeJunctions,
            meanJunctionLoad: activeJunctions > 0
                ? Double(fixedJunctionLoad) / Self.energyAuditScale / Double(activeJunctions)
                : 0,
            trophicGain: trophicGain,
            trophicLoss: trophicLoss,
            energyResidual: Double(audit[9]) / Self.energyAuditScale,
            cellularEnergyHarvest: living.reduce(0.0) {
                $0 + Double(max(aggregates[$1].energetics.x, 0))
            },
            cellularMaintenance: living.reduce(0.0) {
                $0 + Double(max(aggregates[$1].energetics.y, 0))
            },
            cellularActiveWork: living.reduce(0.0) {
                $0 + Double(max(aggregates[$1].energetics.z, 0))
            },
            cellularDissipation: living.reduce(0.0) {
                $0 + Double(max(aggregates[$1].energetics.w, 0))
            },
            meanCellsPerComponent: meanCells,
            meanTissueRadius: meanRadius,
            meanShapeIndex: meanShape,
            meanElongation: meanElongation,
            meanExposedMembraneLength: meanExposedMembrane,
            meanCellATP: cellWeightedMean { $0.physiology.y },
            meanCellIntegrity: cellWeightedMean { $0.physiology.z },
            meanCellStress: cellWeightedMean { $0.physiology.w },
            meanMembraneVoltage: cellWeightedMean { $0.dynamics.x },
            meanCalciumActivity: cellWeightedMean { $0.signaling.x },
            meanERKActivity: cellWeightedMean { $0.signaling.y },
            dividingCellFraction: cellWeightedMean { $0.morphology.w },
            meanCellTraction: cellWeightedMean { $0.tissueMotion.w },
            maximumDetachmentScore: maximumDetachmentScore,
            meanInheritedDetachmentThreshold:
                detachmentThresholdTotal * inverseReproductionSamples,
            meanEffectiveDetachmentThreshold:
                effectiveDetachmentThresholdTotal * inverseReproductionSamples,
            meanPropaguleInvestment:
                propaguleInvestmentTotal * inverseReproductionSamples,
            meanFrequencyMatch: cellWeightedMean { $0.environment.w },
            meanMorphogenActivator: cellWeightedMean { $0.development.x },
            meanMorphogenInhibitor: cellWeightedMean { $0.development.y },
            meanDevelopmentalFateMemory: cellWeightedMean { $0.development.z },
            meanJunctionMorphogenTransport: cellWeightedMean { $0.development.w },
            meanMorphogenDifferentiation: cellWeightedMean {
                $0.developmentCausality.x
            },
            meanDevelopmentalPolarityCoherence: cellWeightedMean {
                $0.developmentCausality.y
            },
            meanMorphogenSynthesisRate: cellWeightedMean {
                $0.developmentCausality.z
            },
            meanMorphogenTransportWork: cellWeightedMean {
                $0.developmentCausality.w
            },
            meanEnergeticIndependence: cellWeightedMean {
                let supply = max($0.energetics.x, 0)
                return supply / max(supply + max($0.energetics.y, 0) +
                    max($0.energetics.z, 0) + max($0.energetics.w, 0), 0.0000001)
            },
            meanBoundaryMaintenance: cellWeightedMean {
                let maintained = max($0.regulation.w, 0) * max($0.physiology.z, 0) *
                    max($0.geometryBoundary.w, 0)
                return maintained / max(maintained + max($0.trophic.z, 0) +
                    max($0.mechanics.z, 0), 0.0000001)
            },
            meanMechanochemicalClosure: cellWeightedMean {
                pow(max($0.signalCausality.x * $0.signalCausality.y *
                    $0.signalCausality.z * coordinatedTractionStrain($0), 0), 0.25)
            },
            meanProgramCooperation: cellWeightedMean {
                max($0.programEcology.x, 0) + max($0.programEcology.y, 0)
            },
            meanProgramConflict: cellWeightedMean {
                max(-$0.programEcology.x, 0) + max($0.programEcology.w, 0)
            },
            componentAutonomyDistribution: AutonomyDistribution(
                vectors: componentAutonomyVectors
            ),
            cellAutonomyDistribution: AutonomyDistribution(vectors: cellAutonomyVectors),
            selectionInterval: selectionInterval,
            invariantReport: invariant
        )
        try journal.append("sample", sample)
        return sample
    }

    private func retainSelectionInterval(
        _ interval: MultilevelSelectionInterval,
        history: inout [MultilevelSelectionInterval],
        observedCount: inout UInt64
    ) {
        let selectionHistoryCapacity = 4_096
        observedCount &+= 1
        guard history.count >= selectionHistoryCapacity else {
            history.append(interval)
            return
        }

        var random = observedCount &+ 0x9E37_79B9_7F4A_7C15
        random = (random ^ (random >> 30)) &* 0xBF58_476D_1CE4_E5B9
        random = (random ^ (random >> 27)) &* 0x94D0_49BB_1331_11EB
        random ^= random >> 31
        let replacement = Int(random % observedCount)
        if replacement < selectionHistoryCapacity {
            history[replacement] = interval
        }
    }
}

private struct PostProcessUniforms {
    var sourceSize: SIMD2<Float>
    var exposure: Float
    var bloomIntensity: Float
    var observationZoom: Float
    var frameIndex: UInt32
}

private final class RenderTargetSet {
    let size: MTLSize
    let heap: any MTLHeap
    let residencySet: MTLResidencySet
    let sceneColor: MTLTexture
    let bloomTexture: MTLTexture

    init(
        size: MTLSize,
        heap: any MTLHeap,
        residencySet: MTLResidencySet,
        sceneColor: MTLTexture,
        bloomTexture: MTLTexture
    ) {
        self.size = size
        self.heap = heap
        self.residencySet = residencySet
        self.sceneColor = sceneColor
        self.bloomTexture = bloomTexture
    }
}

private final class RenderSubmissionResources {
    let visibleCellIndices: MTLBuffer
    let cellDrawArguments: MTLBuffer
    let cellMeshDrawArguments: MTLBuffer
    let visibleJunctionIndices: MTLBuffer
    let junctionDrawArguments: MTLBuffer
    var renderTargets: RenderTargetSet?

    init(
        visibleCellIndices: MTLBuffer,
        cellDrawArguments: MTLBuffer,
        cellMeshDrawArguments: MTLBuffer,
        visibleJunctionIndices: MTLBuffer,
        junctionDrawArguments: MTLBuffer
    ) {
        self.visibleCellIndices = visibleCellIndices
        self.cellDrawArguments = cellDrawArguments
        self.cellMeshDrawArguments = cellMeshDrawArguments
        self.visibleJunctionIndices = visibleJunctionIndices
        self.junctionDrawArguments = junctionDrawArguments
    }

    var buffers: [MTLBuffer] {
        [
            visibleCellIndices, cellDrawArguments, cellMeshDrawArguments,
            visibleJunctionIndices, junctionDrawArguments
        ]
    }
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
    var dominantProgramGeneration: UInt32
    var componentPersistenceSteps: UInt32
    var programReplicationGeneration: UInt32
    var componentFlags: UInt32
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
    var energeticBoundary: SIMD4<Float>
    var boundary: SIMD4<Float>
    var mechanochemical: SIMD4<Float>
    var social: SIMD4<Float>
    var environment: SIMD4<Float>
}

private struct CellObservationRecord {
    var geometry: SIMD4<Float>
    var identity: SIMD4<UInt32>
    var programLineage: SIMD4<UInt32>
    var programAncestry: SIMD4<UInt32>
    var inheritedTraits: SIMD4<Float>
    var energetic: SIMD4<Float>
    var boundary: SIMD4<Float>
    var mechanochemical: SIMD4<Float>
    var social: SIMD4<Float>
    var environment: SIMD4<Float>
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
    var environment: SIMD4<Float>
    var development: SIMD4<Float>
}

private struct CellIdentity {
    var owner: UInt32
    var programIndex: UInt32
    var persistentID: UInt32
    var componentRoot: UInt32
    var programGeneration: UInt32
    var identityPadding0: UInt32
    var identityPadding1: UInt32
    var identityPadding2: UInt32
}

private struct HeritableProgram {
    var geneA: SIMD4<Float>
    var geneB: SIMD4<Float>
    var geneC: SIMD4<Float>
    var recognition: SIMD4<Float>
    var social: SIMD4<Float>
    var genomeHash: UInt32
    var parentGenomeHash: UInt32
    var originBirthID: UInt32
    var generation: UInt32
    var parentProgramIndex: UInt32
    var parentProgramGeneration: UInt32
    var secondParentGenomeHash: UInt32
    var secondParentProgramIndex: UInt32
    var secondParentProgramGeneration: UInt32
    var ancestryFlags: UInt32
}

private struct ProgramSlotState {
    var occupied: UInt32
    var referenceCount: UInt32
    var generation: UInt32
    var lineageHash: UInt32
    var mutationHazard: UInt32
    var mutationHazardPadding0: UInt32
    var mutationHazardPadding1: UInt32
    var mutationHazardPadding2: UInt32
}

private struct CellJunctionState {
    var pairKey: UInt32
    var lastSeenStep: UInt32
    var persistentFingerprint: UInt32
    var flags: UInt32
    var restDistance: Float
    var strength: Float
    var age: Float
    var load: Float
    var material: SIMD4<Float>
    var remodeling: SIMD4<Float>
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
    var environment: SIMD4<Float>
    var development: SIMD4<Float>
    var developmentCausality: SIMD4<Float>
}

private struct DevelopmentalGenome {
    var topology: SIMD4<UInt32>
    var mutation: SIMD4<Float>
    var actuatorBiasA: SIMD4<Float>
    var actuatorBiasB: SIMD4<Float>
    var mechanochemistryA: SIMD4<Float>
    var mechanochemistryB: SIMD4<Float>
    var morphogenKinetics: SIMD4<Float>
    var morphogenTransport: SIMD4<Float>
    var junctionMaterial: SIMD4<Float>
    var ecologicalResponse: SIMD4<Float>
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
    var programAncestry: SIMD4<UInt32>
}

struct AgentObservation: Sendable, Equatable {
    let id: Int
    let birthID: UInt32
    let parentBirthID: UInt32
    let position: SIMD2<Float>
    let componentDescentDepth: UInt32
    let programReplicationGeneration: UInt32
    let isHunter: Bool
    let hasRegeneratedDevelopment: Bool
    let hasReceivedDamageChallenge: Bool
    let hasDemonstratedHomeostasis: Bool
    let isSexualOffspring: Bool
    let genomeHash: UInt32
    let topologyHash: UInt32
    let morphology: SIMD4<Float>
    let dynamics: SIMD4<Float>
    let mutationDistance: Float
    let energeticIndependence: Float
    let mechanochemicalClosure: Float
    let energeticBoundary: SIMD4<Float>
    let boundary: SIMD4<Float>
    let mechanochemical: SIMD4<Float>
    let social: SIMD4<Float>
    let environment: SIMD4<Float>

    var generation: UInt32 { componentDescentDepth }
}

struct CellObservation: Sendable, Equatable {
    let persistentID: UInt32
    let owner: Int
    let componentBirthID: UInt32
    let programReplicationGeneration: UInt32
    let programID: UInt64
    let parentProgramID: UInt64?
    let programGenomeHash: UInt32
    let parentProgramGenomeHash: UInt32
    let inheritedMechanochemicalTrait: Float
    let position: SIMD2<Float>
    let membranePerimeter: Float
    let exposedPerimeterFraction: Float
    let energetic: SIMD4<Float>
    let boundary: SIMD4<Float>
    let mechanochemical: SIMD4<Float>
    let social: SIMD4<Float>
    let environment: SIMD4<Float>
}

struct RecordedLineageEvent: Sendable, Equatable {
    enum Kind: UInt32, Sendable {
        case birth = 1
        case death = 2
        case fusion = 3
        case programMutation = 4
        case cellDivision = 5
        case crossbreeding = 6
    }

    let sequence: UInt32
    let kind: Kind
    let birthID: UInt32
    let parentBirthID: UInt32
    let step: UInt32
    let generation: UInt32
    let programID: UInt64
    let parentProgramID: UInt64?
    let genomeHash: UInt32
    let topologyHash: UInt32
    let mutationDistance: Float
    let resonanceFrequency: Float
    let energy: Float
    let morphology: SIMD4<Float>
}

private struct SendableAgentObservationBuffers: @unchecked Sendable {
    let records: MTLBuffer
    let cellRecords: MTLBuffer
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
                programID: permanentProgramID(
                    index: record.programAncestry.x,
                    generation: record.programAncestry.y
                ),
                parentProgramID: record.programAncestry.z <
                    permanentProgramSlotCapacity
                    ? permanentProgramID(
                        index: record.programAncestry.z,
                        generation: record.programAncestry.w
                    ) : nil,
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

    func checkpoint() -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        return lastSequence
    }

    func restore(sequence: UInt32) {
        lock.lock()
        lastSequence = sequence
        lock.unlock()
    }
}

private struct RecoveryCheckpointMetadata: @unchecked Sendable {
    let step: UInt64
    let quantumStep: UInt32
    let generation: UInt32
    let resetToken: UInt64
    let addColonyToken: UInt64
    let expansionToken: UInt64
    let lineageSequence: UInt32
    let evaluator: AdaptiveComplexityEvaluator
    let snapshot: EvolutionSnapshot
}

private struct PendingRecoveryCheckpoint: @unchecked Sendable {
    let slot: Int
    let metadata: RecoveryCheckpointMetadata
}

private struct RecoveryCheckpointBank {
    let textures: [MTLTexture]
    let buffers: [MTLBuffer]
    var metadata: RecoveryCheckpointMetadata?
}

private final class MetricReadbackSlot: @unchecked Sendable {
    let metrics: MTLBuffer
    let quantumNorm: MTLBuffer
    let agentState: MTLBuffer
    let agentOccupancy: MTLBuffer
    let cellAggregates: MTLBuffer
    let programRecords: MTLBuffer
    let identityCounters: MTLBuffer
    let energyAudit: MTLBuffer

    init(
        metrics: MTLBuffer,
        quantumNorm: MTLBuffer,
        agentState: MTLBuffer,
        agentOccupancy: MTLBuffer,
        cellAggregates: MTLBuffer,
        programRecords: MTLBuffer,
        identityCounters: MTLBuffer,
        energyAudit: MTLBuffer
    ) {
        self.metrics = metrics
        self.quantumNorm = quantumNorm
        self.agentState = agentState
        self.agentOccupancy = agentOccupancy
        self.cellAggregates = cellAggregates
        self.programRecords = programRecords
        self.identityCounters = identityCounters
        self.energyAudit = energyAudit
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
    case missingCompiledShader
    case missingFunction(String)
    case resourceAllocation(String)
    case executionFailure(String)

    var errorDescription: String? {
        switch self {
        case .noMetalDevice: "This Mac does not expose a Metal device."
        case .missingShader: "The Numi Automata Metal source is missing from the app bundle."
        case .missingCompiledShader:
            "The release app is missing its ahead-of-time Metal 4 shader library."
        case let .missingFunction(name): "The Metal function \(name) could not be loaded."
        case let .resourceAllocation(name): "Metal could not allocate \(name)."
        case let .executionFailure(message): "Metal 4 execution failed: \(message)"
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
    private static let interactiveQuantumStride: UInt64 = 3
    private static let maxAgentCount = maxCellCount
    private static let maxCellCount = 9_216
    private static let maxHeritableProgramCount = 4_096
    private static let maxProgramsPerPropagule = 16
    private static let regulatoryNodeCapacity = 16
    private static let regulatoryEdgeCapacity = 48
    private static let membraneVertexCount = 12
    private static let membraneRenderSubdivision = 4
    private static let cellSpatialHashBucketCount = 16_384
    private static let membraneContactPairCapacity = 524_288
    private static let contactWorkStateCount = 4
    private static let cellJunctionCapacity = 32_768
    private static let worldExchangeChannelCount = 14
    private static let energyAuditChannelCount = 10
    private static let identityCounterCount = 19
    private static let invariantStateCount = 20
    private static let invariantScratchHeaderCount = 16
    private static let invariantScratchCount = invariantScratchHeaderCount +
        maxHeritableProgramCount + maxAgentCount
    private static let lineageEventCapacity = 4_096
    private static let agentObservationRingSize = 3
    private static let agentObservationIntervalFrames: UInt64 = 6
    private static let trackedAgentObservationIntervalFrames: UInt64 = 2
    private static let metricReadbackRingSize = 3
    private static let metricCount = 46
    private static let metricScale = 4096.0
    private static let quantumMetricScale = 1_000_000_000.0
    private static let energyAuditScale = 1_048_576.0
    private static let maximumInteractiveInFlightSubmissions = 2
    private static let maximumInteractiveStepsPerSubmission = 24
    private static let maximumWorldExpansionsPerSubmission = 1
    // This is over sixteen times the current per-step uniform footprint. Keeping a
    // fixed reserve for the render tail makes arena admission deterministic even as
    // x24 population work approaches the cell and contact capacities.
    private static let maximumUniformBytesPerSimulationStep = 128 * 1_024
    private static let reservedUniformBytesForFrameTail = 512 * 1_024
    private static let runtimeTelemetryPublicationInterval = 1.0 / 12.0
    private static let singleBufferGPUThresholdMilliseconds = 8.0
    private static let doubleBufferGPUThresholdMilliseconds = 12.0
    private static let gpuTimingLogEnabled = ProcessInfo.processInfo.environment[
        "NUMI_GPU_TIMING_LOG"
    ] == "1"
    private static let gpuFrameTimingEnabled = ProcessInfo.processInfo.environment[
        "NUMI_GPU_TIMING"
    ] == "1"
    private static let gpuTimingEnabled = gpuFrameTimingEnabled || gpuTimingLogEnabled
    private static let experimentalMeshCellRenderingEnabled =
        ProcessInfo.processInfo.environment["NUMI_EXPERIMENTAL_MESH_CELLS"] == "1"

    private let device: MTLDevice
    private let tuningProfile: MetalDeviceTuningProfile
    private var commandQueue: Metal4ExecutionContext
    private let initializePipeline: MTLComputePipelineState
    private let initializeQuantumPipeline: MTLComputePipelineState
    private let expandWorldPipeline: MTLComputePipelineState
    private let expandQuantumPipeline: MTLComputePipelineState
    private let initializeMechanicalPipeline: MTLComputePipelineState
    private let expandMechanicalPipeline: MTLComputePipelineState
    private let evolveMechanicalPipeline: MTLComputePipelineState
    private let reactionPipeline: MTLComputePipelineState
    private let quantumCouplingPipeline: MTLComputePipelineState
    private let quantumPipeline: MTLComputePipelineState
    private let damagePipeline: MTLComputePipelineState
    private let damageCellPipeline: MTLComputePipelineState
    private let markDamagedComponentsPipeline: MTLComputePipelineState
    private let selectQualificationTargetPipeline: MTLComputePipelineState
    private let damageSelectedTargetWorldPipeline: MTLComputePipelineState
    private let damageSelectedTargetCellsPipeline: MTLComputePipelineState
    private let markSelectedTargetChallengedPipeline: MTLComputePipelineState
    private let measureQualificationTargetPipeline: MTLComputePipelineState
    private let brushPipeline: MTLComputePipelineState
    private let measurementPipeline: MTLComputePipelineState
    private let quantumMeasurementPipeline: MTLComputePipelineState
    private let initializeAgentPipeline: MTLComputePipelineState
    private let nucleateFounderPipeline: MTLComputePipelineState
    private let evolveAgentPipeline: MTLComputePipelineState
    private let injectFounderPipeline: MTLComputePipelineState
    private let expandAgentPipeline: MTLComputePipelineState
    private let collectAgentObservationPipeline: MTLComputePipelineState
    private let collectCellObservationPipeline: MTLComputePipelineState
    private let collectProgramMetricPipeline: MTLComputePipelineState
    private let resetActiveComponentDispatchPipeline: MTLComputePipelineState
    private let compactActiveComponentsPipeline: MTLComputePipelineState
    private let prepareActiveComponentDispatchPipeline: MTLComputePipelineState
    private let compactActiveCellsPipeline: MTLComputePipelineState
    private let evolveCellPipeline: MTLComputePipelineState
    private let evolveMembranePipeline: MTLComputePipelineState
    private let clearCellSpatialHashPipeline: MTLComputePipelineState
    private let clearActiveCellContactEffectsPipeline: MTLComputePipelineState
    private let buildCellSpatialHashPipeline: MTLComputePipelineState
    private let resetMembraneContactWorkPipeline: MTLComputePipelineState
    private let buildMembraneContactPairsPipeline: MTLComputePipelineState
    private let prepareMembraneContactDispatchPipeline: MTLComputePipelineState
    private let detectCellTopologyChangesPipeline: MTLComputePipelineState
    private let clearOwnerCellListsPipeline: MTLComputePipelineState
    private let buildOwnerCellListsPipeline: MTLComputePipelineState
    private let resolveCellContactsPipeline: MTLComputePipelineState
    private let applyCellContactEffectsPipeline: MTLComputePipelineState
    private let measureCellMembraneExposurePipeline: MTLComputePipelineState
    private let initializeCellComponentsPipeline: MTLComputePipelineState
    private let unionCellComponentsPipeline: MTLComputePipelineState
    private let compressCellComponentsPipeline: MTLComputePipelineState
    private let buildCellComponentListsPipeline: MTLComputePipelineState
    private let accumulateCellComponentsPipeline: MTLComputePipelineState
    private let selectPrimaryCellComponentsPipeline: MTLComputePipelineState
    private let assignCellComponentOwnersPipeline: MTLComputePipelineState
    private let reassignCellComponentsPipeline: MTLComputePipelineState
    private let finalizeCellTopologyPipeline: MTLComputePipelineState
    private let divideAndReduceCellPipeline: MTLComputePipelineState
    private let initializeInvariantPipeline: MTLComputePipelineState
    private let clearInvariantScratchPipeline: MTLComputePipelineState
    private let auditContactMomentumPipeline: MTLComputePipelineState
    private let accumulateSimulationInvariantsPipeline: MTLComputePipelineState
    private let finalizeSimulationInvariantsPipeline: MTLComputePipelineState
    private let resetRenderDrawArgumentsPipeline: MTLComputePipelineState
    private let compactCellRenderPipeline: MTLComputePipelineState
    private let compactJunctionRenderPipeline: MTLComputePipelineState
    private let finalizeRenderDrawArgumentsPipeline: MTLComputePipelineState
    private let scaleSurfacePipelines: [MTLRenderPipelineState]
    private let cellRenderPipeline: MTLRenderPipelineState
    private let cellMeshRenderPipeline: MTLRenderPipelineState
    private let junctionRenderPipeline: MTLRenderPipelineState
    private let bloomPrefilterPipeline: MTLComputePipelineState
    private let compositePipeline: MTLRenderPipelineState
    private let spinorDisplayPipeline: MTLRenderPipelineState
    private let pipelineBuildTelemetry: Metal4PipelineBuildTelemetry
    private let renderSubmissionResources: [RenderSubmissionResources]
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
    private var developmentalField: MTLTexture
    private var reactionDevelopmentalField: MTLTexture
    private var environmentState: MTLTexture
    private var reactionEnvironmentState: MTLTexture
    private var mechanicalState: MTLTexture
    private var reactionMechanicalState: MTLTexture
    private var quantumState: MTLTexture
    private var reactionQuantumState: MTLTexture
    private let quantumCoupling: MTLTexture
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
    private let componentCellHeads: MTLBuffer
    private let componentCellNext: MTLBuffer
    private let ownerPrimaryRoots: MTLBuffer
    private let cellAggregates: MTLBuffer
    private let heritablePrograms: MTLBuffer
    private let programSlots: MTLBuffer
    private let developmentalGenomes: MTLBuffer
    private let regulatoryNodes: MTLBuffer
    private let regulatoryEdges: MTLBuffer
    private let regulatoryStates: MTLBuffer
    private let resonanceGenomes: MTLBuffer
    private let membraneVertices: MTLBuffer
    private let cellSpatialHashHeads: MTLBuffer
    private let cellSpatialHashNext: MTLBuffer
    private let membraneContactPairs: MTLBuffer
    private let contactWorkState: MTLBuffer
    private let cellTopologySignatures: MTLBuffer
    private let contactPairDispatchArguments: MTLBuffer
    private let cellContactEffects: MTLBuffer
    private let membraneContactEffects: MTLBuffer
    private let cellJunctions: MTLBuffer
    private let cellEnergyExchange: MTLBuffer
    private let energyAudit: MTLBuffer
    private let invariantState: MTLBuffer
    private let invariantScratch: MTLBuffer
    private let activeComponentIndices: MTLBuffer
    private let activeComponentCount: MTLBuffer
    private let activeComponentDispatchArguments: MTLBuffer
    private let activeCellIndices: MTLBuffer
    private let activeCellCount: MTLBuffer
    private let activeCellDispatchArguments: MTLBuffer
    private let identityCounters: MTLBuffer
    private let lineageEvents: MTLBuffer
    private let mechanicalForcing: MTLBuffer
    private let qualificationTargetState: MTLBuffer
    private let qualificationTargetMeasurement: MTLBuffer
    private let agentObservationBuffers: [MTLBuffer]
    private let cellObservationBuffers: [MTLBuffer]
    private let lineageEventObservationBuffers: [MTLBuffer]
    private let identityCounterObservationBuffers: [MTLBuffer]
    private let metricReadbackSlots: [MetricReadbackSlot]
    private var headlessReadbackBuffers: HeadlessReadbackBuffers?
    private var recoveryCheckpointBanks: [RecoveryCheckpointBank] = []
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
        barrierGain: 1,
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
    private var gpuCompletedSteps: UInt64 = 0
    private var scientificallyCommittedSteps: UInt64 = 0
    private var unfinishedCommandBuffers = 0
    private var submissionEpoch: UInt64 = 1
    private var recoveryCount: UInt32 = 0
    private var lastMetalError: String?
    private var lastCompletionTime = CFAbsoluteTimeGetCurrent()
    private var telemetrySampleTime = CFAbsoluteTimeGetCurrent()
    private var telemetrySampleStep: UInt64 = 0
    private var measuredStepsPerSecond = 0.0
    private var lastCPUEncodeMilliseconds = 0.0
    private var lastTotalGPUMilliseconds = 0.0
    private var interactiveInFlightSubmissionLimit = maximumInteractiveInFlightSubmissions
    private var lastRuntimeTelemetryPublicationTime = 0.0
    private var lastPhaseTimings: [MetalPhaseTiming] = []
    private var checkpointStep: UInt64 = 0
    private var lastRestoredCheckpointStep: UInt64?
    private var submissionFaulted = false
    private let syntheticFaultStep = ProcessInfo.processInfo.environment[
        "NUMI_SYNTHETIC_METAL_FAULT_STEP"
    ].flatMap(UInt64.init)
    private var syntheticFaultInjected = false
    private let syntheticStallStep = ProcessInfo.processInfo.environment[
        "NUMI_SYNTHETIC_METAL_STALL_STEP"
    ].flatMap(UInt64.init)
    private var syntheticStallInjected = false
    private var syntheticRetiredCommandBuffers = 0
    private var watchdogTimer: Timer?
    private var quantumStep: UInt32 = 0
    private var generation: UInt32 = 0
    private var frameSerial: UInt64 = 0
    private var metricSlotsInFlight = Array(repeating: false, count: metricReadbackRingSize)
    private var evaluator = AdaptiveComplexityEvaluator(seed: 0xA170_6E51, eliteCount: 1)
    private var latestSnapshot = EvolutionSnapshot()

    var onSnapshot: (@Sendable (EvolutionSnapshot) -> Void)?
    var onObservationBatch: (@Sendable (
        [RecordedLineageEvent], [AgentObservation], [CellObservation]
    ) -> Void)?
    var onRuntimeTelemetry: (@Sendable (RendererRuntimeTelemetry) -> Void)?

    init(view: MTKView) throws {
        precondition(MemoryLayout<AgentState>.stride == 192, "AgentState Metal ABI drift")
        precondition(MemoryLayout<AgentObservationRecord>.stride == 176, "AgentObservationRecord Metal ABI drift")
        precondition(MemoryLayout<CellObservationRecord>.stride == 160, "CellObservationRecord Metal ABI drift")
        precondition(MemoryLayout<CellState>.stride == 288, "CellState Metal ABI drift")
        precondition(MemoryLayout<CellIdentity>.stride == 32, "CellIdentity Metal ABI drift")
        precondition(MemoryLayout<HeritableProgram>.stride == 128, "HeritableProgram Metal ABI drift")
        precondition(MemoryLayout<ProgramSlotState>.stride == 32, "ProgramSlotState Metal ABI drift")
        precondition(MemoryLayout<CellJunctionState>.stride == 64, "CellJunctionState Metal ABI drift")
        precondition(MemoryLayout<CellAggregate>.stride == 336, "CellAggregate Metal ABI drift")
        precondition(MemoryLayout<DevelopmentalGenome>.stride == 160, "DevelopmentalGenome Metal ABI drift")
        precondition(MemoryLayout<RegulatoryNode>.stride == 32, "RegulatoryNode Metal ABI drift")
        precondition(MemoryLayout<RegulatoryEdge>.stride == 32, "RegulatoryEdge Metal ABI drift")
        precondition(MemoryLayout<ResonanceGenome>.stride == 32, "ResonanceGenome Metal ABI drift")
        precondition(MemoryLayout<ProgramMetricRecord>.stride == 192, "ProgramMetricRecord Metal ABI drift")
        precondition(MemoryLayout<MembraneVertex>.stride == 32, "MembraneVertex Metal ABI drift")
        precondition(MemoryLayout<LineageEventRecord>.stride == 80, "LineageEventRecord Metal ABI drift")
        precondition(
            MemoryLayout<QualificationTargetMeasurement>.stride == 32,
            "QualificationTargetMeasurement Metal ABI drift"
        )
        guard let device = view.device ?? MTLCreateSystemDefaultDevice() else {
            throw EvolutionRendererError.noMetalDevice
        }
        let commandQueue = try Metal4ExecutionContext(device: device)
        self.device = device
        tuningProfile = device.name.localizedCaseInsensitiveContains("M4")
            ? .m4Optimized
            : .genericMetal4
        self.commandQueue = commandQueue
        view.device = device

        let library = try Self.makeLibrary(device: device)
        let pipelineFactory = try Metal4PipelineFactory(device: device, library: library)
        initializePipeline = try pipelineFactory.makeComputePipeline(named: "initializeWorld")
        initializeQuantumPipeline = try pipelineFactory.makeComputePipeline(named: "initializeQuantumField")
        expandWorldPipeline = try pipelineFactory.makeComputePipeline(named: "expandWorld")
        expandQuantumPipeline = try pipelineFactory.makeComputePipeline(named: "expandQuantumField")
        initializeMechanicalPipeline = try pipelineFactory.makeComputePipeline(named: "initializeMechanicalField")
        expandMechanicalPipeline = try pipelineFactory.makeComputePipeline(named: "expandMechanicalField")
        evolveMechanicalPipeline = try pipelineFactory.makeComputePipeline(named: "evolveMechanicalField")
        reactionPipeline = try pipelineFactory.makeComputePipeline(named: "reactWorld")
        quantumCouplingPipeline = try pipelineFactory.makeComputePipeline(named: "prepareQuantumCoupling")
        quantumPipeline = try pipelineFactory.makeComputePipeline(named: "evolveQuantumField")
        damagePipeline = try pipelineFactory.makeComputePipeline(named: "damageWorld")
        damageCellPipeline = try pipelineFactory.makeComputePipeline(
            named: "damageOrganismCells"
        )
        markDamagedComponentsPipeline = try pipelineFactory.makeComputePipeline(
            named: "markDamagedComponents"
        )
        selectQualificationTargetPipeline = try pipelineFactory.makeComputePipeline(
            named: "selectRegenerativeQualificationTarget"
        )
        damageSelectedTargetWorldPipeline = try pipelineFactory.makeComputePipeline(
            named: "damageSelectedTargetWorld"
        )
        damageSelectedTargetCellsPipeline = try pipelineFactory.makeComputePipeline(
            named: "damageSelectedTargetCells"
        )
        markSelectedTargetChallengedPipeline = try pipelineFactory.makeComputePipeline(
            named: "markSelectedTargetChallenged"
        )
        measureQualificationTargetPipeline = try pipelineFactory.makeComputePipeline(
            named: "measureQualificationTarget"
        )
        brushPipeline = try pipelineFactory.makeComputePipeline(named: "applyBrush")
        measurementPipeline = try pipelineFactory.makeComputePipeline(named: "measureWorld")
        quantumMeasurementPipeline = try pipelineFactory.makeComputePipeline(named: "measureQuantumField")
        initializeAgentPipeline = try pipelineFactory.makeComputePipeline(named: "initializeAgents")
        nucleateFounderPipeline = try pipelineFactory.makeComputePipeline(named: "nucleateAutogenicFounder")
        evolveAgentPipeline = try pipelineFactory.makeComputePipeline(named: "evolveAgents")
        injectFounderPipeline = try pipelineFactory.makeComputePipeline(named: "injectFounder")
        expandAgentPipeline = try pipelineFactory.makeComputePipeline(named: "expandAgents")
        collectAgentObservationPipeline = try pipelineFactory.makeComputePipeline(named: "collectAgentObservations")
        collectCellObservationPipeline = try pipelineFactory.makeComputePipeline(named: "collectCellObservations")
        collectProgramMetricPipeline = try pipelineFactory.makeComputePipeline(named: "collectProgramMetricRecords")
        resetActiveComponentDispatchPipeline = try pipelineFactory.makeComputePipeline(named: "resetActiveComponentDispatch")
        compactActiveComponentsPipeline = try pipelineFactory.makeComputePipeline(named: "compactActiveComponents")
        prepareActiveComponentDispatchPipeline = try pipelineFactory.makeComputePipeline(named: "prepareActiveComponentDispatch")
        compactActiveCellsPipeline = try pipelineFactory.makeComputePipeline(named: "compactActiveCellsOrdered")
        evolveCellPipeline = try pipelineFactory.makeComputePipeline(named: "evolveOrganismCells")
        evolveMembranePipeline = try pipelineFactory.makeComputePipeline(named: "evolveCellMembranes")
        clearCellSpatialHashPipeline = try pipelineFactory.makeComputePipeline(named: "clearCellSpatialHash")
        clearActiveCellContactEffectsPipeline = try pipelineFactory.makeComputePipeline(
            named: "clearActiveCellContactEffects"
        )
        buildCellSpatialHashPipeline = try pipelineFactory.makeComputePipeline(named: "buildCellSpatialHash")
        resetMembraneContactWorkPipeline = try pipelineFactory.makeComputePipeline(
            named: "resetMembraneContactWork"
        )
        buildMembraneContactPairsPipeline = try pipelineFactory.makeComputePipeline(
            named: "buildMembraneContactPairs"
        )
        prepareMembraneContactDispatchPipeline = try pipelineFactory.makeComputePipeline(
            named: "prepareMembraneContactDispatch"
        )
        detectCellTopologyChangesPipeline = try pipelineFactory.makeComputePipeline(
            named: "detectCellTopologyChanges"
        )
        clearOwnerCellListsPipeline = try pipelineFactory.makeComputePipeline(named: "clearOwnerCellLists")
        buildOwnerCellListsPipeline = try pipelineFactory.makeComputePipeline(named: "buildOwnerCellLists")
        resolveCellContactsPipeline = try pipelineFactory.makeComputePipeline(named: "resolveMembraneContacts")
        applyCellContactEffectsPipeline = try pipelineFactory.makeComputePipeline(named: "applyCellContactEffects")
        measureCellMembraneExposurePipeline = try pipelineFactory.makeComputePipeline(named: "measureCellMembraneExposure")
        initializeCellComponentsPipeline = try pipelineFactory.makeComputePipeline(named: "initializeCellComponents")
        unionCellComponentsPipeline = try pipelineFactory.makeComputePipeline(named: "unionCellComponents")
        compressCellComponentsPipeline = try pipelineFactory.makeComputePipeline(named: "compressCellComponents")
        buildCellComponentListsPipeline = try pipelineFactory.makeComputePipeline(named: "buildCellComponentLists")
        accumulateCellComponentsPipeline = try pipelineFactory.makeComputePipeline(named: "accumulateCellComponents")
        selectPrimaryCellComponentsPipeline = try pipelineFactory.makeComputePipeline(named: "selectPrimaryCellComponents")
        assignCellComponentOwnersPipeline = try pipelineFactory.makeComputePipeline(named: "assignCellComponentOwners")
        reassignCellComponentsPipeline = try pipelineFactory.makeComputePipeline(named: "reassignCellComponents")
        finalizeCellTopologyPipeline = try pipelineFactory.makeComputePipeline(
            named: "finalizeCellTopology"
        )
        divideAndReduceCellPipeline = try pipelineFactory.makeComputePipeline(named: "divideAndReduceOrganismCells")
        initializeInvariantPipeline = try pipelineFactory.makeComputePipeline(named: "initializeInvariantAudit")
        clearInvariantScratchPipeline = try pipelineFactory.makeComputePipeline(named: "clearInvariantScratch")
        auditContactMomentumPipeline = try pipelineFactory.makeComputePipeline(named: "auditContactMomentum")
        accumulateSimulationInvariantsPipeline = try pipelineFactory.makeComputePipeline(named: "accumulateSimulationInvariants")
        finalizeSimulationInvariantsPipeline = try pipelineFactory.makeComputePipeline(named: "finalizeSimulationInvariants")
        resetRenderDrawArgumentsPipeline = try pipelineFactory.makeComputePipeline(
            named: "resetRenderDrawArguments"
        )
        compactCellRenderPipeline = try pipelineFactory.makeComputePipeline(named: "compactVisibleCells")
        compactJunctionRenderPipeline = try pipelineFactory.makeComputePipeline(
            named: "compactVisibleJunctions"
        )
        finalizeRenderDrawArgumentsPipeline = try pipelineFactory.makeComputePipeline(
            named: "finalizeRenderDrawArguments"
        )
        bloomPrefilterPipeline = try pipelineFactory.makeComputePipeline(named: "bloomPrefilter")

        scaleSurfacePipelines = try [
            ("Ecological field renderer", "worldSurfaceFragment"),
            ("Morphology field renderer", "worldSurfaceFragment"),
            ("Cellular tissue renderer", "cellularSurfaceFragment"),
            ("Molecular reaction renderer", "molecularSurfaceFragment"),
            ("Wave-observable renderer", "waveSurfaceFragment"),
            ("Spinor lattice renderer", "spinorSurfaceFragment")
        ].map { specification in
            try pipelineFactory.makeRenderPipeline(
                label: specification.0,
                vertex: "fullscreenVertex",
                fragment: specification.1,
                pixelFormat: .rg11b10Float
            )
        }
        cellRenderPipeline = try pipelineFactory.makeRenderPipeline(
            label: "Persistent multicellular renderer",
            vertex: "cellVertex",
            fragment: "cellFragment",
            pixelFormat: .rg11b10Float,
            blending: true
        )
        cellMeshRenderPipeline = try pipelineFactory.makeMeshRenderPipeline(
            label: "M4 adaptive membrane contour renderer",
            mesh: "cellContourMesh",
            fragment: "cellFragment",
            pixelFormat: .rg11b10Float,
            blending: true
        )
        junctionRenderPipeline = try pipelineFactory.makeRenderPipeline(
            label: "Causal intercellular transport renderer",
            vertex: "junctionVertex",
            fragment: "junctionFragment",
            pixelFormat: .rg11b10Float,
            blending: true
        )
        compositePipeline = try pipelineFactory.makeRenderPipeline(
            label: "HDR bloom and tone-mapping composite",
            vertex: "fullscreenVertex",
            fragment: "compositeFragment",
            pixelFormat: .bgra8Unorm_srgb
        )
        spinorDisplayPipeline = try pipelineFactory.makeRenderPipeline(
            label: "Direct spinor display renderer",
            vertex: "fullscreenVertex",
            fragment: "spinorDisplayFragment",
            pixelFormat: .bgra8Unorm_srgb
        )
        pipelineBuildTelemetry = pipelineFactory.finalize()

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
        developmentalField = try Self.makeWorldTexture(
            device: device, label: "Extracellular ligands, matrix, and wound cue"
        )
        reactionDevelopmentalField = try Self.makeWorldTexture(
            device: device, label: "Reaction extracellular developmental field"
        )
        environmentState = try Self.makeWorldTexture(device: device, label: "Persistent geology and hazards")
        reactionEnvironmentState = try Self.makeWorldTexture(device: device, label: "Expanded geology and hazards")
        mechanicalState = try Self.makeWorldTexture(device: device, label: "Extracellular displacement and velocity")
        reactionMechanicalState = try Self.makeWorldTexture(device: device, label: "Reaction extracellular mechanics")
        quantumState = try Self.makeQuantumTexture(device: device, label: "Quantum wavefunction")
        reactionQuantumState = try Self.makeQuantumTexture(device: device, label: "Reaction quantum wavefunction")
        quantumCoupling = try Self.makeQuantumCouplingTexture(
            device: device,
            label: "Biology-to-spinor coupling coefficients"
        )

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
        let componentCellHeadLength = Self.maxCellCount * MemoryLayout<UInt32>.stride
        let componentCellNextLength = Self.maxCellCount * MemoryLayout<UInt32>.stride
        let ownerPrimaryRootLength = Self.maxAgentCount * MemoryLayout<UInt32>.stride
        let cellAggregateLength = Self.maxAgentCount * MemoryLayout<CellAggregate>.stride
        let heritableProgramLength = Self.maxHeritableProgramCount * MemoryLayout<HeritableProgram>.stride
        let programSlotLength = Self.maxHeritableProgramCount * MemoryLayout<ProgramSlotState>.stride
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
        let membraneContactPairLength = Self.membraneContactPairCapacity *
            MemoryLayout<SIMD2<UInt32>>.stride
        let contactWorkStateLength = Self.contactWorkStateCount * MemoryLayout<UInt32>.stride
        let cellTopologySignatureLength = Self.maxCellCount * 4 * MemoryLayout<UInt32>.stride
        let contactPairDispatchLength = 3 * MemoryLayout<UInt32>.stride
        let cellContactEffectLength = Self.maxCellCount * 6 * MemoryLayout<Int32>.stride
        let membraneContactEffectLength = Self.maxCellCount * Self.membraneVertexCount * 3 *
            MemoryLayout<Int32>.stride
        let cellJunctionLength = Self.cellJunctionCapacity * MemoryLayout<CellJunctionState>.stride
        let cellEnergyExchangeLength = Self.gridSize * Self.gridSize * Self.worldCount *
            Self.worldExchangeChannelCount * MemoryLayout<UInt32>.stride
        let energyAuditLength = Self.energyAuditChannelCount * MemoryLayout<Int32>.stride
        let invariantStateLength = Self.invariantStateCount * MemoryLayout<UInt32>.stride
        let invariantScratchLength = Self.invariantScratchCount * MemoryLayout<Int32>.stride
        let visibleCellIndexLength = Self.maxCellCount * MemoryLayout<UInt32>.stride
        let visibleJunctionIndexLength = Self.cellJunctionCapacity * MemoryLayout<UInt32>.stride
        let drawArgumentLength = 4 * MemoryLayout<UInt32>.stride
        let meshDrawArgumentLength = 3 * MemoryLayout<UInt32>.stride
        let activeComponentIndexLength = Self.maxAgentCount * MemoryLayout<UInt32>.stride
        let activeComponentCountLength = MemoryLayout<UInt32>.stride
        let activeComponentDispatchLength = 3 * MemoryLayout<UInt32>.stride
        let activeCellIndexLength = Self.maxCellCount * MemoryLayout<UInt32>.stride
        let activeCellCountLength = MemoryLayout<UInt32>.stride
        let activeCellDispatchLength = 3 * MemoryLayout<UInt32>.stride
        let identityCounterLength = Self.identityCounterCount * MemoryLayout<UInt32>.stride
        let lineageEventLength = Self.lineageEventCapacity * MemoryLayout<LineageEventRecord>.stride
        let mechanicalForcingLength = Self.gridSize * Self.gridSize * Self.worldCount * 2 *
            MemoryLayout<Int32>.stride
        let qualificationTargetStateLength = 4 * MemoryLayout<UInt32>.stride
        let qualificationTargetMeasurementLength =
            MemoryLayout<QualificationTargetMeasurement>.stride
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
              let componentCellHeads = device.makeBuffer(
                length: componentCellHeadLength, options: .storageModePrivate
              ),
              let componentCellNext = device.makeBuffer(
                length: componentCellNextLength, options: .storageModePrivate
              ),
              let ownerPrimaryRoots = device.makeBuffer(
                length: ownerPrimaryRootLength, options: .storageModePrivate
              ),
              let cellAggregates = device.makeBuffer(length: cellAggregateLength, options: .storageModePrivate),
              let heritablePrograms = device.makeBuffer(
                length: heritableProgramLength,
                options: .storageModePrivate
              ),
              let programSlots = device.makeBuffer(
                length: programSlotLength, options: .storageModePrivate
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
              let membraneContactPairs = device.makeBuffer(
                length: membraneContactPairLength, options: .storageModePrivate
              ),
              let contactWorkState = device.makeBuffer(
                length: contactWorkStateLength, options: .storageModePrivate
              ),
              let cellTopologySignatures = device.makeBuffer(
                length: cellTopologySignatureLength, options: .storageModePrivate
              ),
              let contactPairDispatchArguments = device.makeBuffer(
                length: contactPairDispatchLength, options: .storageModePrivate
              ),
              let cellContactEffects = device.makeBuffer(
                length: cellContactEffectLength, options: .storageModePrivate
              ),
              let membraneContactEffects = device.makeBuffer(
                length: membraneContactEffectLength, options: .storageModePrivate
              ),
              let cellJunctions = device.makeBuffer(
                length: cellJunctionLength, options: .storageModePrivate
              ),
              let cellEnergyExchange = device.makeBuffer(
                length: cellEnergyExchangeLength, options: .storageModePrivate
              ),
              let energyAudit = device.makeBuffer(
                length: energyAuditLength, options: .storageModePrivate
              ),
              let invariantState = device.makeBuffer(
                length: invariantStateLength, options: .storageModePrivate
              ),
              let invariantScratch = device.makeBuffer(
                length: invariantScratchLength, options: .storageModePrivate
              ),
              let activeComponentIndices = device.makeBuffer(
                length: activeComponentIndexLength,
                options: .storageModePrivate
              ),
              let activeComponentCount = device.makeBuffer(
                length: activeComponentCountLength,
                options: .storageModePrivate
              ),
              let activeComponentDispatchArguments = device.makeBuffer(
                length: activeComponentDispatchLength,
                options: .storageModePrivate
              ),
              let activeCellIndices = device.makeBuffer(
                length: activeCellIndexLength,
                options: .storageModePrivate
              ),
              let activeCellCount = device.makeBuffer(
                length: activeCellCountLength,
                options: .storageModePrivate
              ),
              let activeCellDispatchArguments = device.makeBuffer(
                length: activeCellDispatchLength,
                options: .storageModePrivate
              ),
              let identityCounters = device.makeBuffer(length: identityCounterLength, options: .storageModePrivate),
              let lineageEvents = device.makeBuffer(length: lineageEventLength, options: .storageModePrivate),
              let mechanicalForcing = device.makeBuffer(
                length: mechanicalForcingLength,
                options: .storageModePrivate
              ),
              let qualificationTargetState = device.makeBuffer(
                length: qualificationTargetStateLength,
                options: .storageModePrivate
              ),
              let qualificationTargetMeasurement = device.makeBuffer(
                length: qualificationTargetMeasurementLength,
                options: .storageModePrivate
              ) else {
            throw EvolutionRendererError.resourceAllocation("persistent multicellular state")
        }
        let renderSubmissionResources = try (0..<Metal4ExecutionContext.maximumInFlightSubmissions)
            .map { slotIndex in
                guard let visibleCellIndices = device.makeBuffer(
                    length: visibleCellIndexLength,
                    options: .storageModePrivate
                ), let cellDrawArguments = device.makeBuffer(
                    length: drawArgumentLength,
                    options: .storageModePrivate
                ), let cellMeshDrawArguments = device.makeBuffer(
                    length: meshDrawArgumentLength,
                    options: .storageModePrivate
                ), let visibleJunctionIndices = device.makeBuffer(
                    length: visibleJunctionIndexLength,
                    options: .storageModePrivate
                ), let junctionDrawArguments = device.makeBuffer(
                    length: drawArgumentLength,
                    options: .storageModePrivate
                ) else {
                    throw EvolutionRendererError.resourceAllocation(
                        "render submission resources \(slotIndex)"
                    )
                }
                visibleCellIndices.label = "Visible cell indices slot \(slotIndex)"
                cellDrawArguments.label = "Cell draw arguments slot \(slotIndex)"
                cellMeshDrawArguments.label = "Cell mesh arguments slot \(slotIndex)"
                visibleJunctionIndices.label = "Visible junction indices slot \(slotIndex)"
                junctionDrawArguments.label = "Junction draw arguments slot \(slotIndex)"
                return RenderSubmissionResources(
                    visibleCellIndices: visibleCellIndices,
                    cellDrawArguments: cellDrawArguments,
                    cellMeshDrawArguments: cellMeshDrawArguments,
                    visibleJunctionIndices: visibleJunctionIndices,
                    junctionDrawArguments: junctionDrawArguments
                )
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
        componentCellHeads.label = "Segmented connected-component heads"
        componentCellNext.label = "Segmented connected-component links"
        ownerPrimaryRoots.label = "Primary connected component per organism"
        cellAggregates.label = "Per-organism cellular aggregates"
        heritablePrograms.label = "Persistent heritable-program records"
        programSlots.label = "Generation-tagged recyclable program slots"
        developmentalGenomes.label = "Evolvable developmental programs"
        regulatoryNodes.label = "Sparse developmental nodes"
        regulatoryEdges.label = "Sparse developmental edges"
        regulatoryStates.label = "Cell-local regulatory activity"
        resonanceGenomes.label = "Heritable mechanosensory resonance"
        membraneVertices.label = "Deformable cell membrane vertices"
        cellSpatialHashHeads.label = "Membrane-contact spatial hash heads"
        cellSpatialHashNext.label = "Membrane-contact spatial hash links"
        membraneContactPairs.label = "Compacted membrane-contact candidate pairs"
        contactWorkState.label = "Contact count, overflow, and topology state"
        cellTopologySignatures.label = "Current and previous cell connectivity signatures"
        contactPairDispatchArguments.label = "Indirect membrane-contact dispatch arguments"
        cellContactEffects.label = "Accumulated cell contact effects"
        membraneContactEffects.label = "Equal-and-opposite membrane vertex forces"
        cellJunctions.label = "Persistent membrane junction hash"
        cellEnergyExchange.label = "Fixed-point substrate, catalyst, detox, ligand, and matrix exchange"
        energyAudit.label = "Global cellular energy conservation audit"
        invariantState.label = "Persistent fail-fast invariant audit"
        invariantScratch.label = "Invariant reduction scratch"
        activeComponentIndices.label = "Compacted active component handles"
        activeComponentCount.label = "Active component count"
        activeComponentDispatchArguments.label = "Indirect active component dispatch arguments"
        activeCellIndices.label = "Ordered living-cell indices"
        activeCellCount.label = "Living-cell count"
        activeCellDispatchArguments.label = "Indirect living-cell dispatch arguments"
        identityCounters.label = "Permanent identity and innovation counters"
        lineageEvents.label = "GPU lineage event ring"
        mechanicalForcing.label = "Cell contractile forcing"
        qualificationTargetState.label = "Regenerative qualification target"
        qualificationTargetMeasurement.label = "Regenerative qualification measurement"
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
        self.componentCellHeads = componentCellHeads
        self.componentCellNext = componentCellNext
        self.ownerPrimaryRoots = ownerPrimaryRoots
        self.cellAggregates = cellAggregates
        self.heritablePrograms = heritablePrograms
        self.programSlots = programSlots
        self.developmentalGenomes = developmentalGenomes
        self.regulatoryNodes = regulatoryNodes
        self.regulatoryEdges = regulatoryEdges
        self.regulatoryStates = regulatoryStates
        self.resonanceGenomes = resonanceGenomes
        self.membraneVertices = membraneVertices
        self.cellSpatialHashHeads = cellSpatialHashHeads
        self.cellSpatialHashNext = cellSpatialHashNext
        self.membraneContactPairs = membraneContactPairs
        self.contactWorkState = contactWorkState
        self.cellTopologySignatures = cellTopologySignatures
        self.contactPairDispatchArguments = contactPairDispatchArguments
        self.cellContactEffects = cellContactEffects
        self.membraneContactEffects = membraneContactEffects
        self.cellJunctions = cellJunctions
        self.cellEnergyExchange = cellEnergyExchange
        self.energyAudit = energyAudit
        self.invariantState = invariantState
        self.invariantScratch = invariantScratch
        self.renderSubmissionResources = renderSubmissionResources
        self.activeComponentIndices = activeComponentIndices
        self.activeComponentCount = activeComponentCount
        self.activeComponentDispatchArguments = activeComponentDispatchArguments
        self.activeCellIndices = activeCellIndices
        self.activeCellCount = activeCellCount
        self.activeCellDispatchArguments = activeCellDispatchArguments
        self.identityCounters = identityCounters
        self.lineageEvents = lineageEvents
        self.mechanicalForcing = mechanicalForcing
        self.qualificationTargetState = qualificationTargetState
        self.qualificationTargetMeasurement = qualificationTargetMeasurement
        let observationLength = Self.maxAgentCount * MemoryLayout<AgentObservationRecord>.stride
        let cellObservationLength = Self.maxCellCount * MemoryLayout<CellObservationRecord>.stride
        var observationBuffers: [MTLBuffer] = []
        var observedCellBuffers: [MTLBuffer] = []
        var observedLineageEventBuffers: [MTLBuffer] = []
        var observedIdentityCounterBuffers: [MTLBuffer] = []
        for slot in 0..<Self.agentObservationRingSize {
            guard let observationBuffer = device.makeBuffer(
                length: observationLength,
                options: .storageModeShared
            ), let cellObservationBuffer = device.makeBuffer(
                length: cellObservationLength,
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
            cellObservationBuffer.label = "Compact cell observations \(slot)"
            observedLineageEvents.label = "Observed lineage events \(slot)"
            observedIdentityCounters.label = "Observed identity counters \(slot)"
            observationBuffers.append(observationBuffer)
            observedCellBuffers.append(cellObservationBuffer)
            observedLineageEventBuffers.append(observedLineageEvents)
            observedIdentityCounterBuffers.append(observedIdentityCounters)
        }
        agentObservationBuffers = observationBuffers
        cellObservationBuffers = observedCellBuffers
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
                  ),
                  let observedEnergyAudit = device.makeBuffer(
                    length: energyAuditLength,
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
            observedEnergyAudit.label = "Metric energy conservation audit \(slot)"
            metricSlots.append(MetricReadbackSlot(
                metrics: metrics,
                quantumNorm: quantumNorm,
                agentState: observedAgents,
                agentOccupancy: observedOccupancy,
                cellAggregates: observedCellAggregates,
                programRecords: observedProgramRecords,
                identityCounters: observedMetricIdentityCounters,
                energyAudit: observedEnergyAudit
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
        if let layer = view.layer as? CAMetalLayer {
            // Keep one drawable outside the submitted-frame limit so WindowServer
            // compositing cannot stall input handling in nextDrawable().
            layer.maximumDrawableCount = Metal4ExecutionContext.maximumInFlightSubmissions
        }
        registerMetal4Residency(view: view)
        try initializeSimulation()
        recoveryCheckpointBanks = try makeRecoveryCheckpointBanks()
        commandQueue.register(recoveryCheckpointBanks.flatMap { bank in
            bank.textures.map { $0 as any MTLAllocation } +
                bank.buffers.map { $0 as any MTLAllocation }
        })
        try captureInitialRecoveryCheckpoint()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in self?.inspectCompletionWatchdog() }
        }
        if let watchdogTimer {
            RunLoop.main.add(watchdogTimer, forMode: .common)
        }
    }

    isolated deinit {
        watchdogTimer?.invalidate()
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
        let encodingStartedAt = CFAbsoluteTimeGetCurrent()
        let frameSettings: RendererSettings
        stateLock.lock()
        frameSettings = settings
        stateLock.unlock()
        frameSerial &+= 1

        guard !submissionFaulted,
              unfinishedCommandBuffers < interactiveInFlightSubmissionLimit else {
            publishRuntimeTelemetry()
            return
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            handleSubmissionFailure("Metal declined command-buffer allocation.")
            return
        }
        commandBuffer.label = "Numi Automata frame"
        if frameSerial.isMultiple(of: 60) {
            commandBuffer.enablePhaseTiming()
        }
        commandBuffer.writeTimestamp(ending: "submission start")
        var pendingCheckpoint: PendingRecoveryCheckpoint?
        var resetEncoded = false

        if frameSettings.resetToken != appliedResetToken {
            totalSteps = 0
            gpuCompletedSteps = 0
            scientificallyCommittedSteps = 0
            checkpointStep = 0
            lastRestoredCheckpointStep = nil
            recoveryCount = 0
            syntheticFaultInjected = false
            syntheticStallInjected = false
            syntheticRetiredCommandBuffers = 0
            lastMetalError = nil
            quantumStep = 0
            generation = 0
            evaluator = AdaptiveComplexityEvaluator(seed: 0xA170_6E51 ^ frameSettings.resetToken, eliteCount: 1)
            lineageEventDeliveryState.reset()
            encodeInitialization(into: commandBuffer, settings: frameSettings)
            recoveryCheckpointBanks.indices.forEach {
                recoveryCheckpointBanks[$0].metadata = nil
            }
            appliedResetToken = frameSettings.resetToken
            appliedExpansionToken = frameSettings.expansionToken
            resetEncoded = true
        }

        var encodedExpansions = 0
        while appliedExpansionToken < frameSettings.expansionToken,
              encodedExpansions < Self.maximumWorldExpansionsPerSubmission {
            encodeWorldExpansion(
                into: commandBuffer,
                settings: frameSettings,
                level: UInt32(truncatingIfNeeded: appliedExpansionToken + 1)
            )
            appliedExpansionToken &+= 1
            encodedExpansions += 1
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
            let admittedStepCount = min(
                max(frameSettings.stepsPerFrame, 1),
                Self.maximumInteractiveStepsPerSubmission
            )
            for _ in 0..<admittedStepCount {
                guard commandBuffer.remainingUniformBytes >=
                    Self.maximumUniformBytesPerSimulationStep +
                    Self.reservedUniformBytesForFrameTail else { break }
                encodeSimulationStep(into: commandBuffer, settings: frameSettings)
                totalSteps &+= 1
                if totalSteps.isMultiple(of: Self.interactiveQuantumStride) {
                    encodeQuantumStep(into: commandBuffer, settings: frameSettings)
                }
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
                    if !recoveryCheckpointBanks.isEmpty {
                        let slot = Int((totalSteps / UInt64(Self.epochSteps)) % 2)
                        recoveryCheckpointBanks[slot].metadata = nil
                        let metadata = recoveryMetadata()
                        encodeRecoveryCheckpoint(into: commandBuffer, slot: slot)
                        pendingCheckpoint = PendingRecoveryCheckpoint(
                            slot: slot, metadata: metadata
                        )
                    }
                    break
                }
            }
            if let pendingMetricObservation {
                encodeQuantumMeasurement(
                    into: commandBuffer,
                    slot: metricReadbackSlots[pendingMetricObservation.slotIndex]
                )
            }
        }
        if resetEncoded, pendingCheckpoint == nil, !recoveryCheckpointBanks.isEmpty {
            recoveryCheckpointBanks[0].metadata = nil
            let metadata = recoveryMetadata()
            encodeRecoveryCheckpoint(into: commandBuffer, slot: 0)
            pendingCheckpoint = PendingRecoveryCheckpoint(slot: 0, metadata: metadata)
        }

        encodeRender(view: view, into: commandBuffer, settings: frameSettings)
        if let pendingMetricObservation {
            attachMetricObservation(pendingMetricObservation, to: commandBuffer)
        }
        attachGPUTiming(to: commandBuffer)
        let submittedStep = totalSteps
        let submittedEpoch = submissionEpoch
        let submittedCheckpoint = pendingCheckpoint
        lastCPUEncodeMilliseconds = max(
            CFAbsoluteTimeGetCurrent() - encodingStartedAt,
            0
        ) * 1_000
        unfinishedCommandBuffers += 1
        commandBuffer.addCompletedHandler { [weak self, submittedCheckpoint] buffer in
            let status = buffer.status
            let gpuMilliseconds = max(buffer.gpuEndTime - buffer.gpuStartTime, 0) * 1_000
            let phaseTimings = buffer.phaseSamples.map {
                MetalPhaseTiming(phase: $0.phase, gpuMilliseconds: $0.milliseconds)
            }
            let errorDescription = buffer.error.map { error in
                "\(error.localizedDescription) [\(String(describing: error))]"
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.shouldSuppressCompletionForSyntheticStall(
                    submittedStep: submittedStep
                ) {
                    // The synthetic probe hides semantic completion only after Metal's
                    // real feedback has retired the resources. Remember that fact so
                    // the watchdog can drain its simulated queue without weakening the
                    // production retirement rule.
                    self.syntheticRetiredCommandBuffers += 1
                    return
                }
                self.completeSubmission(
                    status: status,
                    errorDescription: errorDescription,
                    submittedStep: submittedStep,
                    epoch: submittedEpoch,
                    checkpoint: submittedCheckpoint,
                    gpuMilliseconds: gpuMilliseconds,
                    phaseTimings: phaseTimings
                )
            }
        }
        commandBuffer.commit()
        publishRuntimeTelemetry()
    }

    private func shouldSuppressCompletionForSyntheticStall(
        submittedStep: UInt64
    ) -> Bool {
        if syntheticStallInjected { return recoveryCount == 0 }
        guard let syntheticStallStep,
              submittedStep >= syntheticStallStep else { return false }
        syntheticStallInjected = true
        return true
    }

    private func attachMetricObservation(
        _ pending: PendingMetricObservation,
        to commandBuffer: Metal4CommandBufferContext
    ) {
        commandBuffer.addCompletedHandler { [weak self] buffer in
            let succeeded = buffer.status == .completed && buffer.error == nil
            Task { @MainActor [weak self] in
                guard succeeded else {
                    self?.metricSlotsInFlight[pending.slotIndex] = false
                    return
                }
                self?.completeMetricObservation(pending)
            }
        }
    }

    private func completeSubmission(
        status: Metal4CommandStatus,
        errorDescription: String?,
        submittedStep: UInt64,
        epoch: UInt64,
        checkpoint: PendingRecoveryCheckpoint?,
        gpuMilliseconds: Double,
        phaseTimings: [MetalPhaseTiming]
    ) {
        unfinishedCommandBuffers = max(unfinishedCommandBuffers - 1, 0)
        lastCompletionTime = CFAbsoluteTimeGetCurrent()
        guard epoch == submissionEpoch else {
            if submissionFaulted, unfinishedCommandBuffers == 0 {
                restoreLatestRecoveryCheckpoint()
            }
            publishRuntimeTelemetry()
            return
        }
        if status == .completed, errorDescription == nil {
            lastTotalGPUMilliseconds = gpuMilliseconds
            updateInteractiveInFlightSubmissionLimit(gpuMilliseconds: gpuMilliseconds)
            lastPhaseTimings = phaseTimings
            if Self.gpuTimingLogEnabled, !phaseTimings.isEmpty {
                let phases = phaseTimings.map {
                    "\($0.phase)=\(String(format: "%.3f", $0.gpuMilliseconds))"
                }.joined(separator: ",")
                print(
                    "metal4_gpu_frame_ms=\(String(format: "%.3f", gpuMilliseconds)) " +
                    "step=\(submittedStep) phases=\(phases)"
                )
            }
            if let syntheticFaultStep,
               submittedStep >= syntheticFaultStep,
               !syntheticFaultInjected {
                syntheticFaultInjected = true
                handleSubmissionFailure(
                    "Synthetic Metal completion fault at submitted step \(submittedStep)."
                )
                publishRuntimeTelemetry()
                return
            }
            gpuCompletedSteps = max(gpuCompletedSteps, submittedStep)
            scientificallyCommittedSteps = gpuCompletedSteps
            if let checkpoint {
                recoveryCheckpointBanks[checkpoint.slot].metadata = checkpoint.metadata
                checkpointStep = max(checkpointStep, checkpoint.metadata.step)
            }
            updateThroughput()
        } else {
            handleSubmissionFailure(
                "Metal command buffer ended with \(status): \(errorDescription ?? "no diagnostic")"
            )
        }
        publishRuntimeTelemetry()
    }

    private func handleSubmissionFailure(_ message: String) {
        guard !submissionFaulted else { return }
        submissionFaulted = true
        submissionEpoch &+= 1
        recoveryCount &+= 1
        lastMetalError = message
        // A timeout is not proof that Metal has retired the submitted work. Keep the
        // old epoch's resources quarantined until every real feedback callback arrives;
        // restoring into buffers that an overdue command buffer can still write causes
        // visible tile corruption and can damage causal state.
        if unfinishedCommandBuffers == 0 {
            restoreLatestRecoveryCheckpoint()
        }
        interactiveInFlightSubmissionLimit = Self.maximumInteractiveInFlightSubmissions
        publishRuntimeTelemetry(force: true)
    }

    private func inspectCompletionWatchdog() {
        guard unfinishedCommandBuffers > 0,
              CFAbsoluteTimeGetCurrent() - lastCompletionTime > 5 else { return }
        if syntheticRetiredCommandBuffers > 0 {
            unfinishedCommandBuffers = max(
                unfinishedCommandBuffers - syntheticRetiredCommandBuffers,
                0
            )
            syntheticRetiredCommandBuffers = 0
        }
        handleSubmissionFailure(
            "Metal completion watchdog exceeded 5 seconds with \(unfinishedCommandBuffers) " +
            "unfinished buffers; submission is paused until Metal retires the old epoch."
        )
    }

    private func updateThroughput() {
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - telemetrySampleTime
        guard elapsed >= 0.25 else { return }
        measuredStepsPerSecond = Double(scientificallyCommittedSteps - telemetrySampleStep) /
            max(elapsed, 0.000_001)
        telemetrySampleTime = now
        telemetrySampleStep = scientificallyCommittedSteps
    }

    private func updateInteractiveInFlightSubmissionLimit(gpuMilliseconds: Double) {
        if gpuMilliseconds <= Self.singleBufferGPUThresholdMilliseconds {
            interactiveInFlightSubmissionLimit = 1
        } else if gpuMilliseconds >= Self.doubleBufferGPUThresholdMilliseconds {
            interactiveInFlightSubmissionLimit = Self.maximumInteractiveInFlightSubmissions
        }
    }

    private func publishRuntimeTelemetry(force: Bool = false) {
        let now = CFAbsoluteTimeGetCurrent()
        guard force || now - lastRuntimeTelemetryPublicationTime >=
            Self.runtimeTelemetryPublicationInterval else { return }
        lastRuntimeTelemetryPublicationTime = now
        onRuntimeTelemetry?(RendererRuntimeTelemetry(
            backendVersion: "Metal 4",
            tuningProfile: tuningProfile,
            scheduledStep: totalSteps,
            gpuCompletedStep: gpuCompletedSteps,
            scientificallyCommittedStep: scientificallyCommittedSteps,
            stepsPerSecond: measuredStepsPerSecond,
            unfinishedCommandBuffers: unfinishedCommandBuffers,
            maximumCommandBuffers: interactiveInFlightSubmissionLimit,
            checkpointStep: checkpointStep,
            lastRestoredCheckpointStep: lastRestoredCheckpointStep,
            recoveryCount: recoveryCount,
            recoveryEpoch: submissionEpoch,
            cpuEncodeMilliseconds: lastCPUEncodeMilliseconds,
            totalGPUMilliseconds: lastTotalGPUMilliseconds,
            phaseTimings: lastPhaseTimings,
            pipelineArchive: PipelineArchiveTelemetry(
                loaded: pipelineBuildTelemetry.archiveLoaded,
                hits: pipelineBuildTelemetry.archiveHits,
                misses: pipelineBuildTelemetry.archiveMisses,
                pipelineCount: pipelineBuildTelemetry.pipelineCount,
                compileMilliseconds: pipelineBuildTelemetry.compilationMilliseconds,
                error: pipelineBuildTelemetry.archiveErrorDescription
            ),
            residency: ResidencyTelemetry(
                residentBytes: commandQueue.residentBytes,
                allocatorSlots: Metal4ExecutionContext.maximumInFlightSubmissions,
                allocatorHighWatermark: commandQueue.allocatorHighWatermark,
                uniformArenaHighWaterBytes: commandQueue.uniformArenaHighWaterBytes
            ),
            lastError: lastMetalError
        ))
    }

    private func checkpointTextureSources() -> [MTLTexture] {
        [
            state, genomeA, genomeB, genomeC, ecology, eventState,
            environmentState, mechanicalState, quantumState, checkpointState,
            developmentalField
        ]
    }

    private func checkpointBufferSources() -> [MTLBuffer] {
        [
            agentState, agentOccupancy, cellState, cellOccupancy, cellIdentities,
            cellParentIDs, programInteractions, ownerCellHeads, ownerCellNext,
            cellComponentParents, cellComponentCounts, cellComponentAccumulation,
            cellComponentOwners, cellComponentPrograms, cellComponentProgramSources,
            cellComponentProgramTargets, componentCellHeads, componentCellNext,
            ownerPrimaryRoots, cellAggregates, heritablePrograms, programSlots,
            developmentalGenomes, regulatoryNodes, regulatoryEdges, regulatoryStates,
            resonanceGenomes, membraneVertices, cellSpatialHashHeads, cellSpatialHashNext,
            contactWorkState, cellTopologySignatures, cellContactEffects, membraneContactEffects,
            cellJunctions, cellEnergyExchange,
            energyAudit, invariantState, invariantScratch, identityCounters, lineageEvents,
            mechanicalForcing, qualificationTargetState, qualificationTargetMeasurement
        ]
    }

    private func registerMetal4Residency(view: MTKView) {
        let pipelines: [any MTLAllocation] = [
            initializePipeline, initializeQuantumPipeline, expandWorldPipeline,
            expandQuantumPipeline, initializeMechanicalPipeline, expandMechanicalPipeline,
            evolveMechanicalPipeline, reactionPipeline, quantumCouplingPipeline,
            quantumPipeline, damagePipeline, damageCellPipeline,
            markDamagedComponentsPipeline,
            selectQualificationTargetPipeline, damageSelectedTargetWorldPipeline,
            damageSelectedTargetCellsPipeline, markSelectedTargetChallengedPipeline,
            measureQualificationTargetPipeline,
            brushPipeline, measurementPipeline, quantumMeasurementPipeline,
            initializeAgentPipeline, nucleateFounderPipeline, evolveAgentPipeline,
            injectFounderPipeline, expandAgentPipeline, collectAgentObservationPipeline,
            collectCellObservationPipeline, collectProgramMetricPipeline,
            resetActiveComponentDispatchPipeline, compactActiveComponentsPipeline,
            prepareActiveComponentDispatchPipeline, compactActiveCellsPipeline,
            evolveCellPipeline,
            evolveMembranePipeline, clearCellSpatialHashPipeline,
            clearActiveCellContactEffectsPipeline,
            buildCellSpatialHashPipeline, resetMembraneContactWorkPipeline,
            buildMembraneContactPairsPipeline, prepareMembraneContactDispatchPipeline,
            detectCellTopologyChangesPipeline,
            clearOwnerCellListsPipeline,
            buildOwnerCellListsPipeline, resolveCellContactsPipeline,
            applyCellContactEffectsPipeline, measureCellMembraneExposurePipeline,
            initializeCellComponentsPipeline, unionCellComponentsPipeline,
            compressCellComponentsPipeline, buildCellComponentListsPipeline,
            accumulateCellComponentsPipeline, selectPrimaryCellComponentsPipeline,
            assignCellComponentOwnersPipeline, reassignCellComponentsPipeline,
            finalizeCellTopologyPipeline,
            divideAndReduceCellPipeline, initializeInvariantPipeline,
            clearInvariantScratchPipeline, auditContactMomentumPipeline,
            accumulateSimulationInvariantsPipeline, finalizeSimulationInvariantsPipeline,
            resetRenderDrawArgumentsPipeline, compactCellRenderPipeline,
            compactJunctionRenderPipeline, finalizeRenderDrawArgumentsPipeline,
            cellRenderPipeline, cellMeshRenderPipeline, junctionRenderPipeline,
            bloomPrefilterPipeline,
            compositePipeline, spinorDisplayPipeline
        ]
        let textures: [any MTLAllocation] = [
            state, reactionState, genomeA, reactionGenomeA, genomeB, reactionGenomeB,
            ecology, reactionEcology, genomeC, reactionGenomeC, checkpointState,
            eventState, reactionEventState, environmentState, reactionEnvironmentState,
            developmentalField, reactionDevelopmentalField,
            mechanicalState, reactionMechanicalState, quantumState, reactionQuantumState,
            quantumCoupling
        ]
        var buffers = checkpointBufferSources()
        buffers.append(contentsOf: [
            reactionAgentState, reactionCellState,
            activeComponentIndices, activeComponentCount, activeComponentDispatchArguments,
            activeCellIndices, activeCellCount, activeCellDispatchArguments,
            membraneContactPairs, contactPairDispatchArguments
        ])
        buffers.append(contentsOf: renderSubmissionResources.flatMap(\.buffers))
        buffers.append(contentsOf: agentObservationBuffers)
        buffers.append(contentsOf: cellObservationBuffers)
        buffers.append(contentsOf: lineageEventObservationBuffers)
        buffers.append(contentsOf: identityCounterObservationBuffers)
        for slot in metricReadbackSlots {
            buffers.append(contentsOf: [
                slot.metrics, slot.quantumNorm, slot.agentState, slot.agentOccupancy,
                slot.cellAggregates, slot.programRecords, slot.identityCounters,
                slot.energyAudit
            ])
        }
        commandQueue.register(
            pipelines + scaleSurfacePipelines.map { $0 as any MTLAllocation } +
                textures + buffers.map { $0 as any MTLAllocation }
        )
        if let layer = view.layer as? CAMetalLayer {
            commandQueue.registerPresentationResidency(layer.residencySet)
        }
        if #available(macOS 26.4, *) {
            commandQueue.registerPresentationResidency(view.residencySet)
        }
    }

    private func makeRecoveryCheckpointBanks() throws -> [RecoveryCheckpointBank] {
        let textureSources = checkpointTextureSources()
        let bufferSources = checkpointBufferSources()
        return try (0..<2).map { bankIndex in
            let textures = try textureSources.enumerated().map { index, source in
                let descriptor = MTLTextureDescriptor()
                descriptor.textureType = source.textureType
                descriptor.pixelFormat = source.pixelFormat
                descriptor.width = source.width
                descriptor.height = source.height
                descriptor.depth = source.depth
                descriptor.mipmapLevelCount = source.mipmapLevelCount
                descriptor.sampleCount = source.sampleCount
                descriptor.arrayLength = source.arrayLength
                descriptor.storageMode = .private
                descriptor.usage = [.shaderRead, .shaderWrite]
                guard let texture = device.makeTexture(descriptor: descriptor) else {
                    throw EvolutionRendererError.resourceAllocation(
                        "recovery checkpoint texture \(bankIndex):\(index)"
                    )
                }
                texture.label = "Recovery checkpoint \(bankIndex) texture \(index)"
                return texture
            }
            let buffers = try bufferSources.enumerated().map { index, source in
                guard let buffer = device.makeBuffer(
                    length: source.length,
                    options: .storageModePrivate
                ) else {
                    throw EvolutionRendererError.resourceAllocation(
                        "recovery checkpoint buffer \(bankIndex):\(index)"
                    )
                }
                buffer.label = "Recovery checkpoint \(bankIndex) buffer \(index)"
                return buffer
            }
            return RecoveryCheckpointBank(textures: textures, buffers: buffers, metadata: nil)
        }
    }

    private func recoveryMetadata() -> RecoveryCheckpointMetadata {
        RecoveryCheckpointMetadata(
            step: totalSteps,
            quantumStep: quantumStep,
            generation: generation,
            resetToken: appliedResetToken,
            addColonyToken: appliedAddColonyToken,
            expansionToken: appliedExpansionToken,
            lineageSequence: lineageEventDeliveryState.checkpoint(),
            evaluator: evaluator,
            snapshot: latestSnapshot
        )
    }

    private func captureInitialRecoveryCheckpoint() throws {
        guard !recoveryCheckpointBanks.isEmpty,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw EvolutionRendererError.resourceAllocation("initial recovery checkpoint")
        }
        commandBuffer.label = "Initial recovery checkpoint"
        encodeRecoveryCheckpoint(into: commandBuffer, slot: 0)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error { throw error }
        recoveryCheckpointBanks[0].metadata = recoveryMetadata()
        checkpointStep = totalSteps
    }

    private func encodeRecoveryCheckpoint(into commandBuffer: Metal4CommandBufferContext, slot: Int) {
        guard recoveryCheckpointBanks.indices.contains(slot),
              let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.label = "Capture causal recovery checkpoint"
        for (source, destination) in zip(
            checkpointTextureSources(), recoveryCheckpointBanks[slot].textures
        ) {
            copyTexture(source, to: destination, with: blit)
        }
        for (source, destination) in zip(
            checkpointBufferSources(), recoveryCheckpointBanks[slot].buffers
        ) {
            blit.copy(
                from: source, sourceOffset: 0,
                to: destination, destinationOffset: 0,
                size: min(source.length, destination.length)
            )
        }
        blit.endEncoding()
    }

    private func copyTexture(
        _ source: MTLTexture,
        to destination: MTLTexture,
        with blit: Metal4BlitCommandEncoderAdapter
    ) {
        for slice in 0..<source.arrayLength {
            for level in 0..<source.mipmapLevelCount {
                blit.copy(
                    from: source,
                    sourceSlice: slice,
                    sourceLevel: level,
                    sourceOrigin: .init(x: 0, y: 0, z: 0),
                    sourceSize: .init(
                        width: max(source.width >> level, 1),
                        height: max(source.height >> level, 1),
                        depth: max(source.depth >> level, 1)
                    ),
                    to: destination,
                    destinationSlice: slice,
                    destinationLevel: level,
                    destinationOrigin: .init(x: 0, y: 0, z: 0)
                )
            }
        }
    }

    private func restoreLatestRecoveryCheckpoint() {
        guard submissionFaulted, unfinishedCommandBuffers == 0,
              let selected = recoveryCheckpointBanks.enumerated().compactMap({ index, bank in
                bank.metadata.map { (index, $0) }
              }).max(by: { $0.1.step < $1.1.step }) else { return }
        do {
            try commandQueue.rebuildQueueAndAllocators()
        } catch {
            lastMetalError = (lastMetalError ?? "Metal failure") +
                " Recovery queue reconstruction failed: \(error.localizedDescription)."
            return
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder() else {
            lastMetalError = (lastMetalError ?? "Metal failure") +
                " Recovery resource allocation failed."
            return
        }
        commandBuffer.label = "Restore causal recovery checkpoint"
        let bank = recoveryCheckpointBanks[selected.0]
        let currentTextures = checkpointTextureSources()
        for (source, destination) in zip(bank.textures, currentTextures) {
            copyTexture(source, to: destination, with: blit)
        }
        let reactionTextures: [(Int, MTLTexture)] = [
            (0, reactionState), (1, reactionGenomeA), (2, reactionGenomeB),
            (3, reactionGenomeC), (4, reactionEcology), (5, reactionEventState),
            (6, reactionEnvironmentState), (7, reactionMechanicalState),
            (8, reactionQuantumState), (10, reactionDevelopmentalField)
        ]
        for (sourceIndex, destination) in reactionTextures {
            copyTexture(bank.textures[sourceIndex], to: destination, with: blit)
        }
        for (source, destination) in zip(bank.buffers, checkpointBufferSources()) {
            blit.copy(
                from: source, sourceOffset: 0,
                to: destination, destinationOffset: 0,
                size: min(source.length, destination.length)
            )
        }
        blit.copy(
            from: bank.buffers[0], sourceOffset: 0,
            to: reactionAgentState, destinationOffset: 0,
            size: min(bank.buffers[0].length, reactionAgentState.length)
        )
        blit.copy(
            from: bank.buffers[2], sourceOffset: 0,
            to: reactionCellState, destinationOffset: 0,
            size: min(bank.buffers[2].length, reactionCellState.length)
        )
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed, commandBuffer.error == nil else {
            lastMetalError = (lastMetalError ?? "Metal failure") +
                " Checkpoint restore failed: \(commandBuffer.error?.localizedDescription ?? "unknown Metal status")."
            return
        }

        let metadata = selected.1
        totalSteps = metadata.step
        gpuCompletedSteps = metadata.step
        scientificallyCommittedSteps = metadata.step
        quantumStep = metadata.quantumStep
        generation = metadata.generation
        appliedResetToken = metadata.resetToken
        appliedAddColonyToken = metadata.addColonyToken
        appliedExpansionToken = metadata.expansionToken
        evaluator = metadata.evaluator
        latestSnapshot = metadata.snapshot
        lineageEventDeliveryState.restore(sequence: metadata.lineageSequence)
        checkpointStep = metadata.step
        lastRestoredCheckpointStep = metadata.step
        metricSlotsInFlight = Array(repeating: false, count: Self.metricReadbackRingSize)
        telemetrySampleTime = CFAbsoluteTimeGetCurrent()
        telemetrySampleStep = metadata.step
        measuredStepsPerSecond = 0
        lastCompletionTime = CFAbsoluteTimeGetCurrent()
        lastMetalError = nil
        submissionFaulted = false
        onSnapshot?(metadata.snapshot)
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

    private func attachGPUTiming(to commandBuffer: Metal4CommandBufferContext) {
        guard Self.gpuFrameTimingEnabled else { return }
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

    private func encodeInitialization(into commandBuffer: Metal4CommandBufferContext, settings: RendererSettings) {
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
        encoder.setTexture(developmentalField, index: 7)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
        dispatchWorlds(encoder, pipeline: initializePipeline)
        encoder.setComputePipelineState(initializeMechanicalPipeline)
        encoder.setTexture(mechanicalState, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
        dispatchWorlds(encoder, pipeline: initializeMechanicalPipeline)
        encoder.endEncoding()
        if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.label = "Initialize fixed-point simulation ledgers"
            blitEncoder.fill(
                buffer: mechanicalForcing,
                range: 0..<mechanicalForcing.length,
                value: 0
            )
            blitEncoder.fill(
                buffer: cellEnergyExchange,
                range: 0..<cellEnergyExchange.length,
                value: 0
            )
            blitEncoder.fill(
                buffer: energyAudit,
                range: 0..<energyAudit.length,
                value: 0
            )
            blitEncoder.fill(
                buffer: contactWorkState,
                range: 0..<contactWorkState.length,
                value: 0
            )
            blitEncoder.fill(
                buffer: cellTopologySignatures,
                range: 0..<cellTopologySignatures.length,
                value: 0
            )
            blitEncoder.fill(
                buffer: contactPairDispatchArguments,
                range: 0..<contactPairDispatchArguments.length,
                value: 0
            )
            blitEncoder.fill(
                buffer: qualificationTargetState,
                range: 0..<qualificationTargetState.length,
                value: 0
            )
            blitEncoder.fill(
                buffer: qualificationTargetMeasurement,
                range: 0..<qualificationTargetMeasurement.length,
                value: 0
            )
            blitEncoder.endEncoding()
        }
        encodeAgentInitialization(into: commandBuffer, settings: settings)
        encodeInvariantInitialization(into: commandBuffer)
        encodeQuantumInitialization(into: commandBuffer, settings: settings)
        copyAllSlices(from: state, to: checkpointState, commandBuffer: commandBuffer)
    }

    private func encodeInvariantInitialization(into commandBuffer: Metal4CommandBufferContext) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Initialize invariant enforcement"
        encoder.setComputePipelineState(initializeInvariantPipeline)
        encoder.setBuffer(invariantState, offset: 0, index: 0)
        encoder.setBuffer(invariantScratch, offset: 0, index: 1)
        encoder.dispatchThreads(
            MTLSize(width: Self.invariantScratchCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(
                width: min(initializeInvariantPipeline.maxTotalThreadsPerThreadgroup, 256),
                height: 1,
                depth: 1
            )
        )
        encoder.endEncoding()
    }

    private func encodeAgentInitialization(
        into commandBuffer: Metal4CommandBufferContext,
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
        encoder.setBuffer(programSlots, offset: 0, index: 26)
        encoder.setBuffer(componentCellHeads, offset: 0, index: 27)
        encoder.setBuffer(componentCellNext, offset: 0, index: 28)
        encoder.setBuffer(cellJunctions, offset: 0, index: 29)
        encoder.setBuffer(membraneContactEffects, offset: 0, index: 30)
        dispatchAgents(encoder, pipeline: initializeAgentPipeline)
        encoder.endEncoding()
    }

    private func encodeFounderInjection(
        into commandBuffer: Metal4CommandBufferContext,
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
        encoder.setBuffer(programSlots, offset: 0, index: 18)
        encoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
        encoder.memoryBarrier(resources: [agentOccupancy])
        encodeActiveComponentCompaction(encoder)
        encoder.endEncoding()
    }

    private func encodeQuantumInitialization(
        into commandBuffer: Metal4CommandBufferContext,
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
        into commandBuffer: Metal4CommandBufferContext,
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
        encoder.setTexture(developmentalField, index: 14)
        encoder.setTexture(reactionDevelopmentalField, index: 15)
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

    private func encodeAgentExpansion(into commandBuffer: Metal4CommandBufferContext) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Keep organisms fixed in the expanding world"
        encoder.setComputePipelineState(expandAgentPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        dispatchAgents(encoder, pipeline: expandAgentPipeline)
        encoder.endEncoding()
    }

    private func encodeSimulationStep(
        into commandBuffer: Metal4CommandBufferContext,
        settings: RendererSettings,
        auditInvariants: Bool = false
    ) {
        if auditInvariants {
            encodeInvariantScratchReset(into: commandBuffer)
        }
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
        encoder.setTexture(developmentalField, index: 15)
        encoder.setTexture(reactionDevelopmentalField, index: 16)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
        encoder.setBuffer(cellEnergyExchange, offset: 0, index: 1)
        dispatchWorlds(encoder, pipeline: reactionPipeline)
        encoder.endEncoding()
        commandBuffer.writeTimestamp(ending: "chemistry")
        swapWorldReactionState()
        encodeAgentStep(
            into: commandBuffer,
            settings: settings,
            auditInvariants: auditInvariants
        )
        if auditInvariants {
            encodeSimulationInvariantAudit(into: commandBuffer, settings: settings)
        }
    }

    private func encodeAgentStep(
        into commandBuffer: Metal4CommandBufferContext,
        settings: RendererSettings,
        auditInvariants: Bool
    ) {
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
        encoder.setBuffer(programSlots, offset: 0, index: 18)
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
            cellIdentities, heritablePrograms, programSlots
        ])

        encodeActiveComponentCompaction(encoder)
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
        encoder.setBuffer(programSlots, offset: 0, index: 9)
        encoder.setTexture(state, index: 0)
        encoder.setTexture(ecology, index: 1)
        encoder.setTexture(environmentState, index: 2)
        encoder.setTexture(mechanicalState, index: 3)
        encoder.setBuffer(activeComponentIndices, offset: 0, index: 10)
        encoder.setBuffer(activeComponentCount, offset: 0, index: 11)
        dispatchActiveComponents(encoder, pipeline: evolveAgentPipeline)
        encoder.memoryBarrier(resources: [
            reactionAgentState, agentOccupancy, lineageEvents, identityCounters, programSlots
        ])
        swap(&agentState, &reactionAgentState)
        encoder.endEncoding()
        commandBuffer.writeTimestamp(ending: "component mechanics")
        encodeCellStep(
            into: commandBuffer,
            settings: settings,
            auditInvariants: auditInvariants
        )
    }

    private func encodeCellStep(
        into commandBuffer: Metal4CommandBufferContext,
        settings: RendererSettings,
        auditInvariants: Bool
    ) {
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.label = "Reset per-step energy conservation audit"
            blit.fill(buffer: energyAudit, range: 0..<energyAudit.length, value: 0)
            blit.endEncoding()
        }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Cell energetics, electrophysiology, oscillators, and mechanical waves"
        var uniforms = makeUniforms(settings: settings)
        encodeActiveCellCompaction(encoder)
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
        encoder.setBuffer(programSlots, offset: 0, index: 18)
        encoder.setBuffer(identityCounters, offset: 0, index: 19)
        encoder.setBuffer(cellEnergyExchange, offset: 0, index: 20)
        encoder.setBuffer(energyAudit, offset: 0, index: 21)
        encoder.setBuffer(cellJunctions, offset: 0, index: 22)
        encoder.setBuffer(contactWorkState, offset: 0, index: 23)
        encoder.setTexture(state, index: 0)
        encoder.setTexture(ecology, index: 1)
        encoder.setTexture(environmentState, index: 2)
        encoder.setTexture(eventState, index: 3)
        encoder.setTexture(mechanicalState, index: 4)
        encoder.setTexture(developmentalField, index: 5)
        dispatchCells(encoder, pipeline: evolveCellPipeline)
        encoder.memoryBarrier(resources: [
            reactionCellState, cellOccupancy, cellIdentities, programSlots,
            identityCounters, mechanicalForcing, cellEnergyExchange, energyAudit,
            contactWorkState
        ])
        swap(&cellState, &reactionCellState)

        encoder.setComputePipelineState(evolveMembranePipeline)
        encoder.setBuffer(cellState, offset: 0, index: 0)
        encoder.setBuffer(reactionCellState, offset: 0, index: 1)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 2)
        encoder.setBuffer(membraneVertices, offset: 0, index: 3)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 4)
        encoder.setBuffer(cellIdentities, offset: 0, index: 5)
        encoder.setBuffer(agentState, offset: 0, index: 6)
        encoder.setBuffer(heritablePrograms, offset: 0, index: 7)
        encoder.setBuffer(programSlots, offset: 0, index: 8)
        dispatchCells(encoder, pipeline: evolveMembranePipeline)
        encoder.memoryBarrier(resources: [reactionCellState, membraneVertices])
        swap(&cellState, &reactionCellState)
        encoder.writeTimestamp(ending: "cell physiology")

        encodeCellNeighborhoodIndex(encoder, uniforms: &uniforms)

        encoder.setComputePipelineState(resetMembraneContactWorkPipeline)
        encoder.setBuffer(contactWorkState, offset: 0, index: 0)
        encoder.setBuffer(activeCellCount, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 2)
        encoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
        encoder.memoryBarrier(resources: [contactWorkState])

        encoder.setComputePipelineState(buildMembraneContactPairsPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBuffer(cellState, offset: 0, index: 2)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 3)
        encoder.setBuffer(cellSpatialHashHeads, offset: 0, index: 4)
        encoder.setBuffer(cellSpatialHashNext, offset: 0, index: 5)
        encoder.setBuffer(cellIdentities, offset: 0, index: 6)
        encoder.setBuffer(membraneContactPairs, offset: 0, index: 7)
        encoder.setBuffer(contactWorkState, offset: 0, index: 8)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 9)
        dispatchCells(encoder, pipeline: buildMembraneContactPairsPipeline)
        encoder.memoryBarrier(resources: [membraneContactPairs, contactWorkState])

        encoder.setComputePipelineState(prepareMembraneContactDispatchPipeline)
        encoder.setBuffer(contactWorkState, offset: 0, index: 0)
        encoder.setBuffer(contactPairDispatchArguments, offset: 0, index: 1)
        encoder.setBuffer(invariantState, offset: 0, index: 2)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 3)
        encoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
        encoder.memoryBarrier(resources: [
            contactWorkState, contactPairDispatchArguments, invariantState
        ])

        encoder.setComputePipelineState(resolveCellContactsPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBuffer(cellState, offset: 0, index: 2)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 3)
        encoder.setBuffer(membraneVertices, offset: 0, index: 4)
        encoder.setBuffer(membraneContactPairs, offset: 0, index: 5)
        encoder.setBuffer(contactWorkState, offset: 0, index: 6)
        encoder.setBuffer(cellContactEffects, offset: 0, index: 7)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 8)
        encoder.setBuffer(cellIdentities, offset: 0, index: 9)
        encoder.setBuffer(heritablePrograms, offset: 0, index: 10)
        encoder.setBuffer(cellJunctions, offset: 0, index: 11)
        encoder.setBuffer(membraneContactEffects, offset: 0, index: 12)
        encoder.setBuffer(programSlots, offset: 0, index: 13)
        encoder.setBuffer(energyAudit, offset: 0, index: 14)
        encoder.setBuffer(identityCounters, offset: 0, index: 15)
        encoder.setBuffer(cellTopologySignatures, offset: 0, index: 16)
        encoder.setBuffer(developmentalGenomes, offset: 0, index: 17)
        encoder.dispatchThreadgroups(
            indirectBuffer: contactPairDispatchArguments,
            indirectBufferOffset: 0,
            threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1)
        )
        encoder.memoryBarrier(resources: [
            cellContactEffects, membraneContactEffects, cellJunctions, energyAudit,
            identityCounters, contactWorkState, cellTopologySignatures, cellIdentities
        ])

        encoder.setComputePipelineState(detectCellTopologyChangesPipeline)
        encoder.setBuffer(cellTopologySignatures, offset: 0, index: 0)
        encoder.setBuffer(contactWorkState, offset: 0, index: 1)
        dispatchCells(encoder, pipeline: detectCellTopologyChangesPipeline)
        encoder.memoryBarrier(resources: [cellTopologySignatures, contactWorkState])

        if auditInvariants {
            encoder.setComputePipelineState(auditContactMomentumPipeline)
            encoder.setBuffer(cellContactEffects, offset: 0, index: 0)
            encoder.setBuffer(invariantScratch, offset: 0, index: 1)
            dispatchCells(encoder, pipeline: auditContactMomentumPipeline)
            encoder.memoryBarrier(resources: [invariantScratch])
        }

        encoder.setComputePipelineState(applyCellContactEffectsPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(cellState, offset: 0, index: 1)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 2)
        encoder.setBuffer(membraneVertices, offset: 0, index: 3)
        encoder.setBuffer(cellContactEffects, offset: 0, index: 4)
        encoder.setBuffer(cellIdentities, offset: 0, index: 5)
        encoder.setBuffer(membraneContactEffects, offset: 0, index: 6)
        encoder.setBuffer(energyAudit, offset: 0, index: 7)
        dispatchCells(encoder, pipeline: applyCellContactEffectsPipeline)
        encoder.memoryBarrier(resources: [cellState, membraneVertices, energyAudit])
        encoder.writeTimestamp(ending: "contact")

        encoder.setComputePipelineState(measureCellMembraneExposurePipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(cellState, offset: 0, index: 1)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 2)
        encoder.setBuffer(membraneVertices, offset: 0, index: 3)
        encoder.setBuffer(cellSpatialHashHeads, offset: 0, index: 4)
        encoder.setBuffer(cellSpatialHashNext, offset: 0, index: 5)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 6)
        encoder.setBuffer(cellIdentities, offset: 0, index: 7)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 8)
        encoder.setBuffer(developmentalGenomes, offset: 0, index: 9)
        encoder.setBuffer(programSlots, offset: 0, index: 10)
        dispatchCells(encoder, pipeline: measureCellMembraneExposurePipeline)
        encoder.memoryBarrier(resources: [cellState, membraneVertices])

        encodeCellConnectivity(encoder, uniforms: &uniforms)
        encodeActiveComponentCompaction(encoder)
        encodeOwnerCellLists(encoder)
        encoder.writeTimestamp(ending: "topology")

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
        encoder.setBuffer(programSlots, offset: 0, index: 15)
        encoder.setBuffer(developmentalGenomes, offset: 0, index: 16)
        encoder.setBuffer(regulatoryNodes, offset: 0, index: 17)
        encoder.setBuffer(regulatoryEdges, offset: 0, index: 18)
        encoder.setBuffer(heritablePrograms, offset: 0, index: 19)
        encoder.setBuffer(lineageEvents, offset: 0, index: 20)
        encoder.setBuffer(activeComponentIndices, offset: 0, index: 21)
        encoder.setBuffer(activeComponentCount, offset: 0, index: 22)
        encoder.setBuffer(cellJunctions, offset: 0, index: 23)
        encoder.setBuffer(contactWorkState, offset: 0, index: 24)
        dispatchActiveComponents(encoder, pipeline: divideAndReduceCellPipeline)
        encoder.memoryBarrier(resources: [
            agentState, cellState, cellOccupancy, cellIdentities, cellAggregates,
            ownerCellHeads, ownerCellNext, regulatoryStates, membraneVertices,
            identityCounters, programInteractions, programSlots, developmentalGenomes,
            regulatoryNodes, regulatoryEdges, resonanceGenomes, heritablePrograms,
            lineageEvents, cellJunctions, contactWorkState
        ])
        encoder.writeTimestamp(ending: "division + reduction")

        encoder.setComputePipelineState(evolveMechanicalPipeline)
        encoder.setTexture(mechanicalState, index: 0)
        encoder.setTexture(reactionMechanicalState, index: 1)
        encoder.setTexture(environmentState, index: 2)
        encoder.setTexture(developmentalField, index: 3)
        encoder.setBuffer(mechanicalForcing, offset: 0, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 1)
        dispatchWorlds(encoder, pipeline: evolveMechanicalPipeline)
        encoder.writeTimestamp(ending: "field mechanics")
        encoder.endEncoding()
        swap(&mechanicalState, &reactionMechanicalState)
    }

    private func encodeInvariantScratchReset(into commandBuffer: Metal4CommandBufferContext) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Reset invariant reduction scratch"
        encoder.setComputePipelineState(clearInvariantScratchPipeline)
        encoder.setBuffer(invariantScratch, offset: 0, index: 0)
        encoder.dispatchThreads(
            MTLSize(width: Self.invariantScratchCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(
                width: min(clearInvariantScratchPipeline.maxTotalThreadsPerThreadgroup, 256),
                height: 1,
                depth: 1
            )
        )
        encoder.endEncoding()
    }

    private func encodeSimulationInvariantAudit(
        into commandBuffer: Metal4CommandBufferContext,
        settings: RendererSettings
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Enforce simulation invariants"
        var uniforms = makeUniforms(settings: settings)
        encoder.setComputePipelineState(accumulateSimulationInvariantsPipeline)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 0)
        encoder.setBuffer(cellState, offset: 0, index: 1)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 2)
        encoder.setBuffer(cellIdentities, offset: 0, index: 3)
        encoder.setBuffer(programSlots, offset: 0, index: 4)
        encoder.setBuffer(membraneVertices, offset: 0, index: 5)
        encoder.setBuffer(cellJunctions, offset: 0, index: 6)
        encoder.setBuffer(invariantScratch, offset: 0, index: 7)
        encoder.setBuffer(invariantState, offset: 0, index: 8)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 9)
        encoder.dispatchThreads(
            MTLSize(width: Self.cellJunctionCapacity, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(
                width: min(
                    accumulateSimulationInvariantsPipeline.maxTotalThreadsPerThreadgroup,
                    256
                ),
                height: 1,
                depth: 1
            )
        )
        encoder.memoryBarrier(resources: [invariantScratch, invariantState])

        encoder.setComputePipelineState(finalizeSimulationInvariantsPipeline)
        encoder.setBuffer(programSlots, offset: 0, index: 0)
        encoder.setBuffer(invariantScratch, offset: 0, index: 1)
        encoder.setBuffer(invariantState, offset: 0, index: 2)
        encoder.setBuffer(energyAudit, offset: 0, index: 3)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 4)
        encoder.dispatchThreads(
            MTLSize(width: Self.maxHeritableProgramCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(
                width: min(finalizeSimulationInvariantsPipeline.maxTotalThreadsPerThreadgroup, 256),
                height: 1,
                depth: 1
            )
        )
        encoder.endEncoding()
    }

    private func encodeCellNeighborhoodIndex(
        _ encoder: Metal4ComputeCommandEncoderAdapter,
        uniforms: inout SimulationUniforms
    ) {
        encoder.setComputePipelineState(clearCellSpatialHashPipeline)
        encoder.setBuffer(cellSpatialHashHeads, offset: 0, index: 0)
        encoder.dispatchThreads(
            MTLSize(width: Self.cellSpatialHashBucketCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(
                width: min(clearCellSpatialHashPipeline.maxTotalThreadsPerThreadgroup, 256),
                height: 1,
                depth: 1
            )
        )
        encoder.memoryBarrier(resources: [cellSpatialHashHeads])

        encoder.setComputePipelineState(clearActiveCellContactEffectsPipeline)
        encoder.setBuffer(cellContactEffects, offset: 0, index: 0)
        encoder.setBuffer(membraneContactEffects, offset: 0, index: 1)
        encoder.setBuffer(cellTopologySignatures, offset: 0, index: 2)
        encoder.setBuffer(cellIdentities, offset: 0, index: 3)
        dispatchCells(encoder, pipeline: clearActiveCellContactEffectsPipeline)

        encoder.setComputePipelineState(clearOwnerCellListsPipeline)
        encoder.setBuffer(ownerCellHeads, offset: 0, index: 0)
        encoder.setBuffer(activeComponentIndices, offset: 0, index: 1)
        encoder.setBuffer(activeComponentCount, offset: 0, index: 2)
        dispatchActiveComponents(encoder, pipeline: clearOwnerCellListsPipeline)
        encoder.memoryBarrier(resources: [
            cellContactEffects, membraneContactEffects, cellTopologySignatures,
            cellIdentities, ownerCellHeads
        ])

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
        _ encoder: Metal4ComputeCommandEncoderAdapter,
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
        encoder.setBuffer(componentCellHeads, offset: 0, index: 8)
        encoder.setBuffer(componentCellNext, offset: 0, index: 9)
        encoder.setBuffer(contactWorkState, offset: 0, index: 28)
        dispatchCells(encoder, pipeline: initializeCellComponentsPipeline)
        encoder.memoryBarrier(resources: [
            cellIdentities, cellComponentParents, cellComponentCounts,
            cellComponentAccumulation, cellComponentOwners, cellComponentPrograms,
            ownerPrimaryRoots, componentCellHeads, componentCellNext
        ])

        encoder.setComputePipelineState(unionCellComponentsPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBuffer(cellState, offset: 0, index: 2)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 3)
        encoder.setBuffer(membraneVertices, offset: 0, index: 4)
        encoder.setBuffer(cellIdentities, offset: 0, index: 5)
        encoder.setBuffer(membraneContactPairs, offset: 0, index: 6)
        encoder.setBuffer(contactWorkState, offset: 0, index: 7)
        encoder.setBuffer(cellComponentParents, offset: 0, index: 8)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 9)
        encoder.setBuffer(heritablePrograms, offset: 0, index: 10)
        encoder.setBuffer(identityCounters, offset: 0, index: 11)
        encoder.setBuffer(cellJunctions, offset: 0, index: 12)
        encoder.setBuffer(developmentalGenomes, offset: 0, index: 13)
        encoder.dispatchThreadgroups(
            indirectBuffer: contactPairDispatchArguments,
            indirectBufferOffset: 0,
            threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1)
        )
        encoder.memoryBarrier(resources: [
            cellComponentParents, identityCounters, cellJunctions
        ])

        encoder.setComputePipelineState(compressCellComponentsPipeline)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 0)
        encoder.setBuffer(cellComponentParents, offset: 0, index: 1)
        encoder.setBuffer(cellIdentities, offset: 0, index: 2)
        encoder.setBuffer(contactWorkState, offset: 0, index: 28)
        dispatchCells(encoder, pipeline: compressCellComponentsPipeline)
        encoder.memoryBarrier(resources: [cellComponentParents, cellIdentities])

        encoder.setComputePipelineState(buildCellComponentListsPipeline)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 0)
        encoder.setBuffer(cellIdentities, offset: 0, index: 1)
        encoder.setBuffer(componentCellHeads, offset: 0, index: 2)
        encoder.setBuffer(componentCellNext, offset: 0, index: 3)
        encoder.setBuffer(contactWorkState, offset: 0, index: 28)
        dispatchCells(encoder, pipeline: buildCellComponentListsPipeline)
        encoder.memoryBarrier(resources: [componentCellHeads, componentCellNext])

        encoder.setComputePipelineState(accumulateCellComponentsPipeline)
        encoder.setBuffer(cellState, offset: 0, index: 0)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 1)
        encoder.setBuffer(cellIdentities, offset: 0, index: 2)
        encoder.setBuffer(cellComponentCounts, offset: 0, index: 3)
        encoder.setBuffer(cellComponentAccumulation, offset: 0, index: 4)
        encoder.setBuffer(cellComponentOwners, offset: 0, index: 5)
        encoder.setBuffer(contactWorkState, offset: 0, index: 28)
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
        encoder.setBuffer(activeComponentIndices, offset: 0, index: 6)
        encoder.setBuffer(activeComponentCount, offset: 0, index: 7)
        encoder.setBuffer(contactWorkState, offset: 0, index: 28)
        dispatchActiveComponents(encoder, pipeline: selectPrimaryCellComponentsPipeline)
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
        encoder.setBuffer(componentCellHeads, offset: 0, index: 20)
        encoder.setBuffer(componentCellNext, offset: 0, index: 21)
        encoder.setBuffer(programSlots, offset: 0, index: 22)
        encoder.setBuffer(contactWorkState, offset: 0, index: 28)
        dispatchCells(encoder, pipeline: assignCellComponentOwnersPipeline)
        encoder.memoryBarrier(resources: [
            agentState, agentOccupancy, cellComponentOwners, cellAggregates,
            developmentalGenomes, regulatoryNodes, regulatoryEdges,
            resonanceGenomes, identityCounters, lineageEvents,
            cellComponentPrograms, cellComponentProgramSources,
            cellComponentProgramTargets, heritablePrograms, programSlots
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
        encoder.setBuffer(programSlots, offset: 0, index: 10)
        encoder.setBuffer(identityCounters, offset: 0, index: 11)
        encoder.setBuffer(cellJunctions, offset: 0, index: 12)
        encoder.setBuffer(ownerCellHeads, offset: 0, index: 13)
        encoder.setBuffer(ownerCellNext, offset: 0, index: 14)
        encoder.setBuffer(contactWorkState, offset: 0, index: 28)
        dispatchCells(encoder, pipeline: reassignCellComponentsPipeline)
        encoder.memoryBarrier(resources: [
            cellState, cellOccupancy, cellIdentities, programSlots, identityCounters,
            cellJunctions
        ])

        encoder.setComputePipelineState(finalizeCellTopologyPipeline)
        encoder.setBuffer(contactWorkState, offset: 0, index: 0)
        encoder.setBuffer(activeCellCount, offset: 0, index: 1)
        encoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
        encoder.memoryBarrier(resources: [contactWorkState])
    }

    private func encodeOwnerCellLists(_ encoder: Metal4ComputeCommandEncoderAdapter) {
        encoder.setComputePipelineState(clearOwnerCellListsPipeline)
        encoder.setBuffer(ownerCellHeads, offset: 0, index: 0)
        encoder.setBuffer(activeComponentIndices, offset: 0, index: 1)
        encoder.setBuffer(activeComponentCount, offset: 0, index: 2)
        dispatchActiveComponents(encoder, pipeline: clearOwnerCellListsPipeline)
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

    private func encodeQuantumStep(into commandBuffer: Metal4CommandBufferContext, settings: RendererSettings) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Unitary 2D quantum walk"
        var uniforms = makeUniforms(settings: settings)
        encoder.setComputePipelineState(quantumCouplingPipeline)
        encoder.setTexture(state, index: 0)
        encoder.setTexture(genomeA, index: 1)
        encoder.setTexture(ecology, index: 2)
        encoder.setTexture(quantumCoupling, index: 3)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
        dispatch2D(encoder, pipeline: quantumCouplingPipeline)
        encoder.memoryBarrier(resources: [quantumCoupling])

        encoder.setComputePipelineState(quantumPipeline)
        encoder.setTexture(quantumState, index: 0)
        encoder.setTexture(quantumCoupling, index: 1)
        encoder.setTexture(reactionQuantumState, index: 2)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
        var step = quantumStep
        encoder.setBytes(&step, length: MemoryLayout<UInt32>.stride, index: 1)
        dispatchQuantum(encoder, pipeline: quantumPipeline)
        encoder.writeTimestamp(ending: "quantum")
        encoder.endEncoding()

        swap(&quantumState, &reactionQuantumState)
        quantumStep &+= 1
    }

    private func encodeQuantumMeasurement(into commandBuffer: Metal4CommandBufferContext, slot: MetricReadbackSlot) {
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
        into commandBuffer: Metal4CommandBufferContext,
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
        encoder.setTexture(developmentalField, index: 3)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
        dispatchWorlds(encoder, pipeline: damagePipeline)
        encoder.setComputePipelineState(damageCellPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBuffer(cellState, offset: 0, index: 2)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 3)
        encoder.setBuffer(cellIdentities, offset: 0, index: 4)
        encoder.setBuffer(membraneVertices, offset: 0, index: 5)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 6)
        dispatchAgents(encoder, pipeline: damageCellPipeline)
        encoder.setComputePipelineState(markDamagedComponentsPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBuffer(cellState, offset: 0, index: 2)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 3)
        encoder.setBuffer(cellIdentities, offset: 0, index: 4)
        encoder.setBuffer(ownerCellHeads, offset: 0, index: 5)
        encoder.setBuffer(ownerCellNext, offset: 0, index: 6)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 7)
        dispatchAgents(encoder, pipeline: markDamagedComponentsPipeline)
        encoder.endEncoding()
    }

    private func encodeQualificationTargetSelection(
        into commandBuffer: Metal4CommandBufferContext,
        settings: RendererSettings
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Select regenerative qualification target"
        encoder.setComputePipelineState(selectQualificationTargetPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 2)
        encoder.setBuffer(cellIdentities, offset: 0, index: 3)
        encoder.setBuffer(ownerCellHeads, offset: 0, index: 4)
        encoder.setBuffer(qualificationTargetState, offset: 0, index: 5)
        encoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
        encoder.endEncoding()
    }

    private func encodeSelectedTargetDamage(
        into commandBuffer: Metal4CommandBufferContext,
        settings: RendererSettings
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Controlled regenerative wound"
        var uniforms = makeUniforms(settings: settings)
        encoder.setComputePipelineState(markSelectedTargetChallengedPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBuffer(qualificationTargetState, offset: 0, index: 2)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 3)
        encoder.setBuffer(cellIdentities, offset: 0, index: 4)
        encoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
        encoder.memoryBarrier(resources: [agentState, qualificationTargetState])

        encoder.setComputePipelineState(damageSelectedTargetWorldPipeline)
        encoder.setTexture(state, index: 0)
        encoder.setTexture(ecology, index: 1)
        encoder.setTexture(eventState, index: 2)
        encoder.setTexture(developmentalField, index: 3)
        encoder.setBuffer(qualificationTargetState, offset: 0, index: 0)
        encoder.setBuffer(agentState, offset: 0, index: 1)
        encoder.setBuffer(cellState, offset: 0, index: 2)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 3)
        dispatchWorlds(encoder, pipeline: damageSelectedTargetWorldPipeline)

        encoder.setComputePipelineState(damageSelectedTargetCellsPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(cellState, offset: 0, index: 1)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 2)
        encoder.setBuffer(cellIdentities, offset: 0, index: 3)
        encoder.setBuffer(membraneVertices, offset: 0, index: 4)
        encoder.setBuffer(qualificationTargetState, offset: 0, index: 5)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 6)
        dispatchCells(encoder, pipeline: damageSelectedTargetCellsPipeline)
        encoder.endEncoding()
    }

    private func encodeMeasurements(
        into commandBuffer: Metal4CommandBufferContext,
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
        encoder.setTexture(environmentState, index: 6)
        encoder.setTexture(mechanicalState, index: 7)
        encoder.setTexture(quantumState, index: 8)
        encoder.setBuffer(slot.metrics, offset: 0, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 1)
        dispatchWorlds(encoder, pipeline: measurementPipeline)

        encoder.setComputePipelineState(collectProgramMetricPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBuffer(developmentalGenomes, offset: 0, index: 2)
        encoder.setBuffer(resonanceGenomes, offset: 0, index: 3)
        encoder.setBuffer(slot.programRecords, offset: 0, index: 4)
        encoder.setBuffer(programSlots, offset: 0, index: 5)
        encoder.setBuffer(activeComponentIndices, offset: 0, index: 6)
        encoder.setBuffer(activeComponentCount, offset: 0, index: 7)
        dispatchActiveComponents(encoder, pipeline: collectProgramMetricPipeline)
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
            blit.copy(
                from: energyAudit,
                sourceOffset: 0,
                to: slot.energyAudit,
                destinationOffset: 0,
                size: slot.energyAudit.length
            )
            blit.endEncoding()
        }
    }

    private func encodeBrush(_ brush: BrushEvent, into commandBuffer: Metal4CommandBufferContext, settings: RendererSettings) {
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
        into commandBuffer: Metal4CommandBufferContext,
        settings: RendererSettings
    ) -> Bool {
        let renderResources = renderSubmissionResources[commandBuffer.submissionSlotIndex]
        let visibleCellIndices = renderResources.visibleCellIndices
        let cellDrawArguments = renderResources.cellDrawArguments
        let cellMeshDrawArguments = renderResources.cellMeshDrawArguments
        let visibleJunctionIndices = renderResources.visibleJunctionIndices
        let junctionDrawArguments = renderResources.junctionDrawArguments
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return false
        }
        encoder.label = "Compact visible cells and causal junctions"
        encoder.setComputePipelineState(resetRenderDrawArgumentsPipeline)
        encoder.setBuffer(cellDrawArguments, offset: 0, index: 0)
        encoder.setBuffer(cellMeshDrawArguments, offset: 0, index: 1)
        encoder.setBuffer(junctionDrawArguments, offset: 0, index: 2)
        encoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
        encoder.memoryBarrier(resources: [
            cellDrawArguments, cellMeshDrawArguments, junctionDrawArguments
        ])
        if !settings.isRunning {
            encodeActiveCellCompaction(encoder)
        }
        var uniforms = makeUniforms(settings: settings)
        encoder.setComputePipelineState(compactCellRenderPipeline)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 0)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 1)
        encoder.setBuffer(visibleCellIndices, offset: 0, index: 2)
        encoder.setBuffer(cellDrawArguments, offset: 0, index: 3)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 4)
        encoder.setBuffer(cellIdentities, offset: 0, index: 5)
        encoder.setBuffer(agentState, offset: 0, index: 6)
        encoder.setBuffer(cellState, offset: 0, index: 7)
        encoder.setBuffer(cellMeshDrawArguments, offset: 0, index: 8)
        dispatchCells(encoder, pipeline: compactCellRenderPipeline)

        encoder.setComputePipelineState(compactJunctionRenderPipeline)
        encoder.setBuffer(cellJunctions, offset: 0, index: 0)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 1)
        encoder.setBuffer(cellIdentities, offset: 0, index: 2)
        encoder.setBuffer(agentState, offset: 0, index: 3)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 4)
        encoder.setBuffer(cellState, offset: 0, index: 5)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 6)
        encoder.setBuffer(visibleJunctionIndices, offset: 0, index: 7)
        encoder.setBuffer(junctionDrawArguments, offset: 0, index: 8)
        let junctionThreadWidth = threadsPerThreadgroup1D(
            pipeline: compactJunctionRenderPipeline,
            count: Self.cellJunctionCapacity
        )
        encoder.dispatchThreads(
            MTLSize(width: Self.cellJunctionCapacity, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: junctionThreadWidth, height: 1, depth: 1)
        )
        encoder.memoryBarrier(resources: [
            cellDrawArguments, cellMeshDrawArguments, junctionDrawArguments
        ])
        encoder.setComputePipelineState(finalizeRenderDrawArgumentsPipeline)
        encoder.setBuffer(cellDrawArguments, offset: 0, index: 0)
        encoder.setBuffer(cellMeshDrawArguments, offset: 0, index: 1)
        encoder.setBuffer(junctionDrawArguments, offset: 0, index: 2)
        encoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
        encoder.endEncoding()
        return true
    }

    private func encodeRender(view: MTKView, into commandBuffer: Metal4CommandBufferContext, settings: RendererSettings) {
        guard let drawable = view.currentDrawable,
              commandBuffer.claimPresentation(drawable) else { return }
        var presentationEncoded = false
        defer {
            if !presentationEncoded {
                commandBuffer.cancelPresentation()
            }
        }
        let renderResources = renderSubmissionResources[commandBuffer.submissionSlotIndex]
        let visibleCellIndices = renderResources.visibleCellIndices
        let cellDrawArguments = renderResources.cellDrawArguments
        let cellMeshDrawArguments = renderResources.cellMeshDrawArguments
        let visibleJunctionIndices = renderResources.visibleJunctionIndices
        let junctionDrawArguments = renderResources.junctionDrawArguments
        let drawableTexture = drawable.texture
        let observationZoom = settings.cameraZoom / max(settings.worldScale, 1)
        let renderScale = observationZoom >= 512 ? 5 :
            (observationZoom >= 160 ? 4 :
                (observationZoom >= 64 ? 3 :
                    (observationZoom >= 18 ? 2 : (observationZoom >= 6 ? 1 : 0))))
        let exposure: Float = observationZoom >= 420 ? 1.02 :
            (observationZoom >= 160 ? 0.82 :
            (observationZoom >= 64 ? 1.02 :
                (observationZoom >= 18 ? 0.94 :
                    (observationZoom >= 6 ? 1.04 : 0.94))))
        let bloomIntensity: Float = observationZoom >= 420 ? 0.0 :
            (observationZoom >= 160 ? 0.06 :
                (observationZoom >= 64 ? 0.08 :
                (observationZoom >= 18 ? 0.10 :
                    (observationZoom >= 6 ? 0.08 : 0.08))))
        var uniforms = makeUniforms(settings: settings)
        var postUniforms = PostProcessUniforms(
            sourceSize: SIMD2<Float>(Float(drawableTexture.width), Float(drawableTexture.height)),
            exposure: exposure,
            bloomIntensity: bloomIntensity,
            observationZoom: observationZoom,
            frameIndex: UInt32(truncatingIfNeeded: frameSerial)
        )

        // The resolved spinor lattice has no translucent cell layer or bloom. Rendering it
        // directly avoids a full-resolution HDR store, reload, and composite pass.
        if renderScale == 5 {
            let descriptor = MTL4RenderPassDescriptor()
            let attachment = descriptor.colorAttachments[0]!
            attachment.texture = drawableTexture
            attachment.loadAction = .clear
            attachment.storeAction = .store
            attachment.clearColor = MTLClearColorMake(0.0015, 0.003, 0.006, 1)
            commandBuffer.retainResources([drawableTexture as AnyObject])
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                commandBuffer.cancelPresentation()
                return
            }
            encoder.label = "Render spinor lattice directly to display gamut"
            encoder.setRenderPipelineState(spinorDisplayPipeline)
            bindScaleSurfaceResources(encoder, renderScale: renderScale)
            encoder.setFragmentBytes(
                &uniforms,
                length: MemoryLayout<SimulationUniforms>.stride,
                index: 0
            )
            encoder.setFragmentBytes(
                &postUniforms,
                length: MemoryLayout<PostProcessUniforms>.stride,
                index: 1
            )
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.writeTimestamp(ending: "direct spinor display")
            encoder.endEncoding()
            presentationEncoded = true
            encodePeriodicAgentObservation(into: commandBuffer, settings: settings)
            return
        }

        guard let renderTargets = renderTargets(
            width: drawableTexture.width,
            height: drawableTexture.height,
            resources: renderResources
        ) else {
            commandBuffer.cancelPresentation()
            return
        }
        let sceneColor = renderTargets.sceneColor
        let bloomTextureA = renderTargets.bloomTexture
        commandBuffer.useResidencySet(renderTargets.residencySet)
        commandBuffer.retainResources([
            drawableTexture as AnyObject,
            renderTargets.heap as AnyObject,
            sceneColor as AnyObject,
            bloomTextureA as AnyObject
        ])
        postUniforms.sourceSize = SIMD2<Float>(Float(sceneColor.width), Float(sceneColor.height))
        if observationZoom > 0.35, observationZoom < 180 {
            guard encodeVisibleCellCompaction(
                into: commandBuffer,
                settings: settings
            ) else { return }
        }

        let sceneDescriptor = MTL4RenderPassDescriptor()
        let sceneAttachment = sceneDescriptor.colorAttachments[0]!
        sceneAttachment.texture = sceneColor
        sceneAttachment.loadAction = .clear
        sceneAttachment.storeAction = .store
        sceneAttachment.clearColor = MTLClearColorMake(0.0015, 0.003, 0.006, 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: sceneDescriptor) else { return }
        encoder.label = "Render linear HDR simulation state"
        encoder.setRenderPipelineState(scaleSurfacePipelines[renderScale])
        bindScaleSurfaceResources(encoder, renderScale: renderScale)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 3)

        if observationZoom > 0.35, observationZoom < 180 {
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 0)
            if tuningProfile == .m4Optimized && Self.experimentalMeshCellRenderingEnabled {
                encoder.setRenderPipelineState(cellMeshRenderPipeline)
                encoder.setMeshBuffer(agentState, offset: 0, index: 0)
                encoder.setMeshBuffer(agentOccupancy, offset: 0, index: 1)
                encoder.setMeshBuffer(cellState, offset: 0, index: 2)
                encoder.setMeshBuffer(cellOccupancy, offset: 0, index: 3)
                encoder.setMeshBuffer(membraneVertices, offset: 0, index: 4)
                encoder.setMeshBytes(
                    &uniforms,
                    length: MemoryLayout<SimulationUniforms>.stride,
                    index: 5
                )
                encoder.setMeshBuffer(visibleCellIndices, offset: 0, index: 6)
                encoder.setMeshBuffer(cellIdentities, offset: 0, index: 7)
                encoder.setMeshBuffer(heritablePrograms, offset: 0, index: 8)
                encoder.setMeshBuffer(programInteractions, offset: 0, index: 9)
                encoder.setMeshBuffer(programSlots, offset: 0, index: 10)
                encoder.drawMeshThreadgroups(
                    indirectBuffer: cellMeshDrawArguments,
                    indirectBufferOffset: 0,
                    threadsPerMeshThreadgroup: MTLSize(width: 64, height: 1, depth: 1)
                )
            } else {
                encoder.setRenderPipelineState(cellRenderPipeline)
                encoder.setVertexBuffer(agentState, offset: 0, index: 0)
                encoder.setVertexBuffer(agentOccupancy, offset: 0, index: 1)
                encoder.setVertexBuffer(cellState, offset: 0, index: 2)
                encoder.setVertexBuffer(cellOccupancy, offset: 0, index: 3)
                encoder.setVertexBuffer(membraneVertices, offset: 0, index: 4)
                encoder.setVertexBytes(
                    &uniforms,
                    length: MemoryLayout<SimulationUniforms>.stride,
                    index: 5
                )
                encoder.setVertexBuffer(visibleCellIndices, offset: 0, index: 6)
                encoder.setVertexBuffer(cellIdentities, offset: 0, index: 7)
                encoder.setVertexBuffer(heritablePrograms, offset: 0, index: 8)
                encoder.setVertexBuffer(programInteractions, offset: 0, index: 9)
                encoder.setVertexBuffer(programSlots, offset: 0, index: 10)
                encoder.drawPrimitives(
                    type: MTLPrimitiveType.triangle,
                    indirectBuffer: cellDrawArguments,
                    indirectBufferOffset: 0
                )
            }

            encoder.setRenderPipelineState(junctionRenderPipeline)
            encoder.setVertexBuffer(agentState, offset: 0, index: 0)
            encoder.setVertexBuffer(agentOccupancy, offset: 0, index: 1)
            encoder.setVertexBuffer(cellState, offset: 0, index: 2)
            encoder.setVertexBuffer(cellOccupancy, offset: 0, index: 3)
            encoder.setVertexBuffer(membraneVertices, offset: 0, index: 4)
            encoder.setVertexBytes(
                &uniforms,
                length: MemoryLayout<SimulationUniforms>.stride,
                index: 5
            )
            encoder.setVertexBuffer(visibleJunctionIndices, offset: 0, index: 6)
            encoder.setVertexBuffer(cellIdentities, offset: 0, index: 7)
            encoder.setVertexBuffer(heritablePrograms, offset: 0, index: 8)
            encoder.setVertexBuffer(programInteractions, offset: 0, index: 9)
            encoder.setVertexBuffer(programSlots, offset: 0, index: 10)
            encoder.setVertexBuffer(cellJunctions, offset: 0, index: 11)
            encoder.drawPrimitives(
                type: .triangle,
                indirectBuffer: junctionDrawArguments,
                indirectBufferOffset: 0
            )
        }
        encoder.writeTimestamp(ending: "scene raster")
        encoder.endEncoding()
        if postUniforms.bloomIntensity > 0.001 {
            guard encodeBloom(
                source: sceneColor,
                textureA: bloomTextureA,
                uniforms: &postUniforms,
                into: commandBuffer
            ) else { return }
            commandBuffer.writeTimestamp(ending: "bloom downsample")
        }

        let drawableDescriptor = MTL4RenderPassDescriptor()
        let drawableAttachment = drawableDescriptor.colorAttachments[0]!
        drawableAttachment.texture = drawableTexture
        drawableAttachment.loadAction = .clear
        drawableAttachment.storeAction = .store
        drawableAttachment.clearColor = MTLClearColorMake(0.0015, 0.003, 0.006, 1)
        guard let compositeEncoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: drawableDescriptor
        ) else { return }
        compositeEncoder.label = "Composite HDR scene into display gamut"
        compositeEncoder.setRenderPipelineState(compositePipeline)
        compositeEncoder.setFragmentTexture(sceneColor, index: 0)
        compositeEncoder.setFragmentTexture(bloomTextureA, index: 1)
        compositeEncoder.setFragmentBytes(
            &postUniforms,
            length: MemoryLayout<PostProcessUniforms>.stride,
            index: 0
        )
        compositeEncoder.drawPrimitives(
            type: MTLPrimitiveType.triangle,
            vertexStart: 0,
            vertexCount: 3
        )
        compositeEncoder.writeTimestamp(ending: "display composite")
        compositeEncoder.endEncoding()
        presentationEncoded = true
        encodePeriodicAgentObservation(into: commandBuffer, settings: settings)
    }

    private func bindScaleSurfaceResources(
        _ encoder: Metal4RenderCommandEncoderAdapter,
        renderScale: Int
    ) {
        if renderScale >= 3 {
            encoder.setFragmentTexture(quantumState, index: 0)
            encoder.setFragmentTexture(state, index: 1)
            encoder.setFragmentTexture(ecology, index: 2)
            encoder.setFragmentTexture(environmentState, index: 3)
            encoder.setFragmentTexture(mechanicalState, index: 4)
            encoder.setFragmentTexture(genomeA, index: 5)
            encoder.setFragmentTexture(genomeC, index: 6)
        } else {
            encoder.setFragmentTexture(state, index: 0)
            encoder.setFragmentTexture(ecology, index: 1)
            encoder.setFragmentTexture(environmentState, index: 2)
            encoder.setFragmentTexture(eventState, index: 3)
            encoder.setFragmentTexture(mechanicalState, index: 4)
        }
    }

    private func encodePeriodicAgentObservation(
        into commandBuffer: Metal4CommandBufferContext,
        settings: RendererSettings
    ) {
        let observationInterval = settings.trackedAgentID == .max
            ? Self.agentObservationIntervalFrames
            : Self.trackedAgentObservationIntervalFrames
        if frameSerial.isMultiple(of: observationInterval) {
            encodeAgentObservation(into: commandBuffer, settings: settings)
        }
    }

    private func encodeBloom(
        source: MTLTexture,
        textureA: MTLTexture,
        uniforms: inout PostProcessUniforms,
        into commandBuffer: Metal4CommandBufferContext
    ) -> Bool {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return false
        }
        encoder.label = "Quarter-resolution HDR bloom"
        encoder.setComputePipelineState(bloomPrefilterPipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(textureA, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<PostProcessUniforms>.stride, index: 0)
        dispatchTexture(encoder, pipeline: bloomPrefilterPipeline, texture: textureA)
        encoder.endEncoding()
        return true
    }

    private func renderTargets(
        width: Int,
        height: Int,
        resources: RenderSubmissionResources
    ) -> RenderTargetSet? {
        let size = MTLSize(width: width, height: height, depth: 1)
        if let targets = resources.renderTargets,
           targets.size.width == size.width,
           targets.size.height == size.height {
            return targets
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

        let sceneSizeAndAlign = device.heapTextureSizeAndAlign(descriptor: sceneDescriptor)
        let bloomSizeAndAlign = device.heapTextureSizeAndAlign(descriptor: bloomDescriptor)
        let bloomOffset = Self.alignUp(
            sceneSizeAndAlign.size,
            alignment: bloomSizeAndAlign.align
        )
        let heapDescriptor = MTLHeapDescriptor()
        heapDescriptor.storageMode = .private
        heapDescriptor.hazardTrackingMode = .tracked
        heapDescriptor.type = .automatic
        heapDescriptor.size = bloomOffset + bloomSizeAndAlign.size

        guard let heap = device.makeHeap(descriptor: heapDescriptor),
              let nextScene = heap.makeTexture(descriptor: sceneDescriptor),
              let nextBloomA = heap.makeTexture(descriptor: bloomDescriptor) else {
            return nil
        }
        let residencyDescriptor = MTLResidencySetDescriptor()
        residencyDescriptor.label = "Render target residency \(width)x\(height)"
        residencyDescriptor.initialCapacity = 1
        guard let residencySet = try? device.makeResidencySet(descriptor: residencyDescriptor) else {
            return nil
        }
        residencySet.addAllocation(heap)
        residencySet.commit()
        residencySet.requestResidency()
        heap.label = "Bounded transient render targets \(width)x\(height)"
        nextScene.label = "Linear HDR simulation scene"
        nextBloomA.label = "Single-pass quarter-resolution bloom"
        let targets = RenderTargetSet(
            size: size,
            heap: heap,
            residencySet: residencySet,
            sceneColor: nextScene,
            bloomTexture: nextBloomA
        )
        resources.renderTargets = targets
        commandQueue.reportTransientResidentBytes(
            renderSubmissionResources.reduce(UInt64(0)) {
                $0 + UInt64($1.renderTargets?.heap.size ?? 0)
            }
        )
        return targets
    }

    private static func alignUp(_ value: Int, alignment: Int) -> Int {
        guard alignment > 1 else { return value }
        return (value + alignment - 1) & ~(alignment - 1)
    }

    private func encodeAgentObservation(
        into commandBuffer: Metal4CommandBufferContext,
        settings: RendererSettings
    ) {
        guard let slot = agentObservationRingState.acquire() else { return }
        let observedRecords = agentObservationBuffers[slot]
        let observedCellRecords = cellObservationBuffers[slot]
        let observedLineageEvents = lineageEventObservationBuffers[slot]
        let observedIdentityCounters = identityCounterObservationBuffers[slot]
        if let clear = commandBuffer.makeBlitCommandEncoder() {
            clear.label = "Clear inactive component observations"
            clear.fill(buffer: observedRecords, range: 0..<observedRecords.length, value: 0)
            clear.fill(
                buffer: observedCellRecords,
                range: 0..<observedCellRecords.length,
                value: 0
            )
            clear.endEncoding()
        }
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
        encoder.setBuffer(programSlots, offset: 0, index: 6)
        encoder.setBuffer(activeComponentIndices, offset: 0, index: 7)
        encoder.setBuffer(activeComponentCount, offset: 0, index: 8)
        dispatchActiveComponents(encoder, pipeline: collectAgentObservationPipeline)
        encoder.memoryBarrier(resources: [observedRecords])

        var uniforms = makeUniforms(settings: settings)
        encoder.setComputePipelineState(collectCellObservationPipeline)
        encoder.setBuffer(agentState, offset: 0, index: 0)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 1)
        encoder.setBuffer(cellState, offset: 0, index: 2)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 3)
        encoder.setBuffer(cellIdentities, offset: 0, index: 4)
        encoder.setBuffer(programInteractions, offset: 0, index: 5)
        encoder.setBuffer(heritablePrograms, offset: 0, index: 6)
        encoder.setBuffer(observedCellRecords, offset: 0, index: 7)
        encoder.setBytes(&uniforms, length: MemoryLayout<SimulationUniforms>.stride, index: 8)
        encoder.setBuffer(developmentalGenomes, offset: 0, index: 9)
        encoder.setBuffer(programSlots, offset: 0, index: 10)
        dispatchCells(encoder, pipeline: collectCellObservationPipeline)
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
            cellRecords: observedCellRecords,
            lineageEvents: observedLineageEvents,
            identityCounters: observedIdentityCounters
        )
        let ringState = agentObservationRingState
        let deliveryState = lineageEventDeliveryState
        let agentCapacity = Self.maxAgentCount
        let cellCapacity = Self.maxCellCount
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
                    componentDescentDepth: record.generation,
                    programReplicationGeneration: UInt32(max(record.padding.z.rounded(), 0)),
                    isHunter: record.flags & 2 != 0,
                    hasRegeneratedDevelopment: record.flags & 4 != 0,
                    hasReceivedDamageChallenge: record.flags & 16 != 0,
                    hasDemonstratedHomeostasis: record.flags & 8 != 0,
                    isSexualOffspring: record.flags & 32 != 0,
                    genomeHash: record.genomeHash,
                    topologyHash: record.topologyHash,
                    morphology: record.morphology,
                    dynamics: record.dynamics,
                    mutationDistance: record.mutationDistance,
                    energeticIndependence: record.padding.x,
                    mechanochemicalClosure: record.padding.y,
                    energeticBoundary: record.energeticBoundary,
                    boundary: record.boundary,
                    mechanochemical: record.mechanochemical,
                    social: record.social,
                    environment: record.environment
                ))
            }
            let cellRecords = buffers.cellRecords.contents().bindMemory(
                to: CellObservationRecord.self,
                capacity: cellCapacity
            )
            var cellObservations: [CellObservation] = []
            cellObservations.reserveCapacity(64)
            for index in 0..<cellCapacity where cellRecords[index].identity.x != 0 {
                let record = cellRecords[index]
                cellObservations.append(CellObservation(
                    persistentID: record.identity.x,
                    owner: Int(record.identity.y),
                    componentBirthID: record.identity.z,
                    programReplicationGeneration: record.identity.w,
                    programID: permanentProgramID(
                        index: record.programAncestry.x,
                        generation: record.programAncestry.y
                    ),
                    parentProgramID: record.programAncestry.z <
                        permanentProgramSlotCapacity
                        ? permanentProgramID(
                            index: record.programAncestry.z,
                            generation: record.programAncestry.w
                        ) : nil,
                    programGenomeHash: record.programLineage.x,
                    parentProgramGenomeHash: record.programLineage.y,
                    inheritedMechanochemicalTrait: record.inheritedTraits.x,
                    position: SIMD2<Float>(record.geometry.x, record.geometry.y),
                    membranePerimeter: record.geometry.z,
                    exposedPerimeterFraction: record.geometry.w,
                    energetic: record.energetic,
                    boundary: record.boundary,
                    mechanochemical: record.mechanochemical,
                    social: record.social,
                    environment: record.environment
                ))
            }
            let eventRecords = buffers.lineageEvents.contents().bindMemory(
                to: LineageEventRecord.self,
                capacity: lineageCapacity
            )
            let counters = buffers.identityCounters.contents().bindMemory(
                to: UInt32.self, capacity: identityReadbackCounterCount
            )
            let events = deliveryState.consume(
                records: eventRecords,
                writeSequence: counters[2],
                capacity: lineageCapacity
            )
            callback?(events, observations, cellObservations)
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
            capacity: Self.identityCounterCount
        )
        let energyAuditValues = slot.energyAudit.contents().bindMemory(
            to: Int32.self,
            capacity: Self.energyAuditChannelCount
        )
        func auditedEnergy(_ channel: Int) -> Double {
            Double(energyAuditValues[channel]) / Self.energyAuditScale
        }
        let auditedSubstrateEnergy = auditedEnergy(0)
        let auditedATPHarvest = auditedEnergy(1)
        let auditedCellularStorageDelta = auditedEnergy(2)
        let auditedActiveWork = auditedEnergy(3)
        let auditedFrequencyWork = auditedEnergy(4)
        let auditedHeatExport = auditedEnergy(6)
        let auditedDetritusReturn = auditedEnergy(7)
        let energyConservationResidual = auditedEnergy(9)
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
        let meanEnvironment: SIMD4<Double> = cellCount == 0
            ? .zero
            : livingIndices.reduce(into: SIMD4<Double>.zero) { total, index in
                let weight = Double(max(cellular[index].physiology.x, 0))
                total += SIMD4<Double>(cellular[index].environment) * weight
            } / Double(cellCount)
        let meanArmorConstruction = cellCount == 0 ? 0 : livingIndices.reduce(0.0) {
            total, index in
            let aggregate = cellular[index]
            let count = max(aggregate.physiology.x, 0)
            let exposedFraction = min(max(
                aggregate.geometryBoundary.w / max(aggregate.shape.y * count, 0.0001),
                0
            ), 1)
            let construction = exposedFraction * aggregate.regulation.y *
                aggregate.regulation.w * agents[index].geneA.w * aggregate.physiology.y
            return total + Double(count * construction)
        } / Double(cellCount)
        let meanPredatoryConstruction = cellCount == 0 ? 0 : livingIndices.reduce(0.0) {
            total, index in
            let aggregate = cellular[index]
            let count = max(aggregate.physiology.x, 0)
            let exposedFraction = min(max(
                aggregate.geometryBoundary.w / max(aggregate.shape.y * count, 0.0001),
                0
            ), 1)
            let trait = min(max((agents[index].geneC.w - 0.025) * 2.2, 0), 1)
            let construction = exposedFraction * aggregate.regulationB.y *
                aggregate.regulationB.w * trait * aggregate.physiology.y
            return total + Double(count * construction)
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
        let meanDevelopment: SIMD4<Double> = livingIndices.isEmpty
            ? .zero
            : livingIndices.reduce(into: SIMD4<Double>.zero) { total, index in
                let weight = Double(max(cellular[index].physiology.x, 0))
                total += SIMD4<Double>(cellular[index].development) * weight
            } / Double(max(cellCount, 1))
        let meanDevelopmentCausality: SIMD4<Double> = livingIndices.isEmpty
            ? .zero
            : livingIndices.reduce(into: SIMD4<Double>.zero) { total, index in
                let weight = Double(max(cellular[index].physiology.x, 0))
                total += SIMD4<Double>(cellular[index].developmentCausality) * weight
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
        let meanJunctionMaterial: SIMD4<Double> = livingIndices.isEmpty
            ? .zero
            : livingIndices.reduce(into: SIMD4<Double>.zero) { total, index in
                total += SIMD4<Double>(
                    programRecords[index].developmental.junctionMaterial
                )
            } / Double(livingIndices.count)
        let meanEcologicalResponse: SIMD4<Double> = livingIndices.isEmpty
            ? .zero
            : livingIndices.reduce(into: SIMD4<Double>.zero) { total, index in
                total += SIMD4<Double>(
                    programRecords[index].developmental.ecologicalResponse
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
            let lineageMasses = (20..<36).map { Double(raw[base + $0]) }
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
                substrateFluctuation: mean(16),
                detritusDensity: mean(17),
                barrierFraction: mean(18),
                environmentalMechanicalDrive: mean(19),
                centroidX: biomass > 1e-9 ? min(max(mean(10) / biomass, 0), 1) : 0.5,
                centroidY: biomass > 1e-9 ? min(max(mean(11) / biomass, 0), 1) : 0.5
            )
        }

        let decision = evaluator.evaluate(worlds)
        if let champion = decision.rankedWorlds.first {
            let selectedMetricBase = champion.worldIndex * Self.metricCount
            func selectedMean(_ metric: Int) -> Double {
                Double(raw[selectedMetricBase + metric]) / (metricScale * pixelCount)
            }
            latestSnapshot = EvolutionSnapshot(
                generation: Int(completedGeneration),
                totalSteps: completedSteps,
                selectedWorld: champion.worldIndex,
                archiveCount: decision.archiveCount,
                quantumNorm: quantumNorm,
                meanMolecularResourceB: selectedMean(36),
                meanMolecularCatalyst: selectedMean(37),
                meanMolecularToxin: selectedMean(38),
                meanMolecularMembrane: selectedMean(39),
                meanQuantumOrder: selectedMean(40),
                meanChemicalAffinity: selectedMean(41),
                meanCatalystProduction: selectedMean(42) / 100,
                meanPrebioticEnergyProduction: selectedMean(43) / 100,
                meanMembraneAssembly: selectedMean(44) / 100,
                meanDetritalMineralization: selectedMean(45) / 100,
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
                meanSubstrateForcing: meanEnvironment.x,
                meanBarrierLoad: meanEnvironment.y,
                meanEnvironmentalFrequency: meanEnvironment.z,
                meanFrequencyMatch: meanEnvironment.w,
                meanArmorConstruction: meanArmorConstruction,
                meanPredatoryConstruction: meanPredatoryConstruction,
                cellularEnergyHarvest: cellularEnergyHarvest,
                cellularEnergyDemand: cellularEnergyDemand,
                cellularEnergyDissipation: cellularEnergyDissipation,
                auditedSubstrateEnergy: auditedSubstrateEnergy,
                auditedATPHarvest: auditedATPHarvest,
                auditedCellularStorageDelta: auditedCellularStorageDelta,
                auditedActiveWork: auditedActiveWork,
                auditedFrequencyWork: auditedFrequencyWork,
                auditedHeatExport: auditedHeatExport,
                auditedDetritusReturn: auditedDetritusReturn,
                energyConservationResidual: energyConservationResidual,
                meanProliferationProgram: meanDevelopmentalRegulation.x,
                meanAdhesiveProgram: meanDevelopmentalRegulation.y,
                meanContractileProgram: meanDevelopmentalRegulation.z,
                meanRepairProgram: meanDevelopmentalRegulation.w,
                meanDevelopmentalNodeCount: meanDevelopmentalNodeCount,
                meanDevelopmentalEdgeCount: meanDevelopmentalEdgeCount,
                meanMorphogenActivator: meanDevelopment.x,
                meanMorphogenInhibitor: meanDevelopment.y,
                meanDevelopmentalFateMemory: meanDevelopment.z,
                meanJunctionMorphogenTransport: meanDevelopment.w,
                meanMorphogenDifferentiation: meanDevelopmentCausality.x,
                meanDevelopmentalPolarityCoherence: meanDevelopmentCausality.y,
                meanMorphogenSynthesisRate: meanDevelopmentCausality.z,
                meanMorphogenTransportWork: meanDevelopmentCausality.w,
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
                meanJunctionAdhesion: meanJunctionMaterial.x,
                meanJunctionCorticalTension: meanJunctionMaterial.y,
                meanJunctionDamping: meanJunctionMaterial.z,
                meanJunctionPermeability: meanJunctionMaterial.w,
                meanToxinTolerance: meanEcologicalResponse.x,
                meanDetritalScavenging: meanEcologicalResponse.y,
                meanShearAnchoring: meanEcologicalResponse.z,
                meanStarvationQuiescence: meanEcologicalResponse.w,
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
            latestSnapshot.crossComponentContactSamples = identityCounterValues[5]
            latestSnapshot.membraneBreachSamples = identityCounterValues[6]
            latestSnapshot.resistedAttackSamples = identityCounterValues[7]
            latestSnapshot.trophicTransferSamples = identityCounterValues[8]
            latestSnapshot.transferredEnergy =
                Double(identityCounterValues[9]) / Self.energyAuditScale
            latestSnapshot.deflectedAttackImpulse =
                Double(identityCounterValues[10]) / Self.energyAuditScale
            latestSnapshot.fusionContactSamples = identityCounterValues[11]
            latestSnapshot.successfulFusionContactSamples = identityCounterValues[12]
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
            let energyAuditSummary = String(
                format: "%.6f/%.6f/%+.6f/%.6f/%.6f/%.6f/%.6f/%+.3e",
                auditedSubstrateEnergy,
                auditedATPHarvest,
                auditedCellularStorageDelta,
                auditedActiveWork,
                auditedFrequencyWork,
                auditedHeatExport,
                auditedDetritusReturn,
                energyConservationResidual
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
                "environment=\(String(format: "%.3f/%.3f/%.5f/%.3f", meanEnvironment.x, meanEnvironment.y, meanEnvironment.z, meanEnvironment.w)) " +
                "construction=\(String(format: "%.4f/%.4f", meanArmorConstruction, meanPredatoryConstruction)) " +
                "elongation=\(String(format: "%.4f", meanTissueElongation)) " +
                "exposed_membrane=\(String(format: "%.4f", meanExposedMembraneLength)) " +
                "cell_force=\(String(format: "%.7f", meanCellGeneratedForce)) " +
                "tissue_torque=\(String(format: "%.7f", meanTissueTorque)) " +
                "contact=\(String(format: "%.7f", cellularContactLoad)) " +
                "trophic=\(String(format: "%.7f/%.7f", cellularTrophicGain, cellularTrophicLoss)) " +
                "detach=\(String(format: "%.4f", meanDetachmentScore)) " +
                "cell_power=\(String(format: "%+.6f", netCellularPower)) " +
                "energy_audit=\(energyAuditSummary)"
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
            seed: UInt32(truncatingIfNeeded: settings.resetToken),
            brushPosition: brushPosition,
            brushRadius: brushRadius,
            brushStrength: brushStrength,
            cameraCenter: settings.cameraCenter,
            cameraZoom: max(settings.cameraZoom, 0.000_000_001),
            worldScale: max(settings.worldScale, 1),
            viewportAspect: viewportAspect,
            intervention: SIMD4<Float>(
                settings.mechanosensingGain,
                settings.barrierGain,
                1,
                1
            )
        )
    }

    private func dispatchWorlds(_ encoder: Metal4ComputeCommandEncoderAdapter, pipeline: MTLComputePipelineState) {
        let threadgroup = threadsPerThreadgroup2D(pipeline: pipeline, gridWidth: Self.gridSize)
        encoder.dispatchThreads(
            MTLSize(width: Self.gridSize, height: Self.gridSize, depth: Self.worldCount),
            threadsPerThreadgroup: threadgroup
        )
    }

    private func dispatch2D(_ encoder: Metal4ComputeCommandEncoderAdapter, pipeline: MTLComputePipelineState) {
        let threadgroup = threadsPerThreadgroup2D(pipeline: pipeline, gridWidth: Self.gridSize)
        encoder.dispatchThreads(
            MTLSize(width: Self.gridSize, height: Self.gridSize, depth: 1),
            threadsPerThreadgroup: threadgroup
        )
    }

    private func dispatchQuantum(_ encoder: Metal4ComputeCommandEncoderAdapter, pipeline: MTLComputePipelineState) {
        let threadgroup = threadsPerThreadgroup2D(pipeline: pipeline, gridWidth: Self.quantumGridSize)
        encoder.dispatchThreads(
            MTLSize(width: Self.quantumGridSize, height: Self.quantumGridSize, depth: 1),
            threadsPerThreadgroup: threadgroup
        )
    }

    private func dispatchAgents(_ encoder: Metal4ComputeCommandEncoderAdapter, pipeline: MTLComputePipelineState) {
        let width = threadsPerThreadgroup1D(pipeline: pipeline, count: Self.maxAgentCount)
        encoder.dispatchThreads(
            MTLSize(width: Self.maxAgentCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
    }

    private func encodeActiveComponentCompaction(_ encoder: Metal4ComputeCommandEncoderAdapter) {
        encoder.setComputePipelineState(resetActiveComponentDispatchPipeline)
        encoder.setBuffer(activeComponentCount, offset: 0, index: 0)
        encoder.setBuffer(activeComponentDispatchArguments, offset: 0, index: 1)
        encoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
        encoder.memoryBarrier(resources: [activeComponentCount, activeComponentDispatchArguments])

        encoder.setComputePipelineState(compactActiveComponentsPipeline)
        encoder.setBuffer(agentOccupancy, offset: 0, index: 0)
        encoder.setBuffer(activeComponentIndices, offset: 0, index: 1)
        encoder.setBuffer(activeComponentCount, offset: 0, index: 2)
        dispatchAgents(encoder, pipeline: compactActiveComponentsPipeline)
        encoder.memoryBarrier(resources: [activeComponentIndices, activeComponentCount])

        encoder.setComputePipelineState(prepareActiveComponentDispatchPipeline)
        encoder.setBuffer(activeComponentCount, offset: 0, index: 0)
        encoder.setBuffer(activeComponentDispatchArguments, offset: 0, index: 1)
        encoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
        encoder.memoryBarrier(resources: [activeComponentDispatchArguments])
    }

    private func encodeActiveCellCompaction(_ encoder: Metal4ComputeCommandEncoderAdapter) {
        encoder.setComputePipelineState(compactActiveCellsPipeline)
        encoder.setBuffer(cellOccupancy, offset: 0, index: 0)
        encoder.setBuffer(activeCellIndices, offset: 0, index: 1)
        encoder.setBuffer(activeCellCount, offset: 0, index: 2)
        encoder.setBuffer(activeCellDispatchArguments, offset: 0, index: 3)
        encoder.dispatchThreads(
            MTLSize(width: 256, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1)
        )
        encoder.memoryBarrier(resources: [
            activeCellIndices, activeCellCount, activeCellDispatchArguments
        ])
        encoder.setBuffer(activeCellCount, offset: 0, index: 29)
        encoder.setBuffer(activeCellIndices, offset: 0, index: 30)
    }

    private func dispatchActiveComponents(
        _ encoder: Metal4ComputeCommandEncoderAdapter,
        pipeline: MTLComputePipelineState
    ) {
        precondition(
            pipeline.maxTotalThreadsPerThreadgroup >= 64,
            "Active-component kernels require a 64-thread group"
        )
        encoder.dispatchThreadgroups(
            indirectBuffer: activeComponentDispatchArguments,
            indirectBufferOffset: 0,
            threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1)
        )
    }

    private func dispatchCells(_ encoder: Metal4ComputeCommandEncoderAdapter, pipeline: MTLComputePipelineState) {
        precondition(
            pipeline.maxTotalThreadsPerThreadgroup >= 64,
            "Living-cell kernels require a 64-thread group"
        )
        encoder.dispatchThreadgroups(
            indirectBuffer: activeCellDispatchArguments,
            indirectBufferOffset: 0,
            threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1)
        )
    }

    private func dispatchTexture(
        _ encoder: Metal4ComputeCommandEncoderAdapter,
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
        let preferredRows = tuningProfile == .m4Optimized ? 8 : 4
        return MTLSize(width: width, height: min(availableRows, preferredRows), depth: 1)
    }

    private func threadsPerThreadgroup1D(
        pipeline: MTLComputePipelineState,
        count: Int
    ) -> Int {
        let executionWidth = max(pipeline.threadExecutionWidth, 1)
        let profileLimit = tuningProfile == .m4Optimized ? 256 : 128
        let limit = max(1, min(
            pipeline.maxTotalThreadsPerThreadgroup,
            min(count, profileLimit)
        ))
        return limit >= executionWidth
            ? max(executionWidth, (limit / executionWidth) * executionWidth)
            : limit
    }

    private func copyAllSlices(from source: MTLTexture, to destination: MTLTexture, commandBuffer: Metal4CommandBufferContext) {
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
        swap(&developmentalField, &reactionDevelopmentalField)
    }

    private func copySlice(
        from source: MTLTexture,
        sourceSlice: Int,
        to destination: MTLTexture,
        destinationSlice: Int,
        encoder: Metal4BlitCommandEncoderAdapter
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
        let packagedResourceBundle = Bundle.main.resourceURL
            .map { $0.appendingPathComponent("NumiAutomata_NumiAutomata.bundle", isDirectory: true) }
            .flatMap(Bundle.init(url:))

        if let metallibURL = packagedResourceBundle?.url(
            forResource: "Replicator",
            withExtension: "metallib",
            subdirectory: "Shaders"
        ) ?? Bundle.module.url(
            forResource: "Replicator",
            withExtension: "metallib",
            subdirectory: "Shaders"
        ) {
            return try device.makeLibrary(URL: metallibURL)
        }

#if DEBUG
        guard let url = packagedResourceBundle?.url(
            forResource: "Replicator",
            withExtension: "metal",
            subdirectory: "Shaders"
        ) ?? Bundle.module.url(
            forResource: "Replicator",
            withExtension: "metal",
            subdirectory: "Shaders"
        ) else {
            throw EvolutionRendererError.missingShader
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        return try device.makeLibrary(source: source, options: nil)
#else
        throw EvolutionRendererError.missingCompiledShader
#endif
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

    private static func makeQuantumCouplingTexture(
        device: MTLDevice,
        label: String
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: gridSize,
            height: gridSize,
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
