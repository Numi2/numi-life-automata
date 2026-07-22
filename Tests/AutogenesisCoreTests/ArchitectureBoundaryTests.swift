import Foundation
import Testing

struct ArchitectureBoundaryTests {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test
    func causalShaderContainsNoObserverOrLifecycleState() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        for forbidden in [
            "AutonomyVector", "IndividualityEvidence", "SelectionPartition",
            "lifeStage", "homeostasisSteps", "integrationSteps"
        ] {
            #expect(!shader.contains(forbidden), "Causal shader contains forbidden observer state: \(forbidden)")
        }
    }

    @Test
    func sourceTreeContainsNoRetiredLifecycleState() throws {
        let sourceRoot = repositoryRoot.appending(path: "Sources")
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: nil
            )
        )
        let sourceFiles = enumerator.compactMap { $0 as? URL }.filter {
            ["swift", "metal"].contains($0.pathExtension)
        }
        for file in sourceFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for forbidden in [
                "AgentLifeStage", "lifeStage", "homeostasisSteps",
                "integrationSteps", "DevelopmentalQualification"
            ] {
                #expect(
                    !source.contains(forbidden),
                    "\(file.lastPathComponent) contains retired lifecycle symbol \(forbidden)"
                )
            }
        }
    }

    @Test
    func componentSeparationHasNoAggregateBiologicalGate() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        let start = try #require(shader.range(of: "kernel void assignCellComponentOwners"))
        let end = try #require(shader.range(of: "inline void invalidateCellJunctions", range: start.upperBound..<shader.endIndex))
        let assignment = String(shader[start.lowerBound..<end.lowerBound])
        #expect(!assignment.contains("meanATP <"))
        #expect(!assignment.contains("meanIntegrity <"))
        #expect(!assignment.contains("detachment <"))
        #expect(!assignment.contains("mutateCellProgram("))
    }

    @Test
    func programMutationOccursOnlyInCellDivisionKernel() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        let definition = try #require(shader.range(of: "inline AgentState mutateCellProgram"))
        let call = try #require(shader.range(
            of: "mutateCellProgram(",
            range: definition.upperBound..<shader.endIndex
        ))
        let division = try #require(shader.range(of: "kernel void divideAndReduceOrganismCells"))
        #expect(call.lowerBound > division.lowerBound)
        #expect(shader[division.lowerBound..<call.lowerBound].contains("replicationError"))
    }

    @Test
    func delayedComponentAllocationCannotDeleteAFragment() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        let start = try #require(shader.range(of: "kernel void reassignCellComponents"))
        let end = try #require(shader.range(
            of: "kernel void injectFounder",
            range: start.upperBound..<shader.endIndex
        ))
        let reassignment = String(shader[start.lowerBound..<end.lowerBound])
        #expect(!reassignment.contains("&cellOccupancy[gid], 0u"))
        #expect(reassignment.contains("retry component assignment"))
    }

    @Test
    func cellDivisionCreatesAPersistentCytokineticMidbody() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        let start = try #require(shader.range(of: "kernel void divideAndReduceOrganismCells"))
        let end = try #require(shader.range(
            of: "kernel void resetActiveComponentDispatch",
            range: start.upperBound..<shader.endIndex
        ))
        let division = String(shader[start.lowerBound..<end.lowerBound])
        #expect(division.contains("findOrCreateCellJunction"))
        #expect(division.contains("cytokineticPairKey"))
        #expect(division.contains("midbodyStrength"))
    }

    @Test
    func cellPhysicsHasNoComponentCentricBodyConstraint() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        let start = try #require(shader.range(of: "kernel void evolveOrganismCells"))
        let end = try #require(shader.range(
            of: "kernel void clearCellSpatialHash",
            range: start.upperBound..<shader.endIndex
        ))
        let cellPhysics = String(shader[start.lowerBound..<end.lowerBound])
        #expect(cellPhysics.contains("float2 mechanicalForce = float2(0.0)"))
        #expect(cellPhysics.contains("float extracellularAccess = pow(membraneExposure"))
        #expect(!cellPhysics.contains("mechanicalForce = -cell.position"))
        #expect(!cellPhysics.contains("radialDistance >"))
        #expect(!cellPhysics.contains("length(cell.position) / 0.62"))
    }

    @Test
    func everyLocallyCompetentCellCanDivideWithoutComponentArbitration() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        let start = try #require(shader.range(of: "kernel void divideAndReduceOrganismCells"))
        let end = try #require(shader.range(
            of: "float activeCount = 0.0",
            range: start.upperBound..<shader.endIndex
        ))
        let division = String(shader[start.lowerBound..<end.lowerBound])
        #expect(division.contains("if (divisionCompetent && cycle >= 1.0)"))
        #expect(division.contains("uint divisionParent = index"))
        #expect(!division.contains("mostAdvancedCycle"))
    }

    @Test
    func divisionAsymmetryPartitionsBoundedCellStateWithoutAssigningFateOutputs() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        let start = try #require(shader.range(of: "kernel void divideAndReduceOrganismCells"))
        let end = try #require(shader.range(
            of: "float activeCount = 0.0",
            range: start.upperBound..<shader.endIndex
        ))
        let division = String(shader[start.lowerBound..<end.lowerBound])
        #expect(shader.contains("inline float conservativeDivisionDelta"))
        #expect(division.contains("parent.signals.xy -= morphogenPartition"))
        #expect(division.contains("child.signals.xy += morphogenPartition"))
        #expect(division.contains("state - stateDelta"))
        #expect(division.contains("state + stateDelta"))
        #expect(!division.contains("parent.regulation ="))
        #expect(!division.contains("child.regulation ="))
    }

    @Test
    func activeLocalDetachmentPenalizesRefusionWithoutBlockingCompatibleMating() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        #expect(!shader.contains(
            "max(cell.tissueGeometry.w, other.tissueGeometry.w) < 0.32"
        ))
        #expect(shader.contains(
            "(0.00018 + detachmentRelease * 0.00012)"
        ))
        #expect(shader.contains("float localDetachmentGate = mix("))
        #expect(shader.contains("0.30, 1.0,"))
        #expect(shader.contains("float compressiveContactGate = 1.0 - smoothstep"))
        #expect(shader.contains("localDetachmentGate * compressiveContactGate"))
    }

    @Test
    func selectionUsesGenerationTaggedProgramIdentityRatherThanGenomeHash() throws {
        let renderer = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/EvolutionRenderer.swift"),
            encoding: .utf8
        )
        let start = try #require(renderer.range(of: "let programID = permanentProgramID"))
        let end = try #require(renderer.range(
            of: "let currentProgramRepresentations",
            range: start.upperBound..<renderer.endIndex
        ))
        let representation = String(renderer[start.lowerBound..<end.lowerBound])
        #expect(representation.contains("identity.programIndex"))
        #expect(representation.contains("identity.programGeneration"))
        #expect(!representation.contains("UInt64(program.genomeHash)"))
    }

    @Test
    func clonalJunctionsTransportATPAndPayForTransport() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        let transport = try #require(shader.range(of: "float sharingGain ="))
        let mixedPrograms = try #require(shader.range(
            of: "if (otherProgramIndex < maxHeritableProgramCount",
            range: transport.upperBound..<shader.endIndex
        ))
        #expect(transport.lowerBound < mixedPrograms.lowerBound)
        #expect(shader.contains("float sharingContactWeight"))
        #expect(shader.contains("float junctionTransportWork = abs(atpSharingFlux)"))
    }

    @Test
    func junctionMaterialIsInheritedRemodeledAndEnergeticallyPaid() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        #expect(shader.contains("float4 junctionMaterial;"))
        #expect(shader.contains("float4 ecologicalResponse;"))
        #expect(shader.contains("float4 material;"))
        #expect(shader.contains("float4 remodeling;"))
        #expect(shader.contains("junctionMaterial.z * maturity"))
        #expect(shader.contains("float junctionMaterialWork ="))
        #expect(shader.contains("updatedRemodeling.y = mix"))
        #expect(shader.contains("metabolicInvestment * pairAdhesion"))
    }

    @Test
    func developmentalRegulationUsesSixteenLocalSensorsWithoutNamedCellTypes() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        #expect(shader.contains("float regulatorySensors[16]"))
        #expect(shader.contains("node.sensorIndex < 16u"))
        #expect(shader.contains("genome.topology = uint4(12u, 20u"))
        for forbidden in ["sensorCell", "muscleCell", "armorCell", "germCell"] {
            #expect(!shader.contains(forbidden))
        }
    }

    @Test
    func structuralMutationCreatesConnectedFunctionalVariation() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        let start = try #require(shader.range(of: "inline void mutateDevelopmentalGenome"))
        let end = try #require(shader.range(
            of: "struct RegulatoryOutputs",
            range: start.upperBound..<shader.endIndex
        ))
        let mutation = String(shader[start.lowerBound..<end.lowerBound])
        #expect(shader.contains("inline uint activeRegulatoryNodeAtOrdinal"))
        #expect(shader.contains("inline uint activeRegulatoryEdgeAtOrdinal"))
        #expect(shader.contains("inline uint firstInactiveRegulatoryNode"))
        #expect(shader.contains("inline uint firstInactiveRegulatoryEdge"))
        #expect(mutation.contains("uint duplicateIncomingSlot"))
        #expect(mutation.contains("uint duplicateOutgoingSlot"))
        #expect(mutation.contains("copiedEdge.target = targetSlot"))
        #expect(mutation.contains("copiedEdge.source = targetSlot"))
        #expect(mutation.contains("uint activeNodeOrdinal"))
        #expect(mutation.contains("uint activeEdgeOrdinal"))
    }

    @Test
    func extracellularDevelopmentIsPersistentLocalAndEnergeticallyPaid() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        #expect(shader.contains("float4 extracellular = developmentalIn.read"))
        #expect(shader.contains("float4 developmentalLaplacian"))
        #expect(shader.contains("float extracellularReceptorBalance"))
        #expect(shader.contains("float extracellularMatrixConstruction"))
        #expect(shader.contains("cellEnergyExchange, energyTileBase, 8u"))
        #expect(shader.contains("cellEnergyExchange, energyTileBase, 10u"))
        #expect(shader.contains("kernel void damageOrganismCells"))
        #expect(!shader.contains("targetMorphology"))
    }

    @Test
    func separatedFragmentsMustRestartDevelopmentBeforeReproductionIsCounted() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        #expect(shader.contains("componentRegeneratedFlag"))
        #expect(shader.contains("if (agent.generation > 0u)"))
        #expect(shader.contains("agent.componentFlags |= componentRegeneratedFlag"))
        #expect(shader.contains("kernel void markDamagedComponents"))
        #expect(shader.contains("kernel void selectRegenerativeQualificationTarget"))
        #expect(shader.contains("kernel void damageSelectedTargetCells"))
        #expect(shader.contains("kernel void measureQualificationTarget"))
        #expect(shader.contains("componentChallengedFlag"))
        #expect(shader.contains("bool struck = false"))
        #expect(shader.contains("bool completedChallengeWindow"))
        #expect(shader.contains("bool stableHomeostasis = regeneratedDescendant"))
    }

    @Test
    func pairedRegenerationProtocolUsesSameSeedShamAndStrictRecoveryGate() throws {
        let runner = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/RegenerationExperiment.swift"),
            encoding: .utf8
        )
        #expect(runner.contains("mode: .shamRegenerativeTarget"))
        #expect(runner.contains("mode: .targetedRegenerativeWound"))
        #expect(runner.contains("recoveredRelativeToSham"))
        #expect(runner.contains("minimumTrials: 8"))
        #expect(runner.contains("threshold: 0.5"))
        #expect(runner.contains("target_matrix"))
        #expect(runner.contains("target_wound_cue"))
    }

    @Test
    func ecologicalTraitsActThroughLocalPhysicsAndCarryWorkCosts() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        #expect(shader.contains("float toxinTolerance = development.ecologicalResponse.x"))
        #expect(shader.contains("float detritalScavenging = development.ecologicalResponse.y"))
        #expect(shader.contains("float shearAnchoring = development.ecologicalResponse.z"))
        #expect(shader.contains("float starvationQuiescence = development.ecologicalResponse.w"))
        #expect(shader.contains("float ecologicalResponseWork ="))
        #expect(shader.contains("(1.0 - starvationQuiescence * 0.88)"))
    }

    @Test
    func woundsSignalAndCollectiveMotionRequiresForceCoherence() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        #expect(shader.contains("float woundSignal = saturate(damage * 12.0)"))
        #expect(shader.contains("cell.signaling.x = saturate"))
        #expect(shader.contains("translationalMobility *= mix(0.10, 1.0, forceCoherence)"))
        #expect(shader.contains("(membraneExposure - 0.5) * 0.18"))
    }

    @Test
    func executionBackendContainsNoLegacyMetalCommandSubmission() throws {
        let execution = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Metal4Execution.swift"),
            encoding: .utf8
        )
        #expect(execution.contains("MTL4CommandQueue"))
        #expect(execution.contains("MTL4CommandAllocator"))
        #expect(execution.contains("MTL4CommitOptions"))
        #expect(execution.contains("addFeedbackHandler"))
        #expect(!execution.contains("MTLCommandQueue"))
        #expect(!execution.contains("MTLCommandBuffer"))
        #expect(!execution.contains("makeCommandQueue("))
    }

    @Test
    func experimentJournalUsesSchema16() throws {
        let renderer = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/EvolutionRenderer.swift"),
            encoding: .utf8
        )
        #expect(renderer.contains("schemaVersion: 16"))
        #expect(!renderer.contains("schemaVersion: 14"))
    }

    @Test
    func cellularRepairIsLocalPaidAndSelfTerminating() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        let start = try #require(shader.range(of: "kernel void evolveOrganismCells"))
        let end = try #require(shader.range(
            of: "kernel void evolveCellMembranes",
            range: start.upperBound..<shader.endIndex
        ))
        let evolution = String(shader[start.lowerBound..<end.lowerBound])
        #expect(shader.contains("inline float cellularRepairUrgency"))
        #expect(shader.contains("inline float repairAdjustedATPPotential"))
        #expect(evolution.contains("otherSupportPotential - cellSupportPotential"))
        #expect(evolution.contains("float requestedRepairWork = repairUrgency * repairCommitment"))
        #expect(evolution.contains("float paidRepairWork = requestedRepairWork * expenseScale"))
        #expect(evolution.contains("float membraneRepair = paidRepairWork * membraneRepairEfficiency"))
        #expect(evolution.contains("1.0 - recoveryAllocation * 0.94"))
        #expect(shader.contains("float homeostaticEnergySupport = cellularEnergySupport"))
        #expect(shader.contains("homeostaticEnergySupport >= 0.32"))
        #expect(!evolution.contains("atp < 0.18 ? 0.36"))
        #expect(!shader.contains("cellAggregate.physiology.y >= 0.16"))
        #expect(!evolution.contains("componentChallengedFlag"))
        #expect(!evolution.contains("componentQualificationTargetFlag"))
    }

    @Test
    func crossbreedingRequiresCompatibleJunctionAndPreservesTwoProgramParents() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        let definition = try #require(shader.range(of: "inline AgentState recombineCellPrograms"))
        let division = try #require(shader.range(of: "kernel void divideAndReduceOrganismCells"))
        let call = try #require(shader.range(
            of: "recombineCellPrograms(",
            range: definition.upperBound..<shader.endIndex
        ))
        let divisionBody = String(shader[division.lowerBound..<shader.endIndex])
        #expect(call.lowerBound > division.lowerBound)
        #expect(divisionBody.contains("findCellJunction"))
        #expect(divisionBody.contains("recognitionCompatibility"))
        #expect(divisionBody.contains("bilateralInvestment"))
        #expect(divisionBody.contains("recombinationEligible"))
        #expect(divisionBody.contains("junctionMaturity > 0.001"))
        #expect(divisionBody.contains("pow(max(combinedSuitability"))
        #expect(divisionBody.contains("recombinationScore * 0.28"))
        #expect(divisionBody.contains("programCrossbred"))
        #expect(divisionBody.contains("lineageEvents, identityCounters, 6u"))
        #expect(shader.contains("secondParentProgramIndex"))
        #expect(shader.contains("childProgram.ancestryFlags = 1u"))
        #expect(shader.contains("float crossbreedingPreparation = mixedProgramTissue"))
        #expect(shader.contains("crossbreedingPreparation * 0.000075"))
        #expect(shader.contains("fusionEligible && fusionDrive > 0.008"))
        #expect(shader.contains("inheritedA.social.x, inheritedB.social.x"))
        #expect(shader.contains("float nonAggression = 1.0 - saturate(predation * 1.8)"))
        #expect(shader.contains("float localDetachmentGate = mix("))
        #expect(shader.contains("compressiveContactGate"))
        #expect(shader.contains("-0.00001, 0.00036, separatingSpeed"))
        #expect(shader.contains("uint fusionJunction = findOrCreateCellJunction"))
        #expect(shader.contains("junctionStates[fusionJunction].flags = 3u"))
        #expect(shader.contains("identityCounters[13]"))
        #expect(shader.contains("identityCounters[14]"))
        #expect(shader.contains("identityCounters[15]"))
    }

    @Test
    func observerHistoriesRemainBoundedDuringLongRuns() throws {
        let renderer = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/EvolutionRenderer.swift"),
            encoding: .utf8
        )
        let store = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/EvolutionStore.swift"),
            encoding: .utf8
        )
        let lineage = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisCore/LineageAnalysis.swift"),
            encoding: .utf8
        )

        #expect(!renderer.contains("observationSamples"))
        #expect(renderer.contains("selectionHistoryCapacity = 4_096"))
        #expect(renderer.contains("componentContributions.removeAll"))
        #expect(store.contains("pendingComponentContributions.removeAll"))
        #expect(store.contains("let capacity = 8_192"))
        #expect(lineage.contains("maximumRetainedBirths: Int = 8_192"))
        #expect(lineage.contains("pruneHistory(retaining:"))
    }

    @Test
    func repeatedHeadlessRunsReuseReadbacksAndRetainOnlyRequiredResults() throws {
        let renderer = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/EvolutionRenderer.swift"),
            encoding: .utf8
        )
        let headless = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/HeadlessExperiment.swift"),
            encoding: .utf8
        )
        let causal = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/CausalExperiment.swift"),
            encoding: .utf8
        )
        let regeneration = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/RegenerationExperiment.swift"),
            encoding: .utf8
        )

        #expect(renderer.contains("private var headlessReadbackBuffers: HeadlessReadbackBuffers?"))
        #expect(renderer.contains("if let headlessReadbackBuffers { return headlessReadbackBuffers }"))
        #expect(renderer.contains("headlessReadbackBuffers = readback"))
        #expect(renderer.contains("resultRetention.contains(.samples)"))
        #expect(renderer.contains("resultRetention.contains(.events)"))
        #expect(renderer.contains("resultRetention.contains(.componentSnapshots)"))
        #expect(headless.contains("resultRetention: []"))
        #expect(causal.contains("resultRetention: []"))
        #expect(regeneration.contains("resultRetention: .samples"))
    }

    @Test
    func speedSelectorAvoidsTheLeakingMacOSSegmentedPickerAdapter() throws {
        let content = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/ContentView.swift"),
            encoding: .utf8
        )
        let metalView = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/MetalEvolutionView.swift"),
            encoding: .utf8
        )

        #expect(!content.contains("Picker(\"Speed\""))
        #expect(!content.contains(".pickerStyle(.segmented)"))
        #expect(content.contains("ForEach([1, 3, 6, 24]"))
        #expect(metalView.contains("@ObservedObject var store: EvolutionStore"))
    }

    @Test
    func cellRenderingRejectsMalformedMembraneTrianglesAtomically() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        let start = try #require(shader.range(of: "inline CellRasterData makeCellRasterData"))
        let end = try #require(shader.range(
            of: "fragment float4 cellFragment",
            range: start.upperBound..<shader.endIndex
        ))
        let vertex = String(shader[start.lowerBound..<end.lowerBound])
        #expect(vertex.contains("if (cellIndex >= maxCellCount) { return output; }"))
        #expect(vertex.contains("if (owner >= maxAgentCount) { return output; }"))
        #expect(vertex.contains("all(isfinite(membraneStart))"))
        #expect(vertex.contains("all(isfinite(membraneEnd))"))
        #expect(vertex.contains("membraneEdgeLength <= 0.08"))
        #expect(vertex.contains("signedTriangleArea > 0.0000001"))
        #expect(vertex.contains("startRadius <= 0.30"))
        #expect(vertex.contains("endRadius <= 0.30"))
    }

    @Test
    func activeScalePipelinesDoNotRenderCoarseEventFieldFlashes() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        let worldStart = try #require(shader.range(of: "fragment float4 worldSurfaceFragment"))
        let cellStart = try #require(shader.range(
            of: "fragment float4 cellularSurfaceFragment",
            range: worldStart.upperBound..<shader.endIndex
        ))
        let legacyStart = try #require(shader.range(
            of: "fragment float4 worldFragment",
            range: cellStart.upperBound..<shader.endIndex
        ))
        let activeFieldShaders = String(shader[worldStart.lowerBound..<legacyStart.lowerBound])
        #expect(!activeFieldShaders.contains("biologicalEvents"))
        #expect(!activeFieldShaders.contains("localEvents"))
    }

    @Test
    func renderPathCullsOffscreenCellsBeforeRasterization() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        let start = try #require(shader.range(of: "kernel void compactVisibleCells"))
        let end = try #require(shader.range(
            of: "struct RasterData",
            range: start.upperBound..<shader.endIndex
        ))
        let compaction = String(shader[start.lowerBound..<end.lowerBound])
        #expect(compaction.contains("cellWorldPosition(agents[owner], cells[gid].position"))
        #expect(compaction.contains("any(screenUV < -margin)"))
        #expect(compaction.contains("any(screenUV > 1.0 + margin)"))
    }

    @Test
    func causalTissueOverlayUsesPhysicalJunctionStateWithoutFeedingSimulation() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        let renderer = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/EvolutionRenderer.swift"),
            encoding: .utf8
        )
        let causalStart = try #require(shader.range(of: "kernel void evolveOrganismCells"))
        let causalEnd = try #require(shader.range(
            of: "kernel void detectCellTopologyChanges",
            range: causalStart.upperBound..<shader.endIndex
        ))
        let causalCellEvolution = String(shader[causalStart.lowerBound..<causalEnd.lowerBound])
        #expect(!causalCellEvolution.contains("visibleJunctionIndices"))
        #expect(!causalCellEvolution.contains("drawArguments"))
        #expect(shader.contains("kernel void compactVisibleJunctions"))
        #expect(shader.contains("vertex JunctionRasterData junctionVertex"))
        #expect(shader.contains("fragment float4 junctionFragment"))
        #expect(shader.contains("MembraneSupportSample supportA = membraneSupportSample"))
        #expect(shader.contains("bool finiteSupport = all(isfinite(supportA.point))"))
        #expect(shader.contains("length(supportA.point) <= 0.30"))
        #expect(shader.contains("junctionStates[junctionIndex].load / 0.0028"))
        #expect(shader.contains("interactionB.x - interactionA.x"))
        #expect(shader.contains("stateA.signaling.x - stateB.signaling.x"))
        #expect(shader.contains("identityA.programIndex != identityB.programIndex"))
        #expect(renderer.contains("compactJunctionRenderPipeline"))
        #expect(renderer.contains("junctionRenderPipeline"))
        #expect(renderer.contains("indirectBuffer: junctionDrawArguments"))
    }

    @Test
    func renderPathUsesSinglePassBloomAndDirectSpinorDisplay() throws {
        let renderer = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/EvolutionRenderer.swift"),
            encoding: .utf8
        )
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        #expect(renderer.contains("spinorDisplayPipeline"))
        #expect(renderer.contains("if renderScale == 5"))
        #expect(renderer.contains("Single-pass quarter-resolution bloom"))
        #expect(renderer.contains("attachment.loadAction = .clear"))
        #expect(renderer.contains("drawableAttachment.loadAction = .clear"))
        #expect(renderer.contains("commandBuffer.retainResources(["))
        #expect(!renderer.contains("bloomBlurPipeline"))
        #expect(!renderer.contains("bloomTextureB"))
        #expect(shader.contains("fragment float4 spinorDisplayFragment"))
        #expect(shader.contains("inline float4 finiteHDRColor"))
        #expect(shader.contains("return finiteHDRColor(color, 1.08);"))
        #expect(shader.contains("return finiteHDRColor(color, contextExposure);"))
        #expect(!shader.contains("kernel void blurBloom"))
    }

    @Test
    func indirectRenderArgumentsArePrivateRebuiltAndBoundedBeforeDereference() throws {
        let renderer = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/EvolutionRenderer.swift"),
            encoding: .utf8
        )
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )

        #expect(shader.contains("kernel void resetRenderDrawArguments"))
        #expect(shader.contains("kernel void finalizeRenderDrawArguments"))
        #expect(shader.contains("&cellDrawArguments[0], membraneRenderSegmentCount * 3u"))
        #expect(shader.contains("atomic_store_explicit(&junctionDrawArguments[0], 6u"))
        #expect(shader.contains("if (instanceID >= maxCellCount || vertexID >="))
        #expect(shader.contains("if (instanceID >= cellJunctionCapacity || vertexID >= 6u)"))
        #expect(renderer.contains("resetRenderDrawArgumentsPipeline"))
        #expect(renderer.contains("finalizeRenderDrawArgumentsPipeline"))
        #expect(renderer.contains("private final class RenderSubmissionResources"))
        #expect(renderer.contains("0..<Metal4ExecutionContext.maximumInFlightSubmissions"))
        #expect(renderer.contains("commandBuffer.submissionSlotIndex"))
        #expect(renderer.contains("encoder.memoryBarrier(resources: [\n            cellDrawArguments"))
        #expect(!renderer.contains("cellDrawArguments.contents()"))
        #expect(!renderer.contains("junctionDrawArguments.contents()"))
    }

    @Test
    func adaptiveCellMeshPublishesGeometryOnceAndSanitizesRasterOutput() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        let meshStart = try #require(shader.range(of: "void cellContourMesh"))
        let fragmentStart = try #require(shader.range(
            of: "fragment float4 cellFragment",
            range: meshStart.upperBound..<shader.endIndex
        ))
        let mesh = String(shader[meshStart.lowerBound..<fragmentStart.lowerBound])
        #expect(mesh.contains("if (lane == 0u)"))
        #expect(mesh.contains("output.set_primitive_count(segmentCount);"))
        #expect(!mesh.contains("\n    output.set_primitive_count(segmentCount);"))
        #expect(shader.contains("all(abs(screenUV - 0.5) <= float2(1.0))"))
        #expect(shader.contains("if (!all(isfinite(coarseColor)) || !isfinite(coarseAlpha))"))
        #expect(shader.contains("if (!all(isfinite(color)) || !isfinite(alpha))"))
        #expect(shader.contains("any(abs(clipA) > float2(2.5))"))
    }

    @Test
    func metal4SubmissionSlotsOwnReusableArgumentTables() throws {
        let execution = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Metal4Execution.swift"),
            encoding: .utf8
        )
        #expect(execution.contains("let computeArgumentTable: MTL4ArgumentTable"))
        #expect(execution.contains("private let vertexArgumentTables: [MTL4ArgumentTable]"))
        #expect(execution.contains("private let meshArgumentTables: [MTL4ArgumentTable]"))
        #expect(execution.contains("slot.resetArgumentTables()"))
        #expect(execution.contains("slot.nextRenderArgumentTables()"))
    }

    @Test
    func transientRenderMemoryUsesPerSubmissionResidencyAndQueueBarriers() throws {
        let renderer = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/EvolutionRenderer.swift"),
            encoding: .utf8
        )
        let execution = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Metal4Execution.swift"),
            encoding: .utf8
        )

        #expect(renderer.contains("private let renderSubmissionResources: [RenderSubmissionResources]"))
        #expect(renderer.contains("resources.renderTargets = targets"))
        #expect(renderer.contains("renderSubmissionResources.reduce(UInt64(0))"))
        #expect(renderer.contains("device.makeHeap(descriptor: heapDescriptor)"))
        #expect(renderer.contains("residencySet.addAllocation(heap)"))
        #expect(renderer.contains("commandBuffer.useResidencySet(renderTargets.residencySet)"))
        #expect(!execution.contains("dynamicResidencySet"))
        #expect(execution.contains("commandBuffer.useResidencySet(residencySet)"))
        #expect(execution.contains("var submissionSlotIndex: Int { slot.index }"))
        #expect(execution.contains("? [.dispatch, .blit, .vertex, .mesh, .fragment]"))
        #expect(execution.contains("retainedResources.removeAll(keepingCapacity: false)"))
        #expect(execution.contains("drawable = nil"))
    }

    @Test
    func presentationAllowsBoundedConcurrencyAndFailsClosed() throws {
        let renderer = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/EvolutionRenderer.swift"),
            encoding: .utf8
        )
        let execution = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Metal4Execution.swift"),
            encoding: .utf8
        )
        let metalView = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/MetalEvolutionView.swift"),
            encoding: .utf8
        )
        let store = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/EvolutionStore.swift"),
            encoding: .utf8
        )

        #expect(execution.contains(
            "claimedDrawableIDs.count < Self.maximumInFlightSubmissions"
        ))
        #expect(!execution.contains("guard claimedDrawableIDs.isEmpty"))
        #expect(renderer.contains("maximumInteractiveInFlightSubmissions = 2"))
        #expect(renderer.contains(
            "layer.maximumDrawableCount = Metal4ExecutionContext.maximumInFlightSubmissions"
        ))
        #expect(renderer.contains(
            "unfinishedCommandBuffers < interactiveInFlightSubmissionLimit"
        ))
        #expect(renderer.contains(
            "maximumCommandBuffers: interactiveInFlightSubmissionLimit"
        ))
        #expect(renderer.contains("runtimeTelemetryPublicationInterval = 1.0 / 12.0"))
        #expect(renderer.contains("publishRuntimeTelemetry(force: true)"))
        #expect(renderer.contains("updateInteractiveInFlightSubmissionLimit"))
        #expect(store.contains("struct RendererSettings: Sendable, Equatable"))
        #expect(metalView.contains("private var lastRendererSettings: RendererSettings?"))
        #expect(metalView.contains("guard settings != lastRendererSettings else { return }"))
        #expect(renderer.contains("var presentationEncoded = false"))
        #expect(renderer.contains("if !presentationEncoded"))
        #expect(renderer.contains("commandBuffer.cancelPresentation()"))
        let compactionSignature = """
        private func encodeVisibleCellCompaction(
                into commandBuffer: Metal4CommandBufferContext,
                settings: RendererSettings
            ) -> Bool
        """
        let bloomSignature = """
        private func encodeBloom(
                source: MTLTexture,
                textureA: MTLTexture,
                uniforms: inout PostProcessUniforms,
                into commandBuffer: Metal4CommandBufferContext
            ) -> Bool
        """
        #expect(renderer.contains(compactionSignature))
        #expect(renderer.contains(bloomSignature))
    }

    @Test
    func contactAndConnectivityReuseOneBoundedPairStream() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        let pairBuilderStart = try #require(shader.range(of: "kernel void buildMembraneContactPairs"))
        let resolverStart = try #require(shader.range(
            of: "kernel void resolveMembraneContacts",
            range: pairBuilderStart.upperBound..<shader.endIndex
        ))
        let applyStart = try #require(shader.range(
            of: "kernel void applyCellContactEffects",
            range: resolverStart.upperBound..<shader.endIndex
        ))
        let unionStart = try #require(shader.range(of: "kernel void unionCellComponents"))
        let compressStart = try #require(shader.range(
            of: "kernel void compressCellComponents",
            range: unionStart.upperBound..<shader.endIndex
        ))
        let resolver = String(shader[resolverStart.lowerBound..<applyStart.lowerBound])
        let union = String(shader[unionStart.lowerBound..<compressStart.lowerBound])
        #expect(shader.contains("constant uint membraneContactPairCapacity = 524288u"))
        #expect(resolver.contains("device const uint2* contactPairs"))
        #expect(union.contains("device const uint2* contactPairs"))
        #expect(!resolver.contains("hashHeads"))
        #expect(!union.contains("hashHeads"))
        #expect(shader.contains("invariantContactPairOverflow"))
    }

    @Test
    func contactBroadPhaseUsesDirectGridAndLocalOcclusionCoordinates() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        let exposureStart = try #require(shader.range(of: "kernel void measureCellMembraneExposure"))
        let divisionStart = try #require(shader.range(
            of: "kernel void divideAndReduceOrganismCells",
            range: exposureStart.upperBound..<shader.endIndex
        ))
        let exposure = String(shader[exposureStart.lowerBound..<divisionStart.lowerBound])
        #expect(shader.contains("constant uint cellSpatialHashAxisResolution = 128u"))
        #expect(shader.contains("return coordinate.x + coordinate.y * cellSpatialHashAxisResolution"))
        #expect(!shader.contains("visitedBuckets"))
        #expect(exposure.contains("cell.position + localMidpoint - other.position"))
        #expect(!exposure.contains("rotateWorldToTissue"))
    }

    @Test
    func lifecycleQualificationIsObserverOnlyAndCannotStopOnSuccess() throws {
        let lifecycle = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/LifecycleExperiment.swift"),
            encoding: .utf8
        )
        let renderer = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/EvolutionRenderer.swift"),
            encoding: .utf8
        )
        let entrypoint = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/AutogenesisMetalApp.swift"),
            encoding: .utf8
        )

        #expect(lifecycle.contains("causalMutation: \"None."))
        #expect(lifecycle.contains("mode: .shamRegenerativeTarget"))
        #expect(lifecycle.contains("mode: .targetedRegenerativeWound"))
        #expect(lifecycle.contains("valid < configuration.minimumValidCycles"))
        #expect(!lifecycle.contains("completed < configuration.minimumValidCycles"))
        #expect(lifecycle.contains("$0.type == \"fission\" && $0.parentBirthID == targetID"))
        #expect(lifecycle.contains("postRecoveryFissionCount"))
        #expect(lifecycle.contains("reportedGrandchildSnapshots"))
        #expect(lifecycle.contains("stableGrandchildSnapshots"))
        #expect(lifecycle.contains("$0.regeneratedDevelopment && $0.cellCount >= 2"))
        #expect(lifecycle.contains("minimumTrials: configuration.minimumValidCycles"))
        #expect(lifecycle.contains("threshold: 0.5"))
        #expect(renderer.contains("recordedEvents.append(event)"))
        #expect(renderer.contains("recordedComponentSnapshots.append("))
        #expect(entrypoint.contains("case \"lifecycle-experiment\":"))
    }

    @Test
    func componentTopologyIsEventDrivenAndClearsOnlyLivingRoots() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        let renderer = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/EvolutionRenderer.swift"),
            encoding: .utf8
        )
        #expect(shader.contains("componentTopologyReconciliationStride = 256u"))
        #expect(shader.contains("kernel void detectCellTopologyChanges"))
        #expect(shader.contains("currentCount != previousCount || currentHash != previousHash"))
        #expect(shader.contains("bool newSameOwnerConnection"))
        #expect(shader.contains("bool fusionCandidate"))
        #expect(shader.contains("kernel void finalizeCellTopology"))
        #expect(shader.contains("&componentAccumulation[gid * 5u + channel]"))
        #expect(!renderer.contains("encoder.fill(buffer: cellComponentParents"))
        #expect(!renderer.contains("encoder.fill(buffer: cellComponentAccumulation"))
    }

    @Test
    func m4KeepsAdaptiveMeshContoursBehindAnExplicitStabilityGate() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        let renderer = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/EvolutionRenderer.swift"),
            encoding: .utf8
        )
        let execution = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Metal4Execution.swift"),
            encoding: .utf8
        )
        #expect(shader.contains("using CellContourMesh = metal::mesh"))
        #expect(shader.contains("void cellContourMesh("))
        #expect(shader.contains("output.set_primitive_count(segmentCount)"))
        #expect(renderer.contains("NUMI_EXPERIMENTAL_MESH_CELLS"))
        #expect(renderer.contains(
            "if tuningProfile == .m4Optimized && Self.experimentalMeshCellRenderingEnabled"
        ))
        #expect(renderer.contains("cellMeshRenderPipeline"))
        #expect(renderer.contains("cellRenderPipeline"))
        #expect(execution.contains("MTL4MeshRenderPipelineDescriptor"))
        #expect(execution.contains("drawMeshThreadgroups("))
    }

    @Test
    func archiveMissFallbackDoesNotReattachTheRejectedArchive() throws {
        let execution = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Metal4Execution.swift"),
            encoding: .utf8
        )
        #expect(!execution.contains("taskOptions.lookupArchives = [loadedArchive]"))
        #expect(execution.contains("NUMI_ENABLE_METAL4_ARCHIVE"))
        #expect(!execution.contains("NUMI_DISABLE_METAL4_ARCHIVE"))
    }

    @Test
    func membraneRenderingUsesLocalPhysicalState() throws {
        let shader = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/AutogenesisMetal/Shaders/Replicator.metal"),
            encoding: .utf8
        )
        #expect(shader.contains("float4 localMembrane"))
        #expect(shader.contains("saturate(localVertex.mechanics.y)"))
        #expect(shader.contains("saturate(localVertex.mechanics.z * 120.0)"))
        #expect(shader.contains("saturate(abs(localVertex.mechanics.w) * 18.0)"))
        #expect(shader.contains("float membraneContinuity"))
        #expect(shader.contains("float woundArc"))
        #expect(shader.contains("float repairDemand"))
        #expect(shader.contains("float repairFront"))
        #expect(shader.contains("float repairBoundary"))
        #expect(shader.contains("float leakage"))
    }
}
