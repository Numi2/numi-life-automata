import Foundation

public struct LaggedAssociationEstimate: Sendable, Equatable, Codable {
    public let correlation: Double
    public let confidenceLower: Double?
    public let confidenceUpper: Double?
    public let nominalSampleCount: Int
    public let effectiveSampleCount: Double
    public let lag: Int
    public let usesFirstDifferences: Bool

    public init(
        correlation: Double,
        confidenceLower: Double?,
        confidenceUpper: Double?,
        nominalSampleCount: Int,
        effectiveSampleCount: Double,
        lag: Int,
        usesFirstDifferences: Bool
    ) {
        self.correlation = correlation
        self.confidenceLower = confidenceLower
        self.confidenceUpper = confidenceUpper
        self.nominalSampleCount = nominalSampleCount
        self.effectiveSampleCount = effectiveSampleCount
        self.lag = lag
        self.usesFirstDifferences = usesFirstDifferences
    }
}

public struct PairedEffectEstimate: Sendable, Equatable, Codable {
    public let controlMean: Double
    public let treatmentMean: Double
    public let meanDifference: Double
    public let differenceStandardDeviation: Double
    public let standardError: Double
    public let confidenceLower: Double
    public let confidenceUpper: Double
    public let pairCount: Int

    public init(
        controlMean: Double,
        treatmentMean: Double,
        meanDifference: Double,
        differenceStandardDeviation: Double,
        standardError: Double,
        confidenceLower: Double,
        confidenceUpper: Double,
        pairCount: Int
    ) {
        self.controlMean = controlMean
        self.treatmentMean = treatmentMean
        self.meanDifference = meanDifference
        self.differenceStandardDeviation = differenceStandardDeviation
        self.standardError = standardError
        self.confidenceLower = confidenceLower
        self.confidenceUpper = confidenceUpper
        self.pairCount = pairCount
    }
}

public enum CausalAnalysis {
    public static func laggedDifferenceAssociation(
        cause: [Double],
        effect: [Double],
        lag: Int = 1,
        minimumPairs: Int = 8
    ) -> LaggedAssociationEstimate? {
        guard cause.count == effect.count,
              lag > 0,
              cause.count > lag + 1,
              cause.allSatisfy(\.isFinite),
              effect.allSatisfy(\.isFinite) else { return nil }

        let causeDifferences = differences(cause)
        let effectDifferences = differences(effect)
        let pairCount = causeDifferences.count - lag
        guard pairCount >= minimumPairs else { return nil }
        let pairedCause = Array(causeDifferences.prefix(pairCount))
        let pairedEffect = Array(effectDifferences.dropFirst(lag).prefix(pairCount))
        guard let correlation = pearson(pairedCause, pairedEffect) else { return nil }

        let causeAutocorrelation = lagOneAutocorrelation(pairedCause) ?? 0
        let effectAutocorrelation = lagOneAutocorrelation(pairedEffect) ?? 0
        let autocorrelationProduct = min(
            max(causeAutocorrelation * effectAutocorrelation, -0.999),
            0.999
        )
        let adjustedCount = Double(pairCount) *
            (1 - autocorrelationProduct) / (1 + autocorrelationProduct)
        let effectiveCount = min(max(adjustedCount, 1), Double(pairCount))

        var confidenceLower: Double?
        var confidenceUpper: Double?
        if effectiveCount > 3 {
            let boundedCorrelation = min(max(correlation, -0.999_999), 0.999_999)
            let fisherZ = atanh(boundedCorrelation)
            let halfWidth = 1.959_963_984_540_054 / sqrt(effectiveCount - 3)
            confidenceLower = tanh(fisherZ - halfWidth)
            confidenceUpper = tanh(fisherZ + halfWidth)
        }
        return LaggedAssociationEstimate(
            correlation: correlation,
            confidenceLower: confidenceLower,
            confidenceUpper: confidenceUpper,
            nominalSampleCount: pairCount,
            effectiveSampleCount: effectiveCount,
            lag: lag,
            usesFirstDifferences: true
        )
    }

    public static func pairedEffect(
        control: [Double],
        treatment: [Double]
    ) -> PairedEffectEstimate? {
        guard control.count == treatment.count else { return nil }
        let pairs = zip(control, treatment).filter { pair in
            pair.0.isFinite && pair.1.isFinite
        }
        guard pairs.count >= 2 else { return nil }
        let controlValues = pairs.map { $0.0 }
        let treatmentValues = pairs.map { $0.1 }
        let differences = zip(controlValues, treatmentValues).map { $1 - $0 }
        let count = Double(differences.count)
        let controlMean = controlValues.reduce(0, +) / count
        let treatmentMean = treatmentValues.reduce(0, +) / count
        let meanDifference = differences.reduce(0, +) / count
        let sumSquaredDeviation = differences.reduce(0) { partial, value in
            partial + (value - meanDifference) * (value - meanDifference)
        }
        let standardDeviation = sqrt(sumSquaredDeviation / (count - 1))
        let standardError = standardDeviation / sqrt(count)
        let criticalValue = twoSided95TCritical(degreesOfFreedom: differences.count - 1)
        let halfWidth = criticalValue * standardError
        return PairedEffectEstimate(
            controlMean: controlMean,
            treatmentMean: treatmentMean,
            meanDifference: meanDifference,
            differenceStandardDeviation: standardDeviation,
            standardError: standardError,
            confidenceLower: meanDifference - halfWidth,
            confidenceUpper: meanDifference + halfWidth,
            pairCount: differences.count
        )
    }

    private static func differences(_ values: [Double]) -> [Double] {
        zip(values.dropFirst(), values).map { $0 - $1 }
    }

    private static func lagOneAutocorrelation(_ values: [Double]) -> Double? {
        guard values.count >= 3 else { return nil }
        return pearson(Array(values.dropLast()), Array(values.dropFirst()))
    }

    private static func pearson(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 2 else { return nil }
        let count = Double(x.count)
        let meanX = x.reduce(0, +) / count
        let meanY = y.reduce(0, +) / count
        var covariance = 0.0
        var varianceX = 0.0
        var varianceY = 0.0
        for index in x.indices {
            let dx = x[index] - meanX
            let dy = y[index] - meanY
            covariance += dx * dy
            varianceX += dx * dx
            varianceY += dy * dy
        }
        let denominator = sqrt(varianceX * varianceY)
        guard denominator > 1e-20 else { return nil }
        return min(max(covariance / denominator, -1), 1)
    }

    private static func twoSided95TCritical(degreesOfFreedom: Int) -> Double {
        let values = [
            12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306,
            2.262, 2.228, 2.201, 2.179, 2.160, 2.145, 2.131, 2.120,
            2.110, 2.101, 2.093, 2.086, 2.080, 2.074, 2.069, 2.064,
            2.060, 2.056, 2.052, 2.048, 2.045, 2.042
        ]
        guard degreesOfFreedom > 0 else { return .infinity }
        return degreesOfFreedom <= values.count
            ? values[degreesOfFreedom - 1]
            : 1.959_963_984_540_054
    }
}
