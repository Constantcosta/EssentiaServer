import Foundation
import AVFoundation

public struct FrequencyBand: Sendable {
    public let low: Float
    public let high: Float
    public let weight: Float
    
    public init(low: Float, high: Float, weight: Float) {
        self.low = low
        self.high = high
        self.weight = weight
    }
}

public struct DrumProfile: Sendable {
    public let focusBands: [FrequencyBand]
    public let floorDb: Float
    public let holdRange: ClosedRange<Float>
    public let hysteresisRatio: Float
    public let thresholdBias: Float
    public let focusWeight: Float
    public let curve: Float
    public let sidechainHP: Float?
    public let sidechainLP: Float?
    public let emphasisPeaks: [(freq: Float, gainDb: Float, q: Float)]
    public let bleedCuts: [(freq: Float, gainDb: Float, q: Float)]
    
    public init(
        focusBands: [FrequencyBand],
        floorDb: Float,
        holdRange: ClosedRange<Float>,
        hysteresisRatio: Float,
        thresholdBias: Float,
        focusWeight: Float,
        curve: Float,
        sidechainHP: Float?,
        sidechainLP: Float?,
        emphasisPeaks: [(freq: Float, gainDb: Float, q: Float)],
        bleedCuts: [(freq: Float, gainDb: Float, q: Float)]
    ) {
        self.focusBands = focusBands
        self.floorDb = floorDb
        self.holdRange = holdRange
        self.hysteresisRatio = hysteresisRatio
        self.thresholdBias = thresholdBias
        self.focusWeight = focusWeight
        self.curve = curve
        self.sidechainHP = sidechainHP
        self.sidechainLP = sidechainLP
        self.emphasisPeaks = emphasisPeaks
        self.bleedCuts = bleedCuts
    }
}

public enum DrumProfiles {
    public static func profile(for drum: DrumClass?) -> DrumProfile? {
        switch drum {
        case .kick:
            return DrumProfile(
                focusBands: [
                    FrequencyBand(low: 45, high: 110, weight: 1.35),
                    FrequencyBand(low: 1800, high: 5200, weight: 0.55)
                ],
                floorDb: -18,
                holdRange: 0.07...0.14,
                hysteresisRatio: 0.55,
                thresholdBias: -1.5,
                focusWeight: 1.25,
                curve: 1.5,
                sidechainHP: 38,
                sidechainLP: 5200,
                emphasisPeaks: [
                    (freq: 70, gainDb: 4, q: 0.8),
                    (freq: 100, gainDb: 2.5, q: 1.0)
                ],
                bleedCuts: [
                    (freq: 220, gainDb: -6, q: 1.2),
                    (freq: 4500, gainDb: -4, q: 1.0)
                ]
            )
        case .snare:
            return DrumProfile(
                focusBands: [
                    FrequencyBand(low: 160, high: 260, weight: 1.2),
                    FrequencyBand(low: 2200, high: 6500, weight: 0.9)
                ],
                floorDb: -15,
                holdRange: 0.05...0.10,
                hysteresisRatio: 0.6,
                thresholdBias: -0.8,
                focusWeight: 1.2,
                curve: 1.4,
                sidechainHP: 130,
                sidechainLP: 9500,
                emphasisPeaks: [
                    (freq: 200, gainDb: 3.5, q: 1.0),
                    (freq: 4500, gainDb: 2.0, q: 1.2)
                ],
                bleedCuts: [
                    (freq: 70, gainDb: -8, q: 1.0),
                    (freq: 9000, gainDb: -4, q: 1.1)
                ]
            )
        case .toms:
            return DrumProfile(
                focusBands: [
                    FrequencyBand(low: 70, high: 190, weight: 1.15),
                    FrequencyBand(low: 3000, high: 6000, weight: 0.6)
                ],
                floorDb: -17,
                holdRange: 0.07...0.13,
                hysteresisRatio: 0.58,
                thresholdBias: -1.0,
                focusWeight: 1.15,
                curve: 1.45,
                sidechainHP: 65,
                sidechainLP: 7000,
                emphasisPeaks: [
                    (freq: 120, gainDb: 3.0, q: 1.0)
                ],
                bleedCuts: [
                    (freq: 9000, gainDb: -5, q: 1.0)
                ]
            )
        case .hihat:
            return DrumProfile(
                focusBands: [
                    FrequencyBand(low: 5000, high: 10000, weight: 1.4)
                ],
                floorDb: -22,
                holdRange: 0.03...0.07,
                hysteresisRatio: 0.62,
                thresholdBias: -0.5,
                focusWeight: 1.35,
                curve: 1.35,
                sidechainHP: 4200,
                sidechainLP: nil,
                emphasisPeaks: [
                    (freq: 7500, gainDb: 3.0, q: 0.9)
                ],
                bleedCuts: [
                    (freq: 180, gainDb: -10, q: 0.9),
                    (freq: 500, gainDb: -6, q: 1.0)
                ]
            )
        case .tambourine, .claps:
            return DrumProfile(
                focusBands: [
                    FrequencyBand(low: 600, high: 1800, weight: 1.2),
                    FrequencyBand(low: 5000, high: 9000, weight: 1.0)
                ],
                floorDb: -18,
                holdRange: 0.04...0.09,
                hysteresisRatio: 0.6,
                thresholdBias: -0.6,
                focusWeight: 1.25,
                curve: 1.35,
                sidechainHP: 500,
                sidechainLP: 9500,
                emphasisPeaks: [
                    (freq: 1500, gainDb: 2.5, q: 1.0),
                    (freq: 6000, gainDb: 2.0, q: 1.2)
                ],
                bleedCuts: [
                    (freq: 120, gainDb: -8, q: 1.0),
                    (freq: 4000, gainDb: -3.5, q: 1.1)
                ]
            )
        case .custom, .none:
            return DrumProfile(
                focusBands: [FrequencyBand(low: 80, high: 240, weight: 1.1)],
                floorDb: -18,
                holdRange: 0.05...0.12,
                hysteresisRatio: 0.6,
                thresholdBias: -1.0,
                focusWeight: 1.1,
                curve: 1.45,
                sidechainHP: 70,
                sidechainLP: 7500,
                emphasisPeaks: [
                    (freq: 160, gainDb: 2.0, q: 1.0)
                ],
                bleedCuts: []
            )
        }
    }
}

public struct Biquad {
    public var b0: Float
    public var b1: Float
    public var b2: Float
    public var a1: Float
    public var a2: Float
    public var x1: Float = 0
    public var x2: Float = 0
    public var y1: Float = 0
    public var y2: Float = 0
    
    public mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }
    
    public static func bandpass(low: Float, high: Float, sampleRate: Float) -> Biquad? {
        guard sampleRate > 0, high > low, high < sampleRate * 0.48 else { return nil }
        let center = sqrt(low * high)
        let bandwidth = max(high - low, 1)
        let q = max(0.2, min(8, center / bandwidth))
        let omega = 2 * Float.pi * center / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega / (2 * q)
        let a0 = 1 + alpha
        guard a0 != 0 else { return nil }
        
        let b0 = alpha / a0
        let b1: Float = 0
        let b2 = -alpha / a0
        let a1 = -2 * cosOmega / a0
        let a2 = (1 - alpha) / a0
        
        return Biquad(
            b0: b0,
            b1: b1,
            b2: b2,
            a1: a1,
            a2: a2
        )
    }
    
    public static func highpass(cutoff: Float, q: Float = 0.7071, sampleRate: Float) -> Biquad? {
        guard sampleRate > 0 else { return nil }
        let omega = 2 * Float.pi * cutoff / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega / (2 * q)
        let a0 = 1 + alpha
        guard a0 != 0 else { return nil }
        
        let b0 = (1 + cosOmega) / 2 / a0
        let b1 = -(1 + cosOmega) / a0
        let b2 = (1 + cosOmega) / 2 / a0
        let a1 = -2 * cosOmega / a0
        let a2 = (1 - alpha) / a0
        
        return Biquad(
            b0: b0,
            b1: b1,
            b2: b2,
            a1: a1,
            a2: a2
        )
    }
    
    public static func lowpass(cutoff: Float, q: Float = 0.7071, sampleRate: Float) -> Biquad? {
        guard sampleRate > 0 else { return nil }
        let omega = 2 * Float.pi * cutoff / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega / (2 * q)
        let a0 = 1 + alpha
        guard a0 != 0 else { return nil }
        
        let b0 = (1 - cosOmega) / 2 / a0
        let b1 = (1 - cosOmega) / a0
        let b2 = (1 - cosOmega) / 2 / a0
        let a1 = -2 * cosOmega / a0
        let a2 = (1 - alpha) / a0
        
        return Biquad(
            b0: b0,
            b1: b1,
            b2: b2,
            a1: a1,
            a2: a2
        )
    }
    
    public static func peaking(freq: Float, q: Float, gainDb: Float, sampleRate: Float) -> Biquad? {
        guard sampleRate > 0 else { return nil }
        let omega = 2 * Float.pi * freq / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega / (2 * q)
        let a0 = 1 + alpha
        guard a0 != 0 else { return nil }
        
        let a = powf(10, gainDb / 40)
        let b0 = 1 + alpha * a
        let b1 = -2 * cosOmega
        let b2 = 1 - alpha * a
        let a1 = -2 * cosOmega
        let a2 = 1 - alpha / a
        
        return Biquad(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
    }
}

public func buildSidechainEQ(profile: DrumProfile, sampleRate: Float) -> [Biquad] {
    var chain: [Biquad] = []
    if let hp = profile.sidechainHP, let filter = Biquad.highpass(cutoff: hp, q: 0.71, sampleRate: sampleRate) {
        chain.append(filter)
    }
    if let lp = profile.sidechainLP, let filter = Biquad.lowpass(cutoff: lp, q: 0.71, sampleRate: sampleRate) {
        chain.append(filter)
    }
    for peak in profile.emphasisPeaks {
        if let filter = Biquad.peaking(freq: peak.freq, q: peak.q, gainDb: peak.gainDb, sampleRate: sampleRate) {
            chain.append(filter)
        }
    }
    for cut in profile.bleedCuts {
        if let filter = Biquad.peaking(freq: cut.freq, q: cut.q, gainDb: cut.gainDb, sampleRate: sampleRate) {
            chain.append(filter)
        }
    }
    return chain
}

struct BandDetector {
    private struct Filter {
        var biquad: Biquad
        let weight: Float
    }
    
    private var filters: [Filter] = []
    
    init?(bands: [FrequencyBand], sampleRate: Float) {
        for band in bands {
            guard let filter = Biquad.bandpass(low: band.low, high: band.high, sampleRate: sampleRate) else { continue }
            filters.append(Filter(biquad: filter, weight: band.weight))
        }
        if filters.isEmpty {
            return nil
        }
    }
    
    mutating func process(sample: Float) -> Float {
        guard !filters.isEmpty else { return 0 }
        var maxAbs: Float = 0
        for idx in filters.indices {
            let y = filters[idx].biquad.process(sample)
            maxAbs = max(maxAbs, fabsf(y) * filters[idx].weight)
        }
        return maxAbs
    }
}
