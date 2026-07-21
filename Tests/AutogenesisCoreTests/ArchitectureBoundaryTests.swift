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
}
