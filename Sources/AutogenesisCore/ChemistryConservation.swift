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
}
