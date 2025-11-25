import Foundation
import AVFoundation

public struct GateProcessor {
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
    }
    
    private var config: Config?
    private var envelope: Float = 0
    private var holdCounter: Int = 0
    private var bandDetector: BandDetector?
    private var sidechainEQ: [Biquad] = []
    
    public init() {}
    
    public init?(gate: GateSettings, sampleRate: Float, profile: DrumProfile?) {
        guard gate.active else { return nil }
        reconfigure(gate: gate, sampleRate: sampleRate, profile: profile)
    }
    
    @discardableResult
    public mutating func reconfigure(gate: GateSettings, sampleRate: Float, profile: DrumProfile?) -> Bool {
        guard gate.active else {
            config = nil
            return false
        }
        
        let thresholdDb = gate.threshold
        let thresholdLinear = powf(10.0, thresholdDb / 20.0)
        let closeRatio = max(0.25, min(profile?.hysteresisRatio ?? 0.6, 0.95))
        let profileFloorDb = profile?.floorDb ?? -18
        let tightness = min(1.0, max(0.0, (thresholdDb + 24.0) / 24.0))
        let floorDb = profileFloorDb * (1 - tightness) + (-60.0 * tightness)
        let floorGain = powf(10.0, floorDb / 20.0)
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
            transientFactor: 1.3
        )
        
        if let profile, let detector = BandDetector(bands: profile.focusBands, sampleRate: sampleRate) {
            bandDetector = detector
        } else {
            bandDetector = nil
        }
        sidechainEQ = profile.map { buildSidechainEQ(profile: $0, sampleRate: sampleRate) } ?? []
        return true
    }
    
    public mutating func process(buffer: AVAudioPCMBuffer) {
        guard let config else { return }
        switch buffer.format.commonFormat {
        case .pcmFormatInt16:
            process(int16Buffer: buffer, config: config)
        case .pcmFormatFloat32:
            process(floatBuffer: buffer, config: config)
        default:
            break
        }
    }
    
    public mutating func process(bufferList: UnsafeMutableAudioBufferListPointer, frameCount: Int) {
        guard let config else { return }
        process(bufferList: bufferList, frameCount: frameCount, config: config)
    }
    
    private mutating func process(floatBuffer buffer: AVAudioPCMBuffer, config: Config) {
        guard let channelData = buffer.floatChannelData else { return }
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        processCore(channelPointers: (0..<channels).map { channelData[$0] }, channels: channels, frames: frames, sampleMax: 1.0, config: config)
    }
    
    private mutating func process(int16Buffer buffer: AVAudioPCMBuffer, config: Config) {
        guard let channelData = buffer.int16ChannelData else { return }
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        let sampleMax = config.sampleMax
        processCore(
            channelPointers: (0..<channels).map { UnsafeMutablePointer<Float>(OpaquePointer(channelData[$0])) },
            channels: channels,
            frames: frames,
            sampleMax: sampleMax,
            config: config,
            int16Source: channelData
        )
    }
    
    private mutating func process(
        bufferList: UnsafeMutableAudioBufferListPointer,
        frameCount: Int,
        config: Config
    ) {
        let channels = bufferList.count
        var channelPointers: [UnsafeMutablePointer<Float>] = []
        channelPointers.reserveCapacity(channels)
        for bufferIndex in 0..<channels {
            let buffer = bufferList[bufferIndex]
            guard let data = buffer.mData else { continue }
            let ptr = data.assumingMemoryBound(to: Float.self)
            channelPointers.append(ptr)
        }
        processCore(
            channelPointers: channelPointers,
            channels: channels,
            frames: frameCount,
            sampleMax: 1.0,
            config: config
        )
    }
    
    private mutating func processCore(
        channelPointers: [UnsafeMutablePointer<Float>],
        channels: Int,
        frames: Int,
        sampleMax: Float,
        config: Config,
        int16Source: UnsafePointer<UnsafeMutablePointer<Int16>>? = nil
    ) {
        guard !channelPointers.isEmpty else { return }
        let channelCount = max(channels, 1)
        
        for frame in 0..<frames {
            var mono: Float = 0
            var rawPeakNorm: Float = 0
            let maxDetected: Float = 8
            
            if let int16Source {
                // Handle 16-bit buffers (used by preview/export pipeline).
                var peak: Float = 0
                for channel in 0..<channelCount {
                    let sample = Float(int16Source[channel][frame])
                    mono += sample
                    peak = max(peak, fabsf(sample))
                }
                mono /= Float(channelCount)
                rawPeakNorm = peak / sampleMax
            } else {
                for channel in 0..<channelCount {
                    let sample = channelPointers[channel][frame]
                    mono += sample
                    rawPeakNorm = max(rawPeakNorm, fabsf(sample))
                }
                mono /= Float(channelCount)
            }
            
            var sidechain = mono
            for idx in sidechainEQ.indices {
                sidechain = sidechainEQ[idx].process(sidechain)
            }
            let broadband = abs(sidechain)
            let focus = (bandDetector?.process(sample: sidechain) ?? 0) * config.focusWeight
            let detectionBoostLimitDb: Float = 12
            let detectionBoost = powf(10, detectionBoostLimitDb / 20)
            let detectionCap = maxDetected * detectionBoost
            let boostedLimit = max(rawPeakNorm * detectionBoost, rawPeakNorm)
            let detectedCandidate = max(broadband, focus)
            let detected = max(rawPeakNorm, min(detectionCap, min(maxDetected, min(boostedLimit, detectedCandidate))))
            
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
                if let int16Source {
                    let processed = Float(int16Source[channel][frame]) * gain
                    int16Source[channel][frame] = Int16(max(-32_768, min(32_767, processed)))
                } else {
                    channelPointers[channel][frame] *= gain
                }
            }
        }
    }
}
