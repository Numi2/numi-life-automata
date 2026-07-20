import Foundation

public struct WorldMetrics: Sendable, Equatable {
    public var biomassDensity: Double
    public var resourceDensity: Double
    public var energyDensity: Double
    public var occupiedFraction: Double
    public var temporalActivity: Double
    public var boundaryCoherence: Double
    public var multiscaleDivergence: Double
    public var recovery: Double
    public var geneticDiversity: Double
    public var lineageDiversity: Double
    public var nicheDifferentiation: Double
    public var trophicActivity: Double
    public var substrateFluctuation: Double
    public var detritusDensity: Double
    public var barrierFraction: Double
    public var environmentalMechanicalDrive: Double
    public var centroidX: Double
    public var centroidY: Double

    public init(
        biomassDensity: Double,
        resourceDensity: Double,
        energyDensity: Double,
        occupiedFraction: Double,
        temporalActivity: Double,
        boundaryCoherence: Double,
        multiscaleDivergence: Double,
        recovery: Double,
        geneticDiversity: Double,
        lineageDiversity: Double = 0,
        nicheDifferentiation: Double = 0,
        trophicActivity: Double = 0,
        substrateFluctuation: Double = 0,
        detritusDensity: Double = 0,
        barrierFraction: Double = 0,
        environmentalMechanicalDrive: Double = 0,
        centroidX: Double,
        centroidY: Double
    ) {
        self.biomassDensity = biomassDensity
        self.resourceDensity = resourceDensity
        self.energyDensity = energyDensity
        self.occupiedFraction = occupiedFraction
        self.temporalActivity = temporalActivity
        self.boundaryCoherence = boundaryCoherence
        self.multiscaleDivergence = multiscaleDivergence
        self.recovery = recovery
        self.geneticDiversity = geneticDiversity
        self.lineageDiversity = lineageDiversity
        self.nicheDifferentiation = nicheDifferentiation
        self.trophicActivity = trophicActivity
        self.substrateFluctuation = substrateFluctuation
        self.detritusDensity = detritusDensity
        self.barrierFraction = barrierFraction
        self.environmentalMechanicalDrive = environmentalMechanicalDrive
        self.centroidX = centroidX
        self.centroidY = centroidY
    }

    public static let empty = WorldMetrics(
        biomassDensity: 0,
        resourceDensity: 0,
        energyDensity: 0,
        occupiedFraction: 0,
        temporalActivity: 0,
        boundaryCoherence: 0,
        multiscaleDivergence: 0,
        recovery: 0,
        geneticDiversity: 0,
        lineageDiversity: 0,
        nicheDifferentiation: 0,
        trophicActivity: 0,
        substrateFluctuation: 0,
        detritusDensity: 0,
        barrierFraction: 0,
        environmentalMechanicalDrive: 0,
        centroidX: 0.5,
        centroidY: 0.5
    )

    public var descriptor: BehaviorDescriptor {
        BehaviorDescriptor(values: [
            occupiedFraction,
            biomassDensity,
            energyDensity,
            temporalActivity,
            boundaryCoherence,
            multiscaleDivergence,
            recovery,
            geneticDiversity,
            lineageDiversity,
            nicheDifferentiation,
            trophicActivity,
            substrateFluctuation,
            detritusDensity,
            barrierFraction,
            environmentalMechanicalDrive,
            centroidX,
            centroidY
        ].map(Self.unit))
    }

    private static func unit(_ value: Double) -> Double {
        min(max(value.isFinite ? value : 0, 0), 1)
    }
}

public struct BehaviorDescriptor: Sendable, Equatable {
    public let values: [Double]

    public init(values: [Double]) {
        self.values = values.map { min(max($0.isFinite ? $0 : 0, 0), 1) }
    }

    public func distance(to other: BehaviorDescriptor) -> Double {
        guard values.count == other.values.count, !values.isEmpty else { return 1 }
        let squared = zip(values, other.values).reduce(0.0) { partial, pair in
            let delta = pair.0 - pair.1
            return partial + delta * delta
        }
        return sqrt(squared / Double(values.count))
    }
}

public struct FitnessVector: Sendable, Equatable {
    public let viability: Double
    public let adaptiveComplexity: Double
    public let recovery: Double
    public let novelty: Double
    public let diversification: Double

    public init(viability: Double, adaptiveComplexity: Double, recovery: Double, novelty: Double) {
        self.init(
            viability: viability,
            adaptiveComplexity: adaptiveComplexity,
            recovery: recovery,
            novelty: novelty,
            diversification: 0
        )
    }

    public init(
        viability: Double,
        adaptiveComplexity: Double,
        recovery: Double,
        novelty: Double,
        diversification: Double
    ) {
        self.viability = viability
        self.adaptiveComplexity = adaptiveComplexity
        self.recovery = recovery
        self.novelty = novelty
        self.diversification = diversification
    }

    public var objectives: [Double] {
        [viability, adaptiveComplexity, recovery, diversification, novelty]
    }

    public func dominates(_ other: FitnessVector, epsilon: Double = 1e-9) -> Bool {
        let pairs = zip(objectives, other.objectives)
        let neverWorse = pairs.allSatisfy { $0 + epsilon >= $1 }
        let betterSomewhere = zip(objectives, other.objectives).contains { pair in
            pair.0 > pair.1 + epsilon
        }
        return neverWorse && betterSomewhere
    }
}

public struct RankedWorld: Sendable, Equatable {
    public let worldIndex: Int
    public let metrics: WorldMetrics
    public let fitness: FitnessVector
    public let paretoRank: Int
    public let crowdingDistance: Double
}

public struct EvolutionDecision: Sendable, Equatable {
    public let rankedWorlds: [RankedWorld]
    public let eliteWorlds: [Int]
    public let parentForWorld: [Int]
    public let archiveCount: Int
}

public struct NoveltyArchive: Sendable {
    public private(set) var descriptors: [BehaviorDescriptor] = []
    public var capacity: Int
    public var neighbors: Int
    public var insertionThreshold: Double

    public init(capacity: Int = 512, neighbors: Int = 5, insertionThreshold: Double = 0.075) {
        self.capacity = max(capacity, 1)
        self.neighbors = max(neighbors, 1)
        self.insertionThreshold = max(insertionThreshold, 0)
    }

    public func novelty(
        of descriptor: BehaviorDescriptor,
        population: [BehaviorDescriptor] = []
    ) -> Double {
        let distances = (descriptors + population)
            .map { descriptor.distance(to: $0) }
            .filter { $0 > 1e-12 }
            .sorted()
        guard !distances.isEmpty else { return 1 }
        let count = min(neighbors, distances.count)
        return distances.prefix(count).reduce(0, +) / Double(count)
    }

    public mutating func consider(_ descriptor: BehaviorDescriptor, novelty: Double, viable: Bool) {
        guard viable, (descriptors.isEmpty || novelty >= insertionThreshold) else { return }
        descriptors.append(descriptor)
        if descriptors.count > capacity {
            descriptors.removeFirst(descriptors.count - capacity)
        }
    }
}

public struct AdaptiveComplexityEvaluator: Sendable {
    public private(set) var archive: NoveltyArchive
    public var eliteCount: Int
    private var random: SplitMix64

    public init(seed: UInt64, eliteCount: Int = 4, archive: NoveltyArchive = NoveltyArchive()) {
        self.archive = archive
        self.eliteCount = max(eliteCount, 1)
        self.random = SplitMix64(seed: seed)
    }

    public mutating func evaluate(_ worlds: [WorldMetrics]) -> EvolutionDecision {
        guard !worlds.isEmpty else {
            return EvolutionDecision(
                rankedWorlds: [], eliteWorlds: [], parentForWorld: [], archiveCount: archive.descriptors.count
            )
        }

        let descriptors = worlds.map(\.descriptor)
        let novelties = descriptors.enumerated().map { index, descriptor in
            var peers = descriptors
            peers.remove(at: index)
            return archive.novelty(of: descriptor, population: peers)
        }
        let fitness = zip(worlds, novelties).map(Self.fitness)
        let ranks = Self.paretoRanks(fitness)
        let crowding = Self.crowdingDistances(fitness: fitness, ranks: ranks)

        let order = worlds.indices.sorted { lhs, rhs in
            if ranks[lhs] != ranks[rhs] { return ranks[lhs] < ranks[rhs] }
            if crowding[lhs] != crowding[rhs] { return crowding[lhs] > crowding[rhs] }
            if fitness[lhs].adaptiveComplexity != fitness[rhs].adaptiveComplexity {
                return fitness[lhs].adaptiveComplexity > fitness[rhs].adaptiveComplexity
            }
            return lhs < rhs
        }

        let eliteLimit = min(eliteCount, worlds.count)
        let elites = Array(order.prefix(eliteLimit))
        var parents = Array(worlds.indices)
        for worldIndex in worlds.indices where !elites.contains(worldIndex) {
            parents[worldIndex] = tournamentParent(from: order)
        }

        for index in order.prefix(min(2, order.count)) {
            archive.consider(
                descriptors[index],
                novelty: novelties[index],
                viable: fitness[index].viability >= 0.2
            )
        }

        let ranked = order.map { index in
            RankedWorld(
                worldIndex: index,
                metrics: worlds[index],
                fitness: fitness[index],
                paretoRank: ranks[index],
                crowdingDistance: crowding[index]
            )
        }
        return EvolutionDecision(
            rankedWorlds: ranked,
            eliteWorlds: elites,
            parentForWorld: parents,
            archiveCount: archive.descriptors.count
        )
    }

    public static func fitness(metrics: WorldMetrics, novelty: Double) -> FitnessVector {
        let occupied = unit(metrics.occupiedFraction)
        let nonCollapse = smoothstep(0.001, 0.012, occupied)
        let nonSaturation = 1 - smoothstep(0.72, 0.95, occupied)
        let sustainedEnergy = smoothstep(0.00005, 0.001, unit(metrics.energyDensity))
        let viability = geometricMean([nonCollapse, nonSaturation, sustainedEnergy])

        let activity = unit(metrics.temporalActivity)
        let dynamic = smoothstep(0.002, 0.035, activity) * (1 - smoothstep(0.72, 0.98, activity))
        // Reductions average a sparse colony over the entire world. Its coherent
        // perimeter therefore occupies roughly the 1e-6...1e-4 range.
        let organized = smoothstep(0.000003, 0.00012, unit(metrics.boundaryCoherence))
        let multiscale = smoothstep(0.001, 0.03, unit(metrics.multiscaleDivergence))
        let inheritedVariation = 0.35 + 0.65 * smoothstep(0.002, 0.18, unit(metrics.geneticDiversity))
        let adaptiveComplexity = geometricMean([dynamic, organized, multiscale, inheritedVariation])

        let lineages = smoothstep(0.08, 0.72, unit(metrics.lineageDiversity))
        let nicheSeparation = smoothstep(0.0004, 0.035, unit(metrics.nicheDifferentiation))
        let trophicBreadth = 0.35 + 0.65 * smoothstep(0.0002, 0.025, unit(metrics.trophicActivity))
        let diversification = geometricMean([lineages, nicheSeparation, trophicBreadth]) * sqrt(viability)

        return FitnessVector(
            viability: unit(viability),
            adaptiveComplexity: unit(adaptiveComplexity),
            recovery: unit(metrics.recovery) * nonCollapse * nonSaturation,
            novelty: unit(novelty) * sqrt(viability),
            diversification: unit(diversification)
        )
    }

    private mutating func tournamentParent(from order: [Int]) -> Int {
        let poolCount = max(1, min(order.count, eliteCount))
        let first = Int(random.next() % UInt64(poolCount))
        let second = Int(random.next() % UInt64(poolCount))
        return order[min(first, second)]
    }

    private static func paretoRanks(_ fitness: [FitnessVector]) -> [Int] {
        var ranks = Array(repeating: 0, count: fitness.count)
        var dominationCounts = Array(repeating: 0, count: fitness.count)
        var dominates = Array(repeating: [Int](), count: fitness.count)
        var front: [Int] = []

        for candidate in fitness.indices {
            for rival in fitness.indices where rival != candidate {
                if fitness[candidate].dominates(fitness[rival]) {
                    dominates[candidate].append(rival)
                } else if fitness[rival].dominates(fitness[candidate]) {
                    dominationCounts[candidate] += 1
                }
            }
            if dominationCounts[candidate] == 0 {
                front.append(candidate)
            }
        }

        var rank = 0
        while !front.isEmpty {
            var next: [Int] = []
            for candidate in front {
                ranks[candidate] = rank
                for dominated in dominates[candidate] {
                    dominationCounts[dominated] -= 1
                    if dominationCounts[dominated] == 0 {
                        next.append(dominated)
                    }
                }
            }
            rank += 1
            front = next
        }
        return ranks
    }

    private static func crowdingDistances(fitness: [FitnessVector], ranks: [Int]) -> [Double] {
        var result = Array(repeating: 0.0, count: fitness.count)
        for rank in Set(ranks) {
            let front = fitness.indices.filter { ranks[$0] == rank }
            guard front.count > 2 else {
                for index in front { result[index] = .infinity }
                continue
            }
            let objectiveCount = fitness.first?.objectives.count ?? 0
            for objective in 0..<objectiveCount {
                let sorted = front.sorted { fitness[$0].objectives[objective] < fitness[$1].objectives[objective] }
                guard let first = sorted.first, let last = sorted.last else { continue }
                result[first] = .infinity
                result[last] = .infinity
                let minimum = fitness[first].objectives[objective]
                let maximum = fitness[last].objectives[objective]
                let span = maximum - minimum
                guard span > 1e-12 else { continue }
                for offset in 1..<(sorted.count - 1) where result[sorted[offset]].isFinite {
                    let before = fitness[sorted[offset - 1]].objectives[objective]
                    let after = fitness[sorted[offset + 1]].objectives[objective]
                    result[sorted[offset]] += (after - before) / span
                }
            }
        }
        return result
    }

    private static func unit(_ value: Double) -> Double {
        min(max(value.isFinite ? value : 0, 0), 1)
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        guard edge1 > edge0 else { return value >= edge1 ? 1 : 0 }
        let t = unit((value - edge0) / (edge1 - edge0))
        return t * t * (3 - 2 * t)
    }

    private static func geometricMean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let product = values.reduce(1.0) { $0 * unit($1) }
        return pow(product, 1 / Double(values.count))
    }
}

public struct SplitMix64: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
