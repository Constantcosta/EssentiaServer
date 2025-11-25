import Foundation
import AVFoundation

public enum GateAutoDetector {
    public struct Suggestion: Sendable {
        public let threshold: Float
        public let release: TimeInterval?
        
        public init(threshold: Float, release: TimeInterval?) {
            self.threshold = threshold
            self.release = release
        }
    }
    
    public struct SpectralSnapshot: Sendable {
        public let focusRMS: Float
        public let focusPeak: Float
        public let offbandRMS: Float
        public let broadbandRMS: Float
        public let broadbandPeak: Float
        
        public init(focusRMS: Float, focusPeak: Float, offbandRMS: Float, broadbandRMS: Float, broadbandPeak: Float) {
            self.focusRMS = focusRMS
            self.focusPeak = focusPeak
            self.offbandRMS = offbandRMS
            self.broadbandRMS = broadbandRMS
            self.broadbandPeak = broadbandPeak
        }
        
        public var focusToOffDb: Float {
            let eps: Float = 0.000001
            return 20 * log10f(max(focusRMS, eps) / max(offbandRMS, eps))
        }
        
        public var crestDb: Float {
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
    
    public static func spectralSnapshot(from url: URL, profile: DrumProfile, maxSeconds: Double = 90, targetSampleRate: Double = 22_050) -> SpectralSnapshot? {
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
    
    public static func suggestSettings(from data: WaveformData, profile: DrumProfile?, spectral: SpectralSnapshot?) -> Suggestion? {
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
        
        let crestDb = spectral?.crestDb ?? 18
        let mixFloor: Float = {
            if crestDb >= 24 { return -42 }
            if crestDb >= 20 { return -36 }
            if crestDb >= 16 { return -32 }
            return -28
        }()
        let threshold: Float = {
            let base = percentile(sorted, 0.82)
            let mixDb = 20 * log10f(max(base, eps))
            let bias = (profile?.thresholdBias ?? -1)
            return min(0, mixDb + bias)
        }()
        
        let release: TimeInterval? = {
            let bodyDb = 20 * log10f(max(p75, eps))
            let floorDb = 20 * log10f(max(p15, eps))
            let ratioDb = bodyDb - floorDb
            if ratioDb < 3 {
                return nil
            } else if ratioDb < 6 {
                return 0.18
            } else if ratioDb < 10 {
                return 0.14
            } else {
                return 0.10
            }
        }()
        
        let clampedRelease = release.map { max(0.07, min(0.35, $0)) }
        let clampedThreshold = max(mixFloor, threshold)
        return Suggestion(threshold: clampedThreshold, release: clampedRelease)
    }
    
    private static func percentile(_ sorted: [Float], _ p: Double) -> Float {
        guard !sorted.isEmpty else { return 0 }
        let idx = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * p)))
        return sorted[idx]
    }
}
