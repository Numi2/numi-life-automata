import Testing
@testable import AutogenesisCore

@Test func sparseOverflowReturnsEveryBasisMaterialAndFreeEnergyAsHeat() {
    let composition = [2.0, 1.0, 0.5, 0, 0.25, 0, 0.25, 0]
    let result = ChemistryConservation.decomposeOverflow(
        amount: 0.4,
        composition: composition,
        freeEnergyPerUnit: 1.5
    )
    let compositionTotal = composition.reduce(0, +)
    #expect(result.basisMaterial == composition.map { $0 / compositionTotal * 0.4 })
    #expect(abs(result.basisMaterial.reduce(0, +) - 0.4) < 1e-12)
    #expect(abs(result.heat - 0.6) < 1e-12)
}

@Test func exhaustedGenomeArenaDoesNotAdvanceItsCursor() {
    #expect(ChemistryConservation.reserveArenaRange(
        cursor: 65_530, requestedCount: 8, capacity: 65_536
    ) == nil)
    #expect(ChemistryConservation.reserveArenaRange(
        cursor: 65_530, requestedCount: 6, capacity: 65_536
    ) == 65_530..<65_536)
}

@Test func damageRedistributesBasisMatterWithoutCreatingOrDeletingIt() {
    let a = [0.8, 0.7, 0.6, 0.5]
    let b = [0.4, 0.3, 0.2, 0.1]
    let before = (a + b).reduce(0, +)
    let result = ChemistryConservation.redistributeDamage(
        basisA: a, basisB: b, impact: 0.73
    )
    let after = (result.basisA + result.basisB).reduce(0, +)
    #expect(abs(after - before) < 1e-12)
}

@Test func persistentPolymerCannotBeCountedAsFreeAndRetainedMatter() {
    let result = ChemistryConservation.advancePersistentStructure(
        freePolymer: 0.8,
        retainedPolymer: 0.3,
        depositionFraction: 0.25,
        erosion: 0.1
    )
    #expect(abs(result.free - 0.6) < 1e-12)
    #expect(abs(result.retained - 0.4) < 1e-12)
    #expect(abs(result.returnedToBasis - 0.1) < 1e-12)
    #expect(abs(result.free + result.retained + result.returnedToBasis - 1.1) < 1e-12)
}

@Test func parallelContactRequestsCannotDuplicateSourceOrOverflowReceiver() {
    let accepted = ChemistryConservation.settleContactTransfers(
        requested: [0.09, 0.07, 0.12],
        sourceCapacity: 0.14,
        receiverCapacity: 0.11
    )
    #expect(abs(accepted[0] - 0.09) < 1e-12)
    #expect(abs(accepted[1] - 0.02) < 1e-12)
    #expect(accepted[2] == 0.0)
    #expect(abs(accepted.reduce(0, +) - 0.11) < 1e-12)
}

@Test func reactionMutationCannotChangeCompositionOrCreateWork() {
    let reactants = [1.0, 0.5, 0, 2, 0, 0.25, 0.75, 0]
    let balanced = ChemistryConservation.balanceReaction(
        reactants: reactants,
        declaredEnergySource: 0.3,
        requestedWork: 4.0
    )
    #expect(balanced.products == reactants)
    #expect(abs(balanced.usableWork - 0.3) < 1e-12)
}

@Test func invalidChemistryInputsCannotInjectMatterOrEnergy() {
    let overflow = ChemistryConservation.decomposeOverflow(
        amount: -.infinity,
        composition: [.nan, -1],
        freeEnergyPerUnit: .infinity
    )
    #expect(overflow.basisMaterial == Array(repeating: 0, count: 8))
    #expect(overflow.heat == 0)
}

@Test func protocellAssemblyIsExactAndAllOrNothing() {
    let debit = ChemistryConservation.debitAssembly(
        moleculeAmounts: [0.045, 0.020, 0.030],
        moleculeFreeEnergy: [0.0063, 0.0036, 0.0084],
        moleculeCosts: [0.010, 0.004, 0.007],
        basisMaterial: [0.09, 0.055, 0.034, 0.022, 0.030, 0.015, 0.020, 0.135],
        basisCosts: [0.006, 0.004, 0, 0, 0, 0, 0, 0.012]
    )
    #expect(debit != nil)
    #expect(abs(debit!.moleculeAmounts[0] - 0.035) < 1e-12)
    #expect(abs(debit!.moleculeFreeEnergy[0] - 0.0049) < 1e-12)
    #expect(abs(debit!.basisMaterial[7] - 0.123) < 1e-12)

    let undersupplied = ChemistryConservation.debitAssembly(
        moleculeAmounts: [0.009, 0.020, 0.030],
        moleculeFreeEnergy: [0.001, 0.0036, 0.0084],
        moleculeCosts: [0.010, 0.004, 0.007],
        basisMaterial: Array(repeating: 1, count: 8),
        basisCosts: Array(repeating: 0, count: 8)
    )
    #expect(undersupplied == nil)
}

@Test func secretionCannotSpendMatterOrEnergyTwice() {
    let reserved = ChemistryConservation.reserveSecretion(
        requestedAmounts: [0.6, 0.4],
        requestedFreeEnergy: [0.3, 0.2],
        availableMatter: 0.5,
        availableEnergy: 0.1
    )
    #expect(abs(reserved.matterCommitted - 0.2) < 1e-12)
    #expect(abs(reserved.energyCommitted - 0.1) < 1e-12)
}
