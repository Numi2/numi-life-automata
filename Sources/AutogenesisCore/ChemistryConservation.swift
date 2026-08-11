import Foundation

/// CPU reference math for the invariants enforced by the Metal chemistry.
/// It is intentionally small: the GPU owns simulation state, while tests use
/// this model to verify the conservation contract without parsing shader text.
public enum ChemistryConservation {
    public struct Decomposition: Sendable, Equatable {
        public let basisMaterial: [Double]
        public let heat: Double

        public init(basisMaterial: [Double], heat: Double) {
            self.basisMaterial = basisMaterial
            self.heat = heat
        }
    }

    public struct AssemblyDebit: Sendable, Equatable {
        public let moleculeAmounts: [Double]
        public let moleculeFreeEnergy: [Double]
        public let basisMaterial: [Double]
    }

    public struct SecretionReservation: Sendable, Equatable {
        public let amounts: [Double]
        public let freeEnergy: [Double]

        public var matterCommitted: Double { amounts.reduce(0, +) }
        public var energyCommitted: Double { freeEnergy.reduce(0, +) }
    }

    public static func decomposeOverflow(
        amount: Double,
        composition: [Double],
        freeEnergyPerUnit: Double
    ) -> Decomposition {
        let finiteAmount = amount.isFinite ? max(amount, 0) : 0
        let normalized = Array(composition.prefix(8)).map {
            $0.isFinite ? max($0, 0) : 0
        } + Array(repeating: 0, count: max(8 - composition.count, 0))
        return Decomposition(
            basisMaterial: normalized.map { $0 * finiteAmount },
            heat: max(freeEnergyPerUnit.isFinite ? freeEnergyPerUnit : 0, 0) *
                finiteAmount
        )
    }

    /// Reaction mutation may change rates and activation barriers, but never
    /// elemental composition. Usable work cannot exceed the declared source.
    public static func balanceReaction(
        reactants: [Double],
        declaredEnergySource: Double,
        requestedWork: Double
    ) -> (products: [Double], usableWork: Double) {
        let products = Array(reactants.prefix(8)).map {
            $0.isFinite ? max($0, 0) : 0
        } + Array(repeating: 0, count: max(8 - reactants.count, 0))
        let source = max(declaredEnergySource.isFinite ? declaredEnergySource : 0, 0)
        let work = max(requestedWork.isFinite ? requestedWork : 0, 0)
        return (products, min(work, source))
    }

    /// Assembly is all-or-nothing. A physical constructor may not create a
    /// complete body by partially consuming an undersupplied recipe.
    public static func debitAssembly(
        moleculeAmounts: [Double],
        moleculeFreeEnergy: [Double],
        moleculeCosts: [Double],
        basisMaterial: [Double],
        basisCosts: [Double]
    ) -> AssemblyDebit? {
        let amounts = moleculeAmounts.map(Self.nonnegativeFinite)
        let energies = moleculeFreeEnergy.map(Self.nonnegativeFinite)
        let moleculeRecipe = moleculeCosts.map(Self.nonnegativeFinite)
        let basis = basisMaterial.map(Self.nonnegativeFinite)
        let basisRecipe = basisCosts.map(Self.nonnegativeFinite)
        guard amounts.count == energies.count,
              amounts.count == moleculeRecipe.count,
              basis.count == basisRecipe.count,
              zip(amounts, moleculeRecipe).allSatisfy({ $0.0 >= $0.1 }),
              zip(basis, basisRecipe).allSatisfy({ $0.0 >= $0.1 }) else {
            return nil
        }
        let remainingAmounts = zip(amounts, moleculeRecipe).map { $0.0 - $0.1 }
        let remainingEnergy = zip(zip(energies, amounts), moleculeRecipe).map { entry in
            let ((energy, amount), cost) = entry
            return amount > 0 ? energy * max(1 - cost / amount, 0) : 0
        }
        return AssemblyDebit(
            moleculeAmounts: remainingAmounts,
            moleculeFreeEnergy: remainingEnergy,
            basisMaterial: zip(basis, basisRecipe).map { $0.0 - $0.1 }
        )
    }

    /// Reserve secretion against both cellular matter and energy before any
    /// discretionary work can spend the same stores.
    public static func reserveSecretion(
        requestedAmounts: [Double],
        requestedFreeEnergy: [Double],
        availableMatter: Double,
        availableEnergy: Double
    ) -> SecretionReservation {
        let amounts = requestedAmounts.map(Self.nonnegativeFinite)
        var energies = requestedFreeEnergy.map(Self.nonnegativeFinite)
        if energies.count < amounts.count {
            energies += Array(repeating: 0, count: amounts.count - energies.count)
        } else if energies.count > amounts.count {
            energies = Array(energies.prefix(amounts.count))
        }
        let matter = nonnegativeFinite(availableMatter)
        let energy = nonnegativeFinite(availableEnergy)
        let requestedMatter = amounts.reduce(0, +)
        let matterScale = requestedMatter > 0 ? min(matter / requestedMatter, 1) : 1
        let matterBoundAmounts = amounts.map { $0 * matterScale }
        let matterBoundEnergy = energies.map { $0 * matterScale }
        let requestedEnergy = matterBoundEnergy.reduce(0, +)
        let energyScale = requestedEnergy > 0 ? min(energy / requestedEnergy, 1) : 1
        return SecretionReservation(
            amounts: matterBoundAmounts.map { $0 * energyScale },
            freeEnergy: matterBoundEnergy.map { $0 * energyScale }
        )
    }

    private static func nonnegativeFinite(_ value: Double) -> Double {
        value.isFinite ? max(value, 0) : 0
    }
}
