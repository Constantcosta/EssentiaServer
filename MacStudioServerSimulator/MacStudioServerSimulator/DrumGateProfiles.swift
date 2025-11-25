//
//  DrumGateProfiles.swift
//  MacStudioServerSimulator
//
//  Drum gate profiles, filters, and processors used across preview/export.
//

import Foundation
import AVFoundation

struct FrequencyBand {
    let low: Float
    let high: Float
    let weight: Float
}

struct DrumProfile {
    let focusBands: [FrequencyBand]
    let floorDb: Float
    let holdRange: ClosedRange<Float>
    let hysteresisRatio: Float
    let thresholdBias: Float
    let focusWeight: Float
    let curve: Float
    let sidechainHP: Float?
    let sidechainLP: Float?
    let emphasisPeaks: [(freq: Float, gainDb: Float, q: Float)]
    let bleedCuts: [(freq: Float, gainDb: Float, q: Float)]
}

enum DrumProfiles {
    static func profile(for drum: DrumClass?) -> DrumProfile? {
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

struct Biquad {
    var b0: Float
    var b1: Float
    var b2: Float
    var a1: Float
    var a2: Float
    var x1: Float = 0
    var x2: Float = 0
    var y1: Float = 0
    var y2: Float = 0
    
    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }
    
    static func bandpass(low: Float, high: Float, sampleRate: Float) -> Biquad? {
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
        
        return Biquad(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }
    
    static func highpass(cutoff: Float, q: Float, sampleRate: Float) -> Biquad? {
        guard cutoff > 0, sampleRate > 0 else { return nil }
        let omega = 2 * Float.pi * cutoff / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega / (2 * max(0.1, q))
        let a0 = 1 + alpha
        guard a0 != 0 else { return nil }
        
        let b0 = (1 + cosOmega) / 2 / a0
        let b1 = -(1 + cosOmega) / a0
        let b2 = (1 + cosOmega) / 2 / a0
        let a1 = -2 * cosOmega / a0
        let a2 = (1 - alpha) / a0
        
        return Biquad(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }
    
    static func lowpass(cutoff: Float, q: Float, sampleRate: Float) -> Biquad? {
        guard cutoff > 0, sampleRate > 0 else { return nil }
        let omega = 2 * Float.pi * cutoff / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega / (2 * max(0.1, q))
        let a0 = 1 + alpha
        guard a0 != 0 else { return nil }
        
        let b0 = (1 - cosOmega) / 2 / a0
        let b1 = (1 - cosOmega) / a0
        let b2 = (1 - cosOmega) / 2 / a0
        let a1 = -2 * cosOmega / a0
        let a2 = (1 - alpha) / a0
        
        return Biquad(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }
    
    static func peaking(freq: Float, q: Float, gainDb: Float, sampleRate: Float) -> Biquad? {
        guard freq > 0, sampleRate > 0 else { return nil }
        let a = powf(10, gainDb / 40)
        let omega = 2 * Float.pi * freq / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega / (2 * max(0.1, q))
        
        let b0 = 1 + alpha * a
        let b1 = -2 * cosOmega
        let b2 = 1 - alpha * a
        let a0 = 1 + alpha / a
        let a1 = -2 * cosOmega
        let a2 = 1 - alpha / a
        guard a0 != 0 else { return nil }
        
        return Biquad(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
    }
}

func buildSidechainEQ(profile: DrumProfile, sampleRate: Float) -> [Biquad] {
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

struct GateProcessor {
    private struct Config {
        let thresholdLinear: Float
        let closeRatio: Float
        let attackCoeff: Float
        let releaseCoeff: Float
        let holdSamples: Int
        let floorGain: Float
        let curve: Float
        let focusWeight: Float
        let sampleMax: Float
        let transientFactor: Float
        let minPassLinear: Float
    }
    
    private var config: Config?
    private var envelope: Float = 0
    private var holdCounter: Int = 0
    private var bandDetector: BandDetector?
    private var sidechainEQ: [Biquad] = []
    
    init() {}
    
    init?(gate: GateSettings, sampleRate: Float, profile: DrumProfile?) {
        guard reconfigure(gate: gate, sampleRate: sampleRate, profile: profile) else { return nil }
    }
    
    @discardableResult
    mutating func reconfigure(gate: GateSettings, sampleRate: Float, profile: DrumProfile?) -> Bool {
        guard gate.active else {
            config = nil
            bandDetector = nil
            sidechainEQ = []
            envelope = 0
            holdCounter = 0
            return false
        }
        let thresholdDb = gate.threshold
        let thresholdLinear = powf(10.0, thresholdDb / 20.0)
        let closeRatio = max(0.25, min(profile?.hysteresisRatio ?? 0.6, 0.95))
        let profileFloorDb = profile?.floorDb ?? -18
        // Tighten floor as user raises threshold; at max threshold, allow deep cut but not full mute.
        let tightness = min(1.0, max(0.0, (thresholdDb + 24.0) / 24.0)) // 0 at -24 dB, 1 at 0 dB+
        let adaptiveFloorDb = profileFloorDb * (1 - tightness) + (-60.0 * tightness)
        let requestedFloorDb = gate.floorDb.map { min($0, -6) } ?? adaptiveFloorDb // clamp user input to -6 dB max
        let floorDb = min(adaptiveFloorDb, requestedFloorDb)
        let floorGain = powf(10.0, max(floorDb, -90.0) / 20.0)
        let minPassLinear = powf(10.0, max(requestedFloorDb, -120.0) / 20.0) // anything quieter than this is zeroed even when open
        let curve = max(1.1, min(profile?.curve ?? 1.45, 3.0))
        let focusWeight = max(1, profile?.focusWeight ?? 1)
        let baseHold = max(0.025, gate.release * 0.85)
        let holdSeconds: Float = {
            guard let range = profile?.holdRange else { return baseHold }
            return min(max(baseHold, range.lowerBound), range.upperBound)
        }()
        let holdSamples = max(1, Int(sampleRate * holdSeconds))
        let attackCoeff = gate.attack > 0 ? expf(-1.0 / (sampleRate * max(gate.attack, 0.0004))) : 0
        let releaseCoeff = gate.release > 0 ? expf(-6.90775527898 / (sampleRate * max(gate.release, 0.001))) : 0
        
        config = Config(
            thresholdLinear: max(thresholdLinear, 0.00005),
            closeRatio: closeRatio,
            attackCoeff: attackCoeff,
            releaseCoeff: releaseCoeff,
            holdSamples: holdSamples,
            floorGain: max(floorGain, 0),
            curve: curve,
            focusWeight: focusWeight,
            sampleMax: 32_767.0,
            transientFactor: 1.3,
            minPassLinear: minPassLinear
        )
        if let profile, let detector = BandDetector(bands: profile.focusBands, sampleRate: sampleRate) {
            bandDetector = detector
        } else {
            bandDetector = nil
        }
        if let profile {
            sidechainEQ = buildSidechainEQ(profile: profile, sampleRate: sampleRate)
        } else {
            sidechainEQ = []
        }
        envelope = 0
        holdCounter = 0
        return true
    }
    
    mutating func process(buffer: AVAudioPCMBuffer) {
        guard let config else { return }
        switch buffer.format.commonFormat {
        case .pcmFormatInt16:
            guard let channelData = buffer.int16ChannelData else { return }
            let channels = Int(buffer.format.channelCount)
            let frames = Int(buffer.frameLength)
            processInt16(channelData: channelData, channels: channels, frames: frames, sampleMax: config.sampleMax, config: config)
        case .pcmFormatFloat32:
            guard let channelData = buffer.floatChannelData else { return }
            let channels = Int(buffer.format.channelCount)
            let frames = Int(buffer.frameLength)
            var pointers: [UnsafeMutablePointer<Float>] = []
            pointers.reserveCapacity(channels)
            for channel in 0..<channels {
                pointers.append(channelData[channel])
            }
            processFloat(channelData: pointers, channels: channels, frames: frames, config: config)
        default:
            return
        }
    }
    
    mutating func process(bufferList: UnsafeMutableAudioBufferListPointer, frameCount: Int) {
        guard let config else { return }
        var channelPointers: [UnsafeMutablePointer<Float>] = []
        channelPointers.reserveCapacity(bufferList.count)
        for bufferIndex in 0..<bufferList.count {
            let buffer = bufferList[bufferIndex]
            guard let data = buffer.mData else { continue }
            let ptr = data.assumingMemoryBound(to: Float.self)
            channelPointers.append(ptr)
        }
        processFloat(channelData: channelPointers, channels: channelPointers.count, frames: frameCount, config: config)
    }
    
    private mutating func processFloat(
        channelData: [UnsafeMutablePointer<Float>],
        channels: Int,
        frames: Int,
        config: Config
    ) {
        guard !channelData.isEmpty else { return }
        let channelCount = max(min(channels, channelData.count), 1)
        let sampleMax: Float = 1.0
        
        for frame in 0..<frames {
            var mono: Float = 0
            var rawPeakNorm: Float = 0
            
            for channel in 0..<channelCount {
                let sample = channelData[channel][frame]
                mono += sample
                rawPeakNorm = max(rawPeakNorm, fabsf(sample))
            }
            
            mono /= Float(channelCount)
            var normalizedMono = mono
            for idx in sidechainEQ.indices {
                normalizedMono = sidechainEQ[idx].process(normalizedMono)
            }
            let broadband = abs(normalizedMono)
            let focus = (bandDetector?.process(sample: normalizedMono) ?? 0) * config.focusWeight
            let detected = max(broadband, focus)
            
            if detected > envelope {
                envelope = config.attackCoeff * (envelope - detected) + detected
            } else {
                envelope = config.releaseCoeff * (envelope - detected) + detected
            }
            
            let ratio = envelope / config.thresholdLinear
            let transientHit = rawPeakNorm >= config.thresholdLinear * config.transientFactor
            if ratio >= 1 {
                holdCounter = config.holdSamples
            }
            if transientHit {
                holdCounter = max(holdCounter, config.holdSamples)
                envelope = max(envelope, rawPeakNorm)
            }
            
            let gain: Float
            if transientHit {
                gain = 1
            } else if holdCounter > 0 {
                gain = 1
                holdCounter -= 1
            } else if ratio >= config.closeRatio {
                let t = (ratio - config.closeRatio) / max(0.0001, 1 - config.closeRatio)
                let shaped = powf(min(1, max(0, t)), config.curve)
                gain = max(config.floorGain, shaped)
            } else {
                gain = config.floorGain
            }
            
            for channel in 0..<channelCount {
                var processed = channelData[channel][frame] * gain
                let normalized = fabsf(processed) / sampleMax
                if normalized < config.minPassLinear {
                    // Gently fade low-level bleed instead of hard muting per-sample to avoid distortion.
                    let factor = normalized / max(config.minPassLinear, 0.000_001)
                    processed *= factor
                }
                channelData[channel][frame] = processed
            }
        }
    }
    
    private mutating func processInt16(
        channelData: UnsafePointer<UnsafeMutablePointer<Int16>>,
        channels: Int,
        frames: Int,
        sampleMax: Float,
        config: Config
    ) {
        let channelCount = max(channels, 1)
        
        for frame in 0..<frames {
            var mono: Float = 0
            var peak: Float = 0
            
            for channel in 0..<channelCount {
                let sample = Float(channelData[channel][frame])
                mono += sample
                peak = max(peak, fabsf(sample))
            }
            
            mono /= Float(channelCount)
            var normalizedMono = mono / sampleMax
            for idx in sidechainEQ.indices {
                normalizedMono = sidechainEQ[idx].process(normalizedMono)
            }
            let broadband = abs(normalizedMono)
            let rawPeakNorm = peak / sampleMax
            let focus = (bandDetector?.process(sample: normalizedMono) ?? 0) * config.focusWeight
            let detected = max(broadband, focus)
            
            if detected > envelope {
                envelope = config.attackCoeff * (envelope - detected) + detected
            } else {
                envelope = config.releaseCoeff * (envelope - detected) + detected
            }
            
            let ratio = envelope / config.thresholdLinear
            let transientHit = rawPeakNorm >= config.thresholdLinear * config.transientFactor
            if ratio >= 1 {
                holdCounter = config.holdSamples
            }
            if transientHit {
                holdCounter = max(holdCounter, config.holdSamples)
                envelope = max(envelope, rawPeakNorm)
            }
            
            let gain: Float
            if transientHit {
                gain = 1
            } else if holdCounter > 0 {
                gain = 1
                holdCounter -= 1
            } else if ratio >= config.closeRatio {
                let t = (ratio - config.closeRatio) / max(0.0001, 1 - config.closeRatio)
                let shaped = powf(min(1, max(0, t)), config.curve)
                gain = max(config.floorGain, shaped)
            } else {
                gain = config.floorGain
            }
            
            for channel in 0..<channelCount {
                var processed = Float(channelData[channel][frame]) * gain
                let normalized = fabsf(processed) / sampleMax
                if normalized < config.minPassLinear {
                    // Gently fade low-level bleed instead of hard muting per-sample to avoid distortion.
                    let factor = normalized / max(config.minPassLinear, 0.000_001)
                    processed *= factor
                }
                channelData[channel][frame] = Int16(max(-32_768, min(32_767, processed)))
            }
        }
    }
}
