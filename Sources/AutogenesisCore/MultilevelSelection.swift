import Foundation

/// A sampled count of one inherited program inside one physical component.
/// These records are observer outputs; the causal solver never consumes them.
public struct ProgramRepresentation: Codable, Sendable, Equatable {
    public let componentID: UInt64
    public let programID: UInt64
    public let parentProgramID: UInt64?
    public let cellCount: Int
    public let inheritedTrait: Double
    public let collectiveTrait: Double

    public init(
        componentID: UInt64,
        programID: UInt64,
        parentProgramID: UInt64?,
        cellCount: Int,
        inheritedTrait: Double,
        collectiveTrait: Double
    ) {
        self.componentID = componentID
        self.programID = programID
        self.parentProgramID = parentProgramID
        self.cellCount = max(cellCount, 0)
        self.inheritedTrait = inheritedTrait.isFinite ? inheritedTrait : 0
        self.collectiveTrait = collectiveTrait.isFinite ? collectiveTrait : 0
    }
}

public struct ComponentContribution: Codable, Sendable, Hashable {
    public let descendantID: UInt64
    public let contributorID: UInt64

    public init(descendantID: UInt64, contributorID: UInt64) {
        self.descendantID = descendantID
        self.contributorID = contributorID
    }
}

public struct TraitResemblancePair: Codable, Sendable, Equatable {
    public let parent: Double
    public let descendant: Double

    public init(parent: Double, descendant: Double) {
        self.parent = parent
        self.descendant = descendant
    }
}

public struct MultilevelSelectionInterval: Codable, Sendable, Equatable {
    public let betweenComponentSelection: Double
    public let withinComponentSelection: Double
    public let transmissionChange: Double
    public let contributingParentComponents: Int
    public let independentDescendantComponents: Int
    public let transmittedVariantCount: Int
    public let collectiveResemblance: [TraitResemblancePair]

    public init(
        betweenComponentSelection: Double,
        withinComponentSelection: Double,
        transmissionChange: Double,
        contributingParentComponents: Int,
        independentDescendantComponents: Int,
        transmittedVariantCount: Int,
        collectiveResemblance: [TraitResemblancePair]
    ) {
        self.betweenComponentSelection = betweenComponentSelection
        self.withinComponentSelection = withinComponentSelection
        self.transmissionChange = transmissionChange
        self.contributingParentComponents = contributingParentComponents
        self.independentDescendantComponents = independentDescendantComponents
        self.transmittedVariantCount = transmittedVariantCount
        self.collectiveResemblance = collectiveResemblance
    }
}

public enum MultilevelPriceAnalysis {
    /// Partitions change in an inherited cellular trait across independently
    /// separated descendant components. Continued occupancy of the same
    /// component is deliberately excluded from reproductive success.
    public static func interval(
        parent: [ProgramRepresentation],
        descendant: [ProgramRepresentation],
        contributions: Set<ComponentContribution>
    ) -> MultilevelSelectionInterval {
        let parentByComponent = Dictionary(grouping: parent.filter { $0.cellCount > 0 }) {
            $0.componentID
        }
        let descendantByComponent = Dictionary(
            grouping: descendant.filter { $0.cellCount > 0 }
        ) { $0.componentID }
        let newDescendantComponentIDs = Set(descendantByComponent.keys).subtracting(
            parentByComponent.keys
        )
        let contributorGraph = Dictionary(grouping: contributions, by: \.descendantID)
            .mapValues { Set($0.map(\.contributorID)) }
        var programParents: [UInt64: UInt64] = [:]
        for row in parent + descendant {
            if let parentProgramID = row.parentProgramID {
                programParents[row.programID] = parentProgramID
            }
        }

        func componentDescends(_ candidate: UInt64, from ancestor: UInt64) -> Bool {
            guard candidate != ancestor else { return false }
            var frontier = Array(contributorGraph[candidate] ?? [])
            var visited: Set<UInt64> = []
            while let current = frontier.popLast() {
                if current == ancestor { return true }
                if visited.insert(current).inserted {
                    frontier.append(contentsOf: contributorGraph[current] ?? [])
                }
            }
            return false
        }

        func programDescends(_ candidate: UInt64, from ancestor: UInt64) -> Bool {
            if candidate == ancestor { return true }
            var current = candidate
            var visited: Set<UInt64> = []
            while let parentID = programParents[current], visited.insert(current).inserted {
                if parentID == ancestor { return true }
                current = parentID
            }
            return false
        }

        struct ProgramOutcome {
            let parent: ProgramRepresentation
            let fitness: Double
            let descendantTrait: Double
        }
        struct ComponentOutcome {
            let initialCount: Double
            let meanTrait: Double
            let fitness: Double
            let programOutcomes: [ProgramOutcome]
        }

        var componentOutcomes: [ComponentOutcome] = []
        var independentDescendants: Set<UInt64> = []
        var transmittedVariants: Set<UInt64> = []
        var resemblance: [TraitResemblancePair] = []

        for (componentID, parentRows) in parentByComponent {
            let descendantComponents = descendantByComponent.filter {
                newDescendantComponentIDs.contains($0.key) &&
                    componentDescends($0.key, from: componentID)
            }
            independentDescendants.formUnion(descendantComponents.keys)

            let initialCount = Double(parentRows.reduce(0) { $0 + $1.cellCount })
            guard initialCount > 0 else { continue }
            let parentCollectiveTrait = parentRows.reduce(0.0) {
                $0 + $1.collectiveTrait * Double($1.cellCount)
            } / initialCount
            for rows in descendantComponents.values {
                let count = Double(rows.reduce(0) { $0 + $1.cellCount })
                guard count > 0 else { continue }
                resemblance.append(TraitResemblancePair(
                    parent: parentCollectiveTrait,
                    descendant: rows.reduce(0.0) {
                        $0 + $1.collectiveTrait * Double($1.cellCount)
                    } / count
                ))
            }

            var programOutcomes: [ProgramOutcome] = []
            for parentRow in parentRows {
                let transmitted = descendantComponents.values.flatMap { $0 }.filter {
                    programDescends($0.programID, from: parentRow.programID)
                }
                transmittedVariants.formUnion(transmitted.compactMap {
                    $0.programID == parentRow.programID ? nil : $0.programID
                })
                let representation = Double(transmitted.reduce(0) { $0 + $1.cellCount })
                let descendantTrait = representation > 0 ? transmitted.reduce(0.0) {
                    $0 + $1.inheritedTrait * Double($1.cellCount)
                } / representation : parentRow.inheritedTrait
                programOutcomes.append(ProgramOutcome(
                    parent: parentRow,
                    fitness: representation / Double(max(parentRow.cellCount, 1)),
                    descendantTrait: descendantTrait
                ))
            }
            let descendantCount = programOutcomes.reduce(0.0) {
                $0 + $1.fitness * Double($1.parent.cellCount)
            }
            componentOutcomes.append(ComponentOutcome(
                initialCount: initialCount,
                meanTrait: parentRows.reduce(0.0) {
                    $0 + $1.inheritedTrait * Double($1.cellCount)
                } / initialCount,
                fitness: descendantCount / initialCount,
                programOutcomes: programOutcomes
            ))
        }

        let initialTotal = componentOutcomes.reduce(0.0) { $0 + $1.initialCount }
        let meanFitness = initialTotal > 0 ? componentOutcomes.reduce(0.0) {
            $0 + $1.fitness * $1.initialCount
        } / initialTotal : 0
        let meanTrait = initialTotal > 0 ? componentOutcomes.reduce(0.0) {
            $0 + $1.meanTrait * $1.initialCount
        } / initialTotal : 0
        guard initialTotal > 0, meanFitness > 0 else {
            return MultilevelSelectionInterval(
                betweenComponentSelection: 0,
                withinComponentSelection: 0,
                transmissionChange: 0,
                contributingParentComponents: componentOutcomes.count,
                independentDescendantComponents: independentDescendants.count,
                transmittedVariantCount: transmittedVariants.count,
                collectiveResemblance: resemblance
            )
        }

        let between = componentOutcomes.reduce(0.0) {
            $0 + $1.initialCount * ($1.meanTrait - meanTrait) * ($1.fitness - meanFitness)
        } / initialTotal / meanFitness
        let withinNumerator = componentOutcomes.reduce(0.0) { total, component in
            total + component.programOutcomes.reduce(0.0) {
                $0 + Double($1.parent.cellCount) *
                    ($1.parent.inheritedTrait - component.meanTrait) *
                    ($1.fitness - component.fitness)
            }
        }
        let transmissionNumerator = componentOutcomes.reduce(0.0) { total, component in
            total + component.programOutcomes.reduce(0.0) {
                $0 + Double($1.parent.cellCount) * $1.fitness *
                    ($1.descendantTrait - $1.parent.inheritedTrait)
            }
        }
        return MultilevelSelectionInterval(
            betweenComponentSelection: between,
            withinComponentSelection: withinNumerator / initialTotal / meanFitness,
            transmissionChange: transmissionNumerator / initialTotal / meanFitness,
            contributingParentComponents: componentOutcomes.count,
            independentDescendantComponents: independentDescendants.count,
            transmittedVariantCount: transmittedVariants.count,
            collectiveResemblance: resemblance
        )
    }

    public static func summarize(
        _ intervals: [MultilevelSelectionInterval],
        resamples: Int = 512,
        seed: UInt64 = 0x5052_4943_45
    ) -> SelectionPartition {
        let informative = intervals.filter {
            $0.contributingParentComponents > 0 && $0.independentDescendantComponents > 0
        }
        let between = informative.map(\.betweenComponentSelection)
        let within = informative.map(\.withinComponentSelection)
        let transmission = informative.map(\.transmissionChange)
        let pairs = informative.flatMap(\.collectiveResemblance)
        return SelectionPartition(
            betweenComponentSelection: mean(between),
            withinComponentSelection: mean(within),
            transmissionChange: mean(transmission),
            covarianceSampleCount: informative.reduce(0) {
                $0 + $1.contributingParentComponents
            },
            betweenComponentConfidence: bootstrapMean(
                between, resamples: resamples, seed: seed
            ),
            withinComponentConfidence: bootstrapMean(
                within, resamples: resamples, seed: seed ^ 0x5749_5448_494e
            ),
            transmissionConfidence: bootstrapMean(
                transmission, resamples: resamples, seed: seed ^ 0x5452_414e_534d
            ),
            collectiveHeritability: bootstrapCorrelation(
                pairs, resamples: resamples, seed: seed ^ 0x4845_5245_4449_5459
            ),
            independentDescendantCount: informative.reduce(0) {
                $0 + $1.independentDescendantComponents
            },
            transmittedVariantCount: informative.reduce(0) {
                $0 + $1.transmittedVariantCount
            }
        )
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func bootstrapMean(
        _ values: [Double],
        resamples: Int,
        seed: UInt64
    ) -> ConfidenceInterval? {
        guard values.count >= 3 else { return nil }
        var rng = SelectionRNG(state: seed)
        let draws = (0..<max(resamples, 32)).map { _ in
            mean((0..<values.count).map { _ in values[rng.index(values.count)] })
        }.sorted()
        return ConfidenceInterval(
            estimate: mean(values),
            lower: quantile(draws, 0.025),
            upper: quantile(draws, 0.975),
            effectiveSampleCount: Double(values.count)
        )
    }

    private static func bootstrapCorrelation(
        _ pairs: [TraitResemblancePair],
        resamples: Int,
        seed: UInt64
    ) -> ConfidenceInterval? {
        guard pairs.count >= 4, let observed = correlation(pairs) else { return nil }
        var rng = SelectionRNG(state: seed)
        let draws = (0..<max(resamples, 32)).compactMap { _ in
            correlation((0..<pairs.count).map { _ in pairs[rng.index(pairs.count)] })
        }.sorted()
        guard !draws.isEmpty else { return nil }
        return ConfidenceInterval(
            estimate: observed,
            lower: quantile(draws, 0.025),
            upper: quantile(draws, 0.975),
            effectiveSampleCount: Double(pairs.count)
        )
    }

    private static func correlation(_ pairs: [TraitResemblancePair]) -> Double? {
        let parentMean = mean(pairs.map(\.parent))
        let childMean = mean(pairs.map(\.descendant))
        let covariance = pairs.reduce(0.0) {
            $0 + ($1.parent - parentMean) * ($1.descendant - childMean)
        }
        let parentVariance = pairs.reduce(0.0) {
            $0 + pow($1.parent - parentMean, 2)
        }
        let childVariance = pairs.reduce(0.0) {
            $0 + pow($1.descendant - childMean, 2)
        }
        let denominator = sqrt(parentVariance * childVariance)
        return denominator > 1e-20 ? min(max(covariance / denominator, -1), 1) : nil
    }

    private static func quantile(_ sorted: [Double], _ probability: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let coordinate = min(max(probability, 0), 1) * Double(sorted.count - 1)
        let lower = Int(floor(coordinate))
        let upper = Int(ceil(coordinate))
        if lower == upper { return sorted[lower] }
        return sorted[lower] + (sorted[upper] - sorted[lower]) *
            (coordinate - Double(lower))
    }
}

private struct SelectionRNG {
    var state: UInt64

    mutating func index(_ upperBound: Int) -> Int {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Int(value % UInt64(upperBound))
    }
}
