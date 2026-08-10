import Foundation

/// A read-only description of change in the living world. None of these values
/// is a reward, rank, or input to the simulation.
public struct OpenEndednessSample: Sendable, Equatable, Codable {
    public var step: UInt64
    public var persistentHeritableNovelty: Double
    public var functionalDiversity: Double
    public var interactionDiversity: Double
    public var programComplexity: Double
    public var ecologicalTurnover: Double
    public var lineageDivergence: Double
    public var individualityShift: Double

    public init(
        step: UInt64,
        persistentHeritableNovelty: Double,
        functionalDiversity: Double,
        interactionDiversity: Double,
        programComplexity: Double,
        ecologicalTurnover: Double,
        lineageDivergence: Double,
        individualityShift: Double
    ) {
        self.step = step
        self.persistentHeritableNovelty = Self.finite(persistentHeritableNovelty)
        self.functionalDiversity = Self.finite(functionalDiversity)
        self.interactionDiversity = Self.finite(interactionDiversity)
        self.programComplexity = Self.finite(programComplexity)
        self.ecologicalTurnover = Self.finite(ecologicalTurnover)
        self.lineageDivergence = Self.finite(lineageDivergence)
        self.individualityShift = Self.finite(individualityShift)
    }

    public static let empty = OpenEndednessSample(
        step: 0,
        persistentHeritableNovelty: 0,
        functionalDiversity: 0,
        interactionDiversity: 0,
        programComplexity: 0,
        ecologicalTurnover: 0,
        lineageDivergence: 0,
        individualityShift: 0
    )

    public var dimensions: [Double] {
        [
            persistentHeritableNovelty,
            functionalDiversity,
            interactionDiversity,
            programComplexity,
            ecologicalTurnover,
            lineageDivergence,
            individualityShift
        ]
    }

    private static func finite(_ value: Double) -> Double {
        value.isFinite ? max(value, 0) : 0
    }
}

public struct OpenEndednessWindow: Sendable, Equatable, Codable {
    public var sampleCount: Int
    public var stepSpan: UInt64
    public var dimensionSlopes: [Double]
    public var activeDimensionCount: Int
    public var plateaued: Bool

    public init(
        sampleCount: Int,
        stepSpan: UInt64,
        dimensionSlopes: [Double],
        activeDimensionCount: Int,
        plateaued: Bool
    ) {
        self.sampleCount = max(sampleCount, 0)
        self.stepSpan = stepSpan
        self.dimensionSlopes = dimensionSlopes.map { $0.isFinite ? $0 : 0 }
        self.activeDimensionCount = max(activeDimensionCount, 0)
        self.plateaued = plateaued
    }

    public static let empty = OpenEndednessWindow(
        sampleCount: 0,
        stepSpan: 0,
        dimensionSlopes: [],
        activeDimensionCount: 0,
        plateaued: false
    )
}

public struct OpenEndednessObservation: Sendable, Equatable, Codable {
    public var current: OpenEndednessSample
    public var shortWindow: OpenEndednessWindow
    public var mediumWindow: OpenEndednessWindow
    public var longWindow: OpenEndednessWindow

    public init(
        current: OpenEndednessSample = .empty,
        shortWindow: OpenEndednessWindow = .empty,
        mediumWindow: OpenEndednessWindow = .empty,
        longWindow: OpenEndednessWindow = .empty
    ) {
        self.current = current
        self.shortWindow = shortWindow
        self.mediumWindow = mediumWindow
        self.longWindow = longWindow
    }

    public static let empty = OpenEndednessObservation()

    /// A warning about an observed plateau, never a termination or selection signal.
    public var sustainedPlateau: Bool {
        shortWindow.plateaued && mediumWindow.plateaued && longWindow.plateaued
    }
}

/// Maintains bounded observation history and tests for saturation at multiple
/// horizons. It deliberately exposes no score, ordering, elite, or parent API.
public struct OpenEndednessObserver: Sendable {
    public var capacity: Int
    public var relativeActivityThreshold: Double
    public private(set) var samples: [OpenEndednessSample]

    public init(
        capacity: Int = 256,
        relativeActivityThreshold: Double = 0.000_01,
        samples: [OpenEndednessSample] = []
    ) {
        self.capacity = max(capacity, 32)
        self.relativeActivityThreshold = max(relativeActivityThreshold, 0)
        self.samples = Array(samples.suffix(max(capacity, 32)))
    }

    public mutating func observe(_ sample: OpenEndednessSample) -> OpenEndednessObservation {
        if let last = samples.last, sample.step <= last.step {
            samples.removeAll { $0.step >= sample.step }
        }
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
        return OpenEndednessObservation(
            current: sample,
            shortWindow: window(suffix: 8),
            mediumWindow: window(suffix: 32),
            longWindow: window(suffix: 128)
        )
    }

    private func window(suffix count: Int) -> OpenEndednessWindow {
        let values = Array(samples.suffix(count))
        guard values.count >= 3, let first = values.first, let last = values.last,
              last.step > first.step else {
            return OpenEndednessWindow(
                sampleCount: values.count,
                stepSpan: values.last?.step ?? 0,
                dimensionSlopes: [],
                activeDimensionCount: 0,
                plateaued: false
            )
        }
        let stepSpan = last.step - first.step
        let scale = Double(stepSpan)
        let dimensionCount = min(first.dimensions.count, last.dimensions.count)
        let slopes = (0..<dimensionCount).map { dimension in
            (last.dimensions[dimension] - first.dimensions[dimension]) / scale
        }
        let active = slopes.count { abs($0) >= relativeActivityThreshold }
        return OpenEndednessWindow(
            sampleCount: values.count,
            stepSpan: stepSpan,
            dimensionSlopes: slopes,
            activeDimensionCount: active,
            plateaued: active == 0
        )
    }
}
