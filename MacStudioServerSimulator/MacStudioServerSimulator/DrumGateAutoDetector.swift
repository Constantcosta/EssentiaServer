//
//  DrumGateAutoDetector.swift
//  MacStudioServerSimulator
//
//  Automatic gate suggestion based on waveform statistics and spectral cues.
//

import Foundation
import AVFoundation

enum GateAutoDetector {
    struct Suggestion {
        let threshold: Float
        let release: TimeInterval?
        let floorDb: Float?
    }
    
    struct SpectralSnapshot {
        let focusRMS: Float
        let focusPeak: Float
        let offbandRMS: Float
        let broadbandRMS: Float
        let broadbandPeak: Float
        
        var focusToOffDb: Float {
            let eps: Float = 0.000001
            return 20 * log10f(max(focusRMS, eps) / max(offbandRMS, eps))
        }
        
        var crestDb: Float {
            let eps: Float = 0.000001
            return 20 * log10f(max(focusPeak, eps) / max(focusRMS, eps))
        }
    }
    
    private struct BandAccumulator {
        var filter: Biquad
        let weight: Float
        var sum: Double = 0
        var peak: Float = 0
        
        mutating func consume(_ sample: Float) -> Float {
            let y = filter.process(sample)
            let mag = fabsf(y) * weight
            sum += Double(mag * mag)
            peak = max(peak, mag)
            return mag
        }
        
        func rms(count: Int) -> Float {
            guard count > 0 else { return 0 }
            return sqrt(Float(sum) / Float(count))
        }
    }
    
    static func spectralSnapshot(from url: URL, profile: DrumProfile, maxSeconds: Double = 90, targetSampleRate: Double = 22_050) -> SpectralSnapshot? {
        do {
            let file = try AVAudioFile(forReading: url)
            let sourceFormat = file.processingFormat
            let monoFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetSampleRate,
                channels: 1,
                interleaved: false
            )!
            guard let converter = AVAudioConverter(from: sourceFormat, to: monoFormat) else { return nil }
            converter.downmix = true
            
            let inputCapacity: AVAudioFrameCount = 2048
            let maxFrames = AVAudioFrameCount(targetSampleRate * maxSeconds)
            var processedFrames: AVAudioFrameCount = 0
            var finished = false
            
            var bands: [BandAccumulator] = []
            for band in profile.focusBands {
                if let filter = Biquad.bandpass(low: band.low, high: band.high, sampleRate: Float(targetSampleRate)) {
                    bands.append(BandAccumulator(filter: filter, weight: band.weight))
                }
            }
            
            if bands.isEmpty {
                return nil
            }
            
            var broadbandEnergy: Double = 0
            var broadbandPeak: Float = 0
            var offbandEnergy: Double = 0
            var sidechainEQ = buildSidechainEQ(profile: profile, sampleRate: Float(targetSampleRate))
            
            while !finished {
                guard let converted = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: inputCapacity) else { break }
                var error: NSError?
                let status = converter.convert(to: converted, error: &error) { _, outStatus in
                    if finished {
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    guard let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: inputCapacity) else {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    do {
                        try file.read(into: input, frameCount: inputCapacity)
                    } catch {
                        finished = true
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    if input.frameLength == 0 {
                        finished = true
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    outStatus.pointee = .haveData
                    return input
                }
                
                if let error { throw error }
                
                switch status {
                case .haveData:
                    guard let samples = converted.floatChannelData else { continue }
                    let frames = Int(converted.frameLength)
                    if frames == 0 { continue }
                    
                    for frame in 0..<frames {
                        var sample = samples[0][frame]
                        for idx in sidechainEQ.indices {
                            sample = sidechainEQ[idx].process(sample)
                        }
                        let absSample = fabsf(sample)
                        broadbandEnergy += Double(absSample * absSample)
                        broadbandPeak = max(broadbandPeak, absSample)
                        
                        var focusMax: Float = 0
                        for idx in bands.indices {
                            let mag = bands[idx].consume(sample)
                            focusMax = max(focusMax, mag)
                        }
                        let off = max(0, absSample - focusMax * 0.5)
                        offbandEnergy += Double(off * off)
                    }
                    
                    processedFrames += AVAudioFrameCount(frames)
                    if processedFrames >= maxFrames {
                        finished = true
                    }
                case .inputRanDry, .error, .endOfStream:
                    finished = true
                default:
                    break
                }
            }
            
            guard processedFrames > 0 else { return nil }
            let count = Int(processedFrames)
            let focusRMS: Float = {
                let sums = bands.reduce(0.0) { $0 + $1.sum }
                return sqrt(Float(sums) / Float(count))
            }()
            let focusPeak = bands.reduce(0) { max($0, $1.peak) }
            let offRMS = sqrt(Float(offbandEnergy) / Float(count))
            let broadbandRMS = sqrt(Float(broadbandEnergy) / Float(count))
            
            return SpectralSnapshot(
                focusRMS: focusRMS,
                focusPeak: focusPeak,
                offbandRMS: offRMS,
                broadbandRMS: broadbandRMS,
                broadbandPeak: broadbandPeak
            )
        } catch {
            return nil
        }
    }
    
    static func suggestSettings(from data: WaveformData, profile: DrumProfile?, spectral: SpectralSnapshot?) -> Suggestion? {
        let peakScale = max(data.peak, 0.0001)
        let raw = data.amplitudes
            .map { $0 * peakScale }
            .filter { $0.isFinite && $0 > 0 }
        guard raw.count >= 12, let maxAmp = raw.max(), maxAmp >= 0.01 else { return nil }
        let sorted = raw.sorted()
        let eps: Float = 0.000001
        
        let p10 = percentile(sorted, 0.10)
        let p15 = percentile(sorted, 0.15)
        let p50 = percentile(sorted, 0.50)
        let p75 = percentile(sorted, 0.75)
        let p90 = percentile(sorted, 0.90)
        let p95 = percentile(sorted, 0.95)
        let p99 = percentile(sorted, 0.99)
        
        let body = max(p50, p75 * 0.9)
        let peakLiftDb = 20 * log10f(max(maxAmp, eps) / max(body, eps))
        let tailLiftDb = 20 * log10f(max(p99, eps) / max(p75, eps))
        let floorLiftDb = 20 * log10f(max(p75, eps) / max(p10, eps))
        let hasBroadSeparation = peakLiftDb >= 6 || tailLiftDb >= 4 || floorLiftDb >= 8
        if !hasBroadSeparation {
            let focusDb = spectral?.focusToOffDb ?? 0
            guard focusDb >= 4 else { return nil }
        }
        
        // Find largest gap (in dB) in the upper half of the distribution.
        let startIndex = max(1, Int(Float(sorted.count) * 0.4))
        var bestGapDb: Float = 0
        var gapIndex = startIndex
        for idx in startIndex..<(sorted.count - 1) {
            let lower = sorted[idx]
            let upper = sorted[idx + 1]
            let gapDb = 20 * log10f(max(upper, eps) / max(lower, eps))
            if gapDb > bestGapDb {
                bestGapDb = gapDb
                gapIndex = idx
            }
        }
        
        let candidateLower = sorted[min(gapIndex, sorted.count - 2)]
        let candidateUpper = sorted[min(gapIndex + 1, sorted.count - 1)]
        
        let usesGap = bestGapDb >= 3 && candidateUpper >= body * 1.3
        let noiseAnchor = max(p10, p15 * 0.8)
        let thresholdLinear: Float = {
            if usesGap {
                let mid = candidateLower + (candidateUpper - candidateLower) * 0.55
                let gapBased = min(candidateUpper * 0.9, max(mid, body * 1.1))
                return max(gapBased, noiseAnchor * 1.2)
            } else {
                // Fallback: bias toward top 5–10% amplitudes.
                let high = max(p95 * 0.9, p90 * 1.1, body * 1.35)
                return max(high, noiseAnchor * 1.2)
            }
        }()
        
        let strongSeparation = bestGapDb >= 4.5 || peakLiftDb >= 12 || tailLiftDb >= 6
        let softenedLinear = strongSeparation ? thresholdLinear * 0.7 : thresholdLinear * 0.5
        let clampedLinear = min(maxAmp * 0.98, max(0.00005, softenedLinear))
        var thresholdDb = max(-60, min(-1, 20 * log10f(clampedLinear)))
        
        if let profile {
            thresholdDb += profile.thresholdBias
        }
        
        if let spectral {
            let focusDb = spectral.focusToOffDb
            if focusDb < 3 {
                thresholdDb += 3
            } else if focusDb < 6 {
                thresholdDb += 1.5
            } else if focusDb > 8 {
                thresholdDb -= 2.5
            } else if focusDb > 6.5 {
                thresholdDb -= 1.5
            }
            
            let crestDb = spectral.crestDb
            if crestDb > 14 {
                thresholdDb -= 1
            } else if crestDb < 9 {
                thresholdDb += 0.5
            }
        }
        
        thresholdDb -= 6.0 // Bias more open to reduce over-clamping on close mics.
        thresholdDb = max(-60, min(-1.0, thresholdDb))
        let finalLinear = powf(10.0, thresholdDb / 20.0)
        
        let normThreshold = finalLinear / peakScale
        let openLevel = max(0.01, normThreshold * 0.35)
        var segments: [Int] = []
        var current = 0
        for amp in data.amplitudes {
            if amp >= openLevel {
                current += 1
            } else if current > 0 {
                segments.append(current)
                current = 0
            }
        }
        if current > 0 { segments.append(current) }
        
        let releaseSuggestion: TimeInterval? = {
            guard let medianLen = medianCount(segments) else { return nil }
            let time = Double(medianLen) * data.binDuration
            // Bias toward keeping body/tail, clamp to reasonable gate ranges.
            return max(0.12, min(0.45, time * 0.85))
        }()
        
        let releaseAdjusted: TimeInterval? = {
            guard let releaseSuggestion else {
                if let profile {
                    let midpoint = Double((profile.holdRange.lowerBound + profile.holdRange.upperBound) / 2)
                    let maxRelease = Double(profile.holdRange.upperBound * 2.2)
                    return max(Double(profile.holdRange.lowerBound), min(maxRelease, midpoint))
                }
                return nil
            }
            guard let profile else { return releaseSuggestion }
            let minRelease = Double(profile.holdRange.lowerBound)
            let maxRelease = Double(profile.holdRange.upperBound * 2.2)
            let bounded = max(minRelease, min(maxRelease, releaseSuggestion))
            return bounded
        }()
        
        // Derive a suggested floor (minimum pass level) from noise stats so bleed is clamped.
        let noiseAnchorDb = 20 * log10f(max(noiseAnchor, 0.00005))
        let floorDb: Float = {
            // Bias floor toward the noise floor plus a small cushion, but keep headroom below threshold.
            let noisePlus = noiseAnchorDb + 4
            let belowThreshold = thresholdDb - 12
            let rawFloor = min(noisePlus, belowThreshold)
            return min(-6, max(-90, rawFloor))
        }()
        
        return Suggestion(threshold: thresholdDb, release: releaseAdjusted, floorDb: floorDb)
    }
    
    private static func medianCount(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
    
    private static func percentile(_ sorted: [Float], _ pct: Float) -> Float {
        guard !sorted.isEmpty else { return 0 }
        let clamped = min(max(pct, 0), 1)
        let idx = Int(round(clamped * Float(sorted.count - 1)))
        return sorted[max(0, min(sorted.count - 1, idx))]
    }
}
