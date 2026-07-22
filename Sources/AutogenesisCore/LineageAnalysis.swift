import Foundation

public struct MorphologyDescriptor: Sendable, Equatable {
    public let values: [Double]

    public init(values: [Double]) {
        self.values = values.map { value in
            guard value.isFinite else { return 0 }
            return min(max(value, 0), 1)
        }
    }

    public func distance(to other: MorphologyDescriptor) -> Double {
        guard values.count == other.values.count, !values.isEmpty else { return 1 }
        let squaredDistance = zip(values, other.values).reduce(0.0) { partial, pair in
            let difference = pair.0 - pair.1
            return partial + difference * difference
        }
        return sqrt(squaredDistance / Double(values.count))
    }
}

public struct LineageBirthRecord: Sendable, Equatable {
    public let birthID: UInt32
    public let parentBirthID: UInt32?
    public let birthStep: UInt64
    public let mutationDistance: Double
    public let genomeHash: UInt32
    public let topologyHash: UInt32

    public init(
        birthID: UInt32,
        parentBirthID: UInt32?,
        birthStep: UInt64,
        mutationDistance: Double,
        genomeHash: UInt32,
        topologyHash: UInt32
    ) {
        self.birthID = birthID
        self.parentBirthID = parentBirthID
        self.birthStep = birthStep
        self.mutationDistance = max(mutationDistance.isFinite ? mutationDistance : 0, 0)
        self.genomeHash = genomeHash
        self.topologyHash = topologyHash
    }
}

public struct LivingLineageSample: Sendable, Equatable {
    public let birthID: UInt32
    public let topologyHash: UInt32
    public let morphology: MorphologyDescriptor

    public init(birthID: UInt32, topologyHash: UInt32, morphology: MorphologyDescriptor) {
        self.birthID = birthID
        self.topologyHash = topologyHash
        self.morphology = morphology
    }
}

public struct LineageAnalysis: Sendable, Equatable {
    public let persistentCladeCount: Int
    public let meanMorphologyDistance: Double
    public let meanGenealogicalDistance: Double
    public let recordedBirthCount: Int
    public let recordedDeathCount: Int

    public static let empty = LineageAnalysis(
        persistentCladeCount: 0,
        meanMorphologyDistance: 0,
        meanGenealogicalDistance: 0,
        recordedBirthCount: 0,
        recordedDeathCount: 0
    )
}

public struct LineageDivergenceTracker: Sendable {
    private let maximumRetainedBirths: Int
    private var births: [UInt32: LineageBirthRecord] = [:]
    private var birthOrder: [UInt32] = []
    private var totalBirthCount = 0
    private var totalDeathCount = 0

    public init(maximumRetainedBirths: Int = 8_192) {
        self.maximumRetainedBirths = max(maximumRetainedBirths, 2)
    }

    public var retainedBirthCount: Int { births.count }

    public mutating func reset() {
        births.removeAll(keepingCapacity: true)
        birthOrder.removeAll(keepingCapacity: true)
        totalBirthCount = 0
        totalDeathCount = 0
    }

    public mutating func registerBirth(_ record: LineageBirthRecord) {
        if births[record.birthID] == nil {
            birthOrder.append(record.birthID)
            totalBirthCount += 1
        }
        births[record.birthID] = record
    }

    public mutating func registerDeath(birthID _: UInt32, step _: UInt64) {
        totalDeathCount += 1
    }

    public func genealogicalDistance(from lhs: UInt32, to rhs: UInt32) -> Double {
        guard lhs != rhs else { return 0 }
        guard births[lhs] != nil, births[rhs] != nil else { return 1 }

        var lhsDistances: [UInt32: Double] = [:]
        var cursor: UInt32? = lhs
        var distance = 0.0
        var visited: Set<UInt32> = []
        while let current = cursor, visited.insert(current).inserted, let record = births[current] {
            lhsDistances[current] = distance
            distance += record.mutationDistance
            cursor = record.parentBirthID
        }

        cursor = rhs
        distance = 0
        visited.removeAll(keepingCapacity: true)
        while let current = cursor, visited.insert(current).inserted, let record = births[current] {
            if let lhsDistance = lhsDistances[current] {
                return lhsDistance + distance
            }
            distance += record.mutationDistance
            cursor = record.parentBirthID
        }
        return 1 + distance
    }

    public mutating func analyze(
        living: [LivingLineageSample],
        currentStep: UInt64,
        minimumPersistenceSteps: UInt64 = 1_200,
        divergenceThreshold: Double = 0.30
    ) -> LineageAnalysis {
        pruneHistory(retaining: Set(living.map(\.birthID)))
        guard !living.isEmpty else {
            return LineageAnalysis(
                persistentCladeCount: 0,
                meanMorphologyDistance: 0,
                meanGenealogicalDistance: 0,
                recordedBirthCount: totalBirthCount,
                recordedDeathCount: totalDeathCount
            )
        }

        var morphologyDistanceTotal = 0.0
        var genealogicalDistanceTotal = 0.0
        var pairCount = 0
        for left in living.indices {
            for right in living.indices where right > left {
                morphologyDistanceTotal += living[left].morphology.distance(to: living[right].morphology)
                genealogicalDistanceTotal += genealogicalDistance(
                    from: living[left].birthID,
                    to: living[right].birthID
                )
                pairCount += 1
            }
        }

        var representatives: [LivingLineageSample] = []
        var persistentRepresentative = Set<UInt32>()
        for sample in living.sorted(by: { $0.birthID < $1.birthID }) {
            let matchingIndex = representatives.firstIndex { representative in
                combinedDistance(sample, representative) < divergenceThreshold
            }
            let representative: LivingLineageSample
            if let matchingIndex {
                representative = representatives[matchingIndex]
            } else {
                representatives.append(sample)
                representative = sample
            }
            if let birth = births[sample.birthID],
               currentStep >= birth.birthStep + minimumPersistenceSteps {
                persistentRepresentative.insert(representative.birthID)
            }
        }

        return LineageAnalysis(
            persistentCladeCount: persistentRepresentative.count,
            meanMorphologyDistance: pairCount > 0 ? morphologyDistanceTotal / Double(pairCount) : 0,
            meanGenealogicalDistance: pairCount > 0 ? genealogicalDistanceTotal / Double(pairCount) : 0,
            recordedBirthCount: totalBirthCount,
            recordedDeathCount: totalDeathCount
        )
    }

    private mutating func pruneHistory(retaining livingIDs: Set<UInt32>) {
        guard births.count > maximumRetainedBirths else { return }

        var retained = livingIDs
        var frontier = Array(livingIDs)
        while let birthID = frontier.popLast(),
              retained.count < maximumRetainedBirths,
              let parentID = births[birthID]?.parentBirthID,
              retained.insert(parentID).inserted {
            frontier.append(parentID)
        }
        for birthID in birthOrder.reversed()
        where retained.count < maximumRetainedBirths {
            if births[birthID] != nil {
                retained.insert(birthID)
            }
        }

        births = births.filter { retained.contains($0.key) }
        birthOrder = birthOrder.filter { retained.contains($0) }
    }

    private func combinedDistance(
        _ lhs: LivingLineageSample,
        _ rhs: LivingLineageSample
    ) -> Double {
        let morphology = lhs.morphology.distance(to: rhs.morphology)
        let genealogy = 1 - exp(-genealogicalDistance(from: lhs.birthID, to: rhs.birthID) / 0.28)
        let topology = lhs.topologyHash == rhs.topologyHash ? 0.0 : 1.0
        return morphology * 0.45 + genealogy * 0.45 + topology * 0.10
    }
}
