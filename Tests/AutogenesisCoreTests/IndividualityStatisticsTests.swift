import Foundation
import Testing
@testable import AutogenesisCore

struct IndividualityStatisticsTests {
    @Test
    func detectsEndogenousStateMemoryBeyondEnvironmentalDrive() throws {
        var state = [Double](repeating: 0, count: 256)
        let environment = (0..<256).map { sin(Double($0) * 0.31) }
        for index in 1..<state.count {
            state[index] = 0.94 * state[index - 1] +
                0.04 * environment[index] + sin(Double(index) * 1.73) * 0.01
        }
        let estimate = try #require(
            IndividualityStatistics.conditionalSelfPredictiveInformation(
                state: state, environment: environment, resamples: 48, seed: 4
            )
        )
        #expect(estimate.observed.estimate > estimate.shuffledNull.estimate)
        #expect(estimate.autocorrelationTime >= 1)
        #expect(estimate.blockLength >= 2)
    }

    @Test
    func rejectsMismatchedSeries() {
        #expect(IndividualityStatistics.conditionalSelfPredictiveInformation(
            state: [0, 1, 2], environment: [0, 1]
        ) == nil)
    }
}
