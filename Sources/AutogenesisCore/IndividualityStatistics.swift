import Foundation

public struct SelfPredictiveInformationEstimate: Codable, Sendable, Equatable {
    public let observed: ConfidenceInterval
    public let shuffledNull: ConfidenceInterval
    public let autocorrelationTime: Double
    public let blockLength: Int
    public let lag: Int
    public let state: EvidenceState
}

public enum IndividualityStatistics {
    /// Gaussian conditional mutual information after residualizing past and future
    /// internal state against the simultaneously observed local environment.
    public static func conditionalSelfPredictiveInformation(
        state: [Double],
        environment: [Double],
        lag: Int = 1,
        resamples: Int = 96,
        seed: UInt64 = 0x4e554d49
    ) -> SelfPredictiveInformationEstimate? {
        guard state.count == environment.count,
              state.count >= max(16, lag * 6),
              lag > 0,
              state.allSatisfy(\.isFinite),
              environment.allSatisfy(\.isFinite) else { return nil }

        let x = Array(state.dropLast(lag))
        let y = Array(state.dropFirst(lag))
        let z = Array(environment.dropLast(lag))
        guard let observedValue = gaussianConditionalInformation(x: x, y: y, z: z) else {
            return nil
        }

        let autocorrelationTime = integratedAutocorrelationTime(state)
        let blockLength = min(max(Int(ceil(autocorrelationTime)), lag + 1), max(x.count / 3, 2))
        var generator = SplitMix64(seed: seed)
        let bootstrapValues = movingBlockBootstrap(
            x: x, y: y, z: z, blockLength: blockLength,
            count: max(resamples, 32), generator: &generator
        )
        let nullValues = blockShuffledNull(
            x: x, y: y, z: z, blockLength: blockLength,
            count: max(resamples, 32), generator: &generator
        )
        guard !bootstrapValues.isEmpty, !nullValues.isEmpty else { return nil }
        let effectiveCount = Double(x.count) / max(autocorrelationTime, 1)
        let observed = ConfidenceInterval(
            estimate: observedValue,
            lower: quantile(bootstrapValues, 0.025),
            upper: quantile(bootstrapValues, 0.975),
            effectiveSampleCount: effectiveCount
        )
        let shuffledNull = ConfidenceInterval(
            estimate: nullValues.reduce(0, +) / Double(nullValues.count),
            lower: quantile(nullValues, 0.025),
            upper: quantile(nullValues, 0.975),
            effectiveSampleCount: effectiveCount
        )
        let evidenceState: EvidenceState
        if observed.lower > shuffledNull.upper {
            evidenceState = .supported
        } else if observed.upper <= shuffledNull.upper {
            evidenceState = .notSupported
        } else {
            evidenceState = .inconclusive
        }
        return SelfPredictiveInformationEstimate(
            observed: observed,
            shuffledNull: shuffledNull,
            autocorrelationTime: autocorrelationTime,
            blockLength: blockLength,
            lag: lag,
            state: evidenceState
        )
    }

    public static func integratedAutocorrelationTime(_ values: [Double]) -> Double {
        guard values.count >= 4 else { return 1 }
        let maximumLag = min(values.count / 4, 128)
        var result = 1.0
        for lag in 1...maximumLag {
            guard let correlation = correlation(
                Array(values.dropLast(lag)), Array(values.dropFirst(lag))
            ), correlation > 0 else { break }
            result += 2 * correlation
        }
        return min(max(result, 1), Double(values.count) / 2)
    }

    private static func gaussianConditionalInformation(
        x: [Double], y: [Double], z: [Double]
    ) -> Double? {
        guard x.count == y.count, y.count == z.count, x.count >= 4 else { return nil }
        let residualX = residuals(x, conditionedOn: z)
        let residualY = residuals(y, conditionedOn: z)
        guard let partialCorrelation = correlation(residualX, residualY) else { return nil }
        let bounded = min(abs(partialCorrelation), 0.999_999)
        return -0.5 * log(max(1 - bounded * bounded, 1e-12))
    }

    private static func residuals(_ values: [Double], conditionedOn z: [Double]) -> [Double] {
        let meanValue = values.reduce(0, +) / Double(values.count)
        let meanZ = z.reduce(0, +) / Double(z.count)
        var covariance = 0.0
        var varianceZ = 0.0
        for index in values.indices {
            covariance += (values[index] - meanValue) * (z[index] - meanZ)
            varianceZ += (z[index] - meanZ) * (z[index] - meanZ)
        }
        let slope = varianceZ > 1e-20 ? covariance / varianceZ : 0
        return values.indices.map { values[$0] - meanValue - slope * (z[$0] - meanZ) }
    }

    private static func movingBlockBootstrap(
        x: [Double], y: [Double], z: [Double], blockLength: Int,
        count: Int, generator: inout SplitMix64
    ) -> [Double] {
        var estimates: [Double] = []
        estimates.reserveCapacity(count)
        let maximumStart = max(x.count - blockLength, 0)
        for _ in 0..<count {
            var bx: [Double] = []
            var by: [Double] = []
            var bz: [Double] = []
            while bx.count < x.count {
                let start = Int(generator.next() % UInt64(maximumStart + 1))
                let end = min(start + blockLength, x.count)
                bx.append(contentsOf: x[start..<end])
                by.append(contentsOf: y[start..<end])
                bz.append(contentsOf: z[start..<end])
            }
            if let value = gaussianConditionalInformation(
                x: Array(bx.prefix(x.count)),
                y: Array(by.prefix(y.count)),
                z: Array(bz.prefix(z.count))
            ) { estimates.append(value) }
        }
        return estimates
    }

    private static func blockShuffledNull(
        x: [Double], y: [Double], z: [Double], blockLength: Int,
        count: Int, generator: inout SplitMix64
    ) -> [Double] {
        let blocks = stride(from: 0, to: y.count, by: blockLength).map {
            Array(y[$0..<min($0 + blockLength, y.count)])
        }
        guard blocks.count > 1 else { return [] }
        var estimates: [Double] = []
        estimates.reserveCapacity(count)
        for _ in 0..<count {
            var order = Array(blocks.indices)
            for index in stride(from: order.count - 1, through: 1, by: -1) {
                let selected = Int(generator.next() % UInt64(index + 1))
                order.swapAt(index, selected)
            }
            let shuffled = order.flatMap { blocks[$0] }
            if let value = gaussianConditionalInformation(
                x: x, y: Array(shuffled.prefix(y.count)), z: z
            ) { estimates.append(value) }
        }
        return estimates
    }

    private static func correlation(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count, a.count >= 3 else { return nil }
        let meanA = a.reduce(0, +) / Double(a.count)
        let meanB = b.reduce(0, +) / Double(b.count)
        var covariance = 0.0
        var varianceA = 0.0
        var varianceB = 0.0
        for index in a.indices {
            let da = a[index] - meanA
            let db = b[index] - meanB
            covariance += da * db
            varianceA += da * da
            varianceB += db * db
        }
        let denominator = sqrt(varianceA * varianceB)
        guard denominator > 1e-20 else { return nil }
        return min(max(covariance / denominator, -1), 1)
    }

    private static func quantile(_ values: [Double], _ probability: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let coordinate = min(max(probability, 0), 1) * Double(sorted.count - 1)
        let lower = Int(floor(coordinate))
        let upper = Int(ceil(coordinate))
        guard upper != lower else { return sorted[lower] }
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (coordinate - Double(lower))
    }
}
