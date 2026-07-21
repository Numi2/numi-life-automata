import Testing
@testable import AutogenesisCore

struct MultilevelSelectionTests {
    @Test
    func reproductiveSuccessCountsOnlyIndependentDescendants() {
        let parent = [
            ProgramRepresentation(
                componentID: 1, programID: 10, parentProgramID: nil,
                cellCount: 4, inheritedTrait: 0.8, collectiveTrait: 0.7
            ),
            ProgramRepresentation(
                componentID: 2, programID: 20, parentProgramID: nil,
                cellCount: 4, inheritedTrait: 0.2, collectiveTrait: 0.3
            )
        ]
        let descendant = [
            ProgramRepresentation(
                componentID: 1, programID: 10, parentProgramID: nil,
                cellCount: 20, inheritedTrait: 0.8, collectiveTrait: 0.7
            ),
            ProgramRepresentation(
                componentID: 3, programID: 10, parentProgramID: nil,
                cellCount: 8, inheritedTrait: 0.8, collectiveTrait: 0.72
            ),
            ProgramRepresentation(
                componentID: 4, programID: 20, parentProgramID: nil,
                cellCount: 1, inheritedTrait: 0.2, collectiveTrait: 0.28
            )
        ]
        let interval = MultilevelPriceAnalysis.interval(
            parent: parent,
            descendant: descendant,
            contributions: [
                ComponentContribution(descendantID: 3, contributorID: 1),
                ComponentContribution(descendantID: 4, contributorID: 2)
            ]
        )

        #expect(interval.independentDescendantComponents == 2)
        #expect(interval.contributingParentComponents == 2)
        #expect(interval.betweenComponentSelection > 0)
        #expect(interval.withinComponentSelection == 0)
    }

    @Test
    func cellDivisionMutationContributesTransmissionChange() {
        let interval = MultilevelPriceAnalysis.interval(
            parent: [ProgramRepresentation(
                componentID: 1, programID: 10, parentProgramID: nil,
                cellCount: 2, inheritedTrait: 0.4, collectiveTrait: 0.5
            )],
            descendant: [ProgramRepresentation(
                componentID: 2, programID: 11, parentProgramID: 10,
                cellCount: 2, inheritedTrait: 0.6, collectiveTrait: 0.55
            )],
            contributions: [ComponentContribution(descendantID: 2, contributorID: 1)]
        )

        #expect(interval.transmissionChange > 0.19)
    }

    @Test
    func persistentDescendantIsNotRecountedAsNewReproduction() {
        let previous = [
            ProgramRepresentation(
                componentID: 1, programID: 10, parentProgramID: nil,
                cellCount: 4, inheritedTrait: 0.5, collectiveTrait: 0.6
            ),
            ProgramRepresentation(
                componentID: 2, programID: 10, parentProgramID: nil,
                cellCount: 2, inheritedTrait: 0.5, collectiveTrait: 0.58
            )
        ]
        let current = [
            ProgramRepresentation(
                componentID: 1, programID: 10, parentProgramID: nil,
                cellCount: 5, inheritedTrait: 0.5, collectiveTrait: 0.61
            ),
            ProgramRepresentation(
                componentID: 2, programID: 10, parentProgramID: nil,
                cellCount: 3, inheritedTrait: 0.5, collectiveTrait: 0.59
            )
        ]
        let interval = MultilevelPriceAnalysis.interval(
            parent: previous,
            descendant: current,
            contributions: [ComponentContribution(descendantID: 2, contributorID: 1)]
        )

        #expect(interval.independentDescendantComponents == 0)
        #expect(interval.betweenComponentSelection == 0)
    }

    @Test
    func selectionSummaryReportsUncertaintyForEveryPriceTerm() {
        var intervals: [MultilevelSelectionInterval] = []
        for index in 0..<6 {
            let sample = Double(index)
            let pair = TraitResemblancePair(
                parent: sample,
                descendant: sample * 0.9 + 0.1
            )
            intervals.append(MultilevelSelectionInterval(
                betweenComponentSelection: 0.08 + sample * 0.01,
                withinComponentSelection: -0.03 + sample * 0.002,
                transmissionChange: 0.01 + sample * 0.001,
                contributingParentComponents: 3,
                independentDescendantComponents: 2,
                collectiveResemblance: [pair]
            ))
        }

        let summary = MultilevelPriceAnalysis.summarize(intervals, resamples: 64)

        #expect(summary.betweenComponentConfidence != nil)
        #expect(summary.withinComponentConfidence != nil)
        #expect(summary.transmissionConfidence != nil)
        #expect(summary.collectiveHeritability != nil)
    }
}
