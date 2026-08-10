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
