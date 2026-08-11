import Testing
@testable import AutogenesisCore

@Test func sparseOverflowReturnsEveryBasisMaterialAndFreeEnergyAsHeat() {
    let composition = [2.0, 1.0, 0.5, 0, 3, 0, 0.25, 1.25]
    let result = ChemistryConservation.decomposeOverflow(
        amount: 0.4,
        composition: composition,
        freeEnergyPerUnit: 1.5
    )
    #expect(result.basisMaterial == composition.map { $0 * 0.4 })
    #expect(abs(result.heat - 0.6) < 1e-12)
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
