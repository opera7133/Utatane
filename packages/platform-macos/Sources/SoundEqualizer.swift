import Foundation

struct SoundEqualizerSettings: Sendable, Equatable {
    var gains: [Double] = []
    var preamp: Double = 0

    mutating func apply(_ option: String) {
        let parts = option.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return }
        switch parts[0].lowercased() {
        case "--eq":
            if parts[1].isEmpty {
                gains = []; return
            }
            let values = parts[1].split(separator: ":", maxSplits: 31, omittingEmptySubsequences: false).map { Double($0) }
            guard [5, 10, 15, 31].contains(values.count), values.allSatisfy({ $0?.isFinite == true }) else { return }
            gains = values.map { min(24, max(-24, $0!)) }
        case "--eq-preamp":
            guard let value = Double(parts[1]), value.isFinite else { return }
            preamp = min(24, max(-24, value))
        default: break
        }
    }

    static func frequencies(_ count: Int) -> [Double] {
        switch count {
        case 5: [63, 250, 1000, 4000, 16000]
        case 10: [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        case 15: [25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000]
        case 31: [20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630,
                  800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000]
        default: []
        }
    }

    /// Cascaded peaking filters, with overlap compensated at each ISO centre.
    /// Filters too close to Nyquist (above 90% of it) are omitted.
    func coefficients(sampleRate: Double) -> [SoundEQBiquad] {
        let centres = Self.frequencies(gains.count)
        let active = centres.indices.filter { centres[$0] < sampleRate * 0.45 }
        guard !active.isEmpty, gains.contains(where: { $0 != 0 }) else { return Array(repeating: .identity, count: 31) }
        let bandwidth = [5: 2.0, 10: 1.0, 15: 2.0 / 3, 31: 1.0 / 3][gains.count]!
        let targets = active.map { gains[$0] }
        var adjusted = targets
        // Newton solve the actual cascade response, rather than assuming that
        // independent band gains add without affecting adjacent centres.
        for _ in 0 ..< 10 {
            let filters = active.enumerated().map { SoundEQBiquad.peak(frequency: centres[$0.element], gain: adjusted[$0.offset], bandwidth: bandwidth, sampleRate: sampleRate) }
            let response = active.map { index in filters.reduce(0) { $0 + $1.decibels(at: centres[index], sampleRate: sampleRate) } }
            let error = zip(targets, response).map(-)
            if error.allSatisfy({ abs($0) < 0.0001 }) {
                break
            }
            var matrix = Array(repeating: Array(repeating: 0.0, count: active.count + 1), count: active.count)
            for row in active.indices {
                for column in active.indices {
                    let perturbed = SoundEQBiquad.peak(frequency: centres[active[column]], gain: adjusted[column] + 0.01, bandwidth: bandwidth, sampleRate: sampleRate)
                    matrix[row][column] = (perturbed.decibels(at: centres[active[row]], sampleRate: sampleRate) - filters[column].decibels(at: centres[active[row]], sampleRate: sampleRate)) / 0.01
                }
                matrix[row][active.count] = error[row]
            }
            guard let delta = Self.solve(matrix) else { break }
            for index in adjusted.indices {
                adjusted[index] = min(72, max(-72, adjusted[index] + delta[index]))
            }
        }
        var result = Array(repeating: SoundEQBiquad.identity, count: 31)
        for (index, band) in active.enumerated() {
            result[band] = .peak(frequency: centres[band], gain: adjusted[index], bandwidth: bandwidth, sampleRate: sampleRate)
        }
        return result
    }

    private static func solve(_ input: [[Double]]) -> [Double]? {
        var matrix = input
        let n = matrix.count
        for column in 0 ..< n {
            let pivot = (column ..< n).max { abs(matrix[$0][column]) < abs(matrix[$1][column]) }!
            guard abs(matrix[pivot][column]) > 1e-10 else { return nil }
            matrix.swapAt(column, pivot)
            let scale = matrix[column][column]
            for index in column ... n {
                matrix[column][index] /= scale
            }
            for row in 0 ..< n where row != column {
                let scale = matrix[row][column]
                for index in column ... n {
                    matrix[row][index] -= scale * matrix[column][index]
                }
            }
        }
        return matrix.map { $0[n] }
    }
}

struct SoundEQBiquad: Sendable, Equatable {
    var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    static let identity = Self(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    static func peak(frequency: Double, gain: Double, bandwidth: Double, sampleRate: Double) -> Self {
        guard abs(gain) > 1e-10 else { return .identity }
        let omega = 2 * Double.pi * frequency / sampleRate
        let sine = sin(omega), cosine = cos(omega), a = pow(10, gain / 40)
        let alpha = sine * sinh(log(2) / 2 * bandwidth * omega / sine)
        let denominator = 1 + alpha / a
        return Self(b0: (1 + alpha * a) / denominator, b1: -2 * cosine / denominator,
                    b2: (1 - alpha * a) / denominator, a1: -2 * cosine / denominator,
                    a2: (1 - alpha / a) / denominator)
    }

    func decibels(at frequency: Double, sampleRate: Double) -> Double {
        let omega = 2 * Double.pi * frequency / sampleRate
        let realNumerator = b0 + b1 * cos(omega) + b2 * cos(2 * omega)
        let imaginaryNumerator = -b1 * sin(omega) - b2 * sin(2 * omega)
        let realDenominator = 1 + a1 * cos(omega) + a2 * cos(2 * omega)
        let imaginaryDenominator = -a1 * sin(omega) - a2 * sin(2 * omega)
        return 10 * log10((realNumerator * realNumerator + imaginaryNumerator * imaginaryNumerator) /
            (realDenominator * realDenominator + imaginaryDenominator * imaginaryDenominator))
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(b0: lhs.b0 + rhs.b0, b1: lhs.b1 + rhs.b1, b2: lhs.b2 + rhs.b2, a1: lhs.a1 + rhs.a1, a2: lhs.a2 + rhs.a2)
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(b0: lhs.b0 - rhs.b0, b1: lhs.b1 - rhs.b1, b2: lhs.b2 - rhs.b2, a1: lhs.a1 - rhs.a1, a2: lhs.a2 - rhs.a2)
    }

    static func / (lhs: Self, rhs: Double) -> Self {
        Self(b0: lhs.b0 / rhs, b1: lhs.b1 / rhs, b2: lhs.b2 / rhs, a1: lhs.a1 / rhs, a2: lhs.a2 / rhs)
    }
}
