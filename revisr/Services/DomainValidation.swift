import Foundation

enum DomainValidation {
    static let percentageTolerance = 0.000_001

    static func isValidPercentage(_ value: Double) -> Bool {
        value.isFinite && (0...1).contains(value)
    }

    static func isValidPercentageGroup(_ values: [Double]) -> Bool {
        !values.isEmpty
            && values.allSatisfy(isValidPercentage)
            && abs(values.reduce(0, +) - 1) <= percentageTolerance
    }

    static func isValidDuration(_ duration: TimeInterval) -> Bool {
        duration.isFinite && duration > 0
    }

    static func isValidResult(rawScore: Double, maximumScore: Double) -> Bool {
        rawScore.isFinite
            && maximumScore.isFinite
            && rawScore >= 0
            && maximumScore > 0
            && rawScore <= maximumScore
    }

    /// Broad data-quality guard only; this is not an official TMUA conversion range.
    static func isSensibleScaledScore(_ value: Double) -> Bool {
        value.isFinite && (0...20).contains(value)
    }
}
