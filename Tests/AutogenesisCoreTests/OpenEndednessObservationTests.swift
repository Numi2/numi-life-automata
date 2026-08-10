import Testing
@testable import AutogenesisCore

@Test func observerNeverOrdersOrSelectsWorlds() {
    var observer = OpenEndednessObserver(capacity: 32)
    let observation = observer.observe(.init(
        step: 10,
        persistentHeritableNovelty: 0.1,
        functionalDiversity: 0.2,
        interactionDiversity: 0.3,
        programComplexity: 0.4,
        ecologicalTurnover: 0.5,
        lineageDivergence: 0.6,
        individualityShift: 0.7
    ))
    #expect(observation.current.step == 10)
    #expect(observation.current.dimensions.count == 7)
    #expect(!observation.sustainedPlateau)
}

@Test func observerDetectsOnlyPersistentMultiWindowPlateaus() {
    var observer = OpenEndednessObserver(capacity: 160, relativeActivityThreshold: 0.000_01)
    var observation = OpenEndednessObservation.empty
    for step in 1...140 {
        observation = observer.observe(.init(
            step: UInt64(step),
            persistentHeritableNovelty: 1,
            functionalDiversity: 1,
            interactionDiversity: 1,
            programComplexity: 1,
            ecologicalTurnover: 1,
            lineageDivergence: 1,
            individualityShift: 1
        ))
    }
    #expect(observation.sustainedPlateau)
    #expect(observation.longWindow.sampleCount == 128)
}

@Test func replacementAtTheSameStepIsDeterministic() {
    var observer = OpenEndednessObserver(capacity: 32)
    _ = observer.observe(.init(
        step: 1, persistentHeritableNovelty: 1, functionalDiversity: 1,
        interactionDiversity: 1, programComplexity: 1, ecologicalTurnover: 1,
        lineageDivergence: 1, individualityShift: 1
    ))
    let replacement = OpenEndednessSample(
        step: 1, persistentHeritableNovelty: 2, functionalDiversity: 2,
        interactionDiversity: 2, programComplexity: 2, ecologicalTurnover: 2,
        lineageDivergence: 2, individualityShift: 2
    )
    let observation = observer.observe(replacement)
    #expect(observer.samples == [replacement])
    #expect(observation.current == replacement)
}
