import Foundation
import AVFoundation
import AVFAudio

public struct GatePreviewResult: Sendable {
    public let peaks: [Float]
    public let renderedURL: URL
    
    public init(peaks: [Float], renderedURL: URL) {
        self.peaks = peaks
        self.renderedURL = renderedURL
    }
}

public struct GatePreviewCacheKey: Hashable, Sendable {
    public let url: URL
    public let gate: GateSettings
    public let classification: DrumClass?
    
    public init(url: URL, gate: GateSettings, classification: DrumClass?) {
        self.url = url
        self.gate = gate
        self.classification = classification
    }
}

public func previewRenderSampleRate(duration: TimeInterval, defaultRate: Double = 22_050) -> Double {
    if duration > 10 * 60 {
        return 12_000
    } else if duration > 5 * 60 {
        return 16_000
    } else if duration > 3 * 60 {
        return 18_000
    }
    return defaultRate
}

public enum GatePreviewLoader {
    public static func loadRenderedPeaks(from url: URL, gate: GateSettings, targetSamples: Int = 1_200, profile: DrumProfile? = nil) throws -> [Float] {
        let result = try renderPreview(from: url, gate: gate, targetSamples: targetSamples, profile: profile)
        try? FileManager.default.removeItem(at: result.renderedURL)
        return result.peaks
    }
    
    public static func renderPreview(
        from url: URL,
        gate: GateSettings,
        targetSamples: Int = 1_200,
        renderSampleRate: Double = 22_050,
        profile: DrumProfile? = nil
    ) throws -> GatePreviewResult {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        let durationSeconds = Double(file.length) / sourceFormat.sampleRate
        let effectiveRate = previewRenderSampleRate(duration: durationSeconds, defaultRate: renderSampleRate)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: effectiveRate,
            channels: 1,
            interleaved: true
        )!
        
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw NSError(domain: "GatePreviewLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to create converter"])
        }
        converter.downmix = true
        
        let previewURL = FileManager.default.temporaryDirectory.appendingPathComponent("drum_gate_preview_\(UUID().uuidString).wav")
        let writer = try AVAudioFile(
            forWriting: previewURL,
            settings: targetFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        
        let inputCapacity: AVAudioFrameCount = {
            if durationSeconds > 10 * 60 { return 131_072 }
            if durationSeconds > 5 * 60 { return 65_536 }
            if durationSeconds > 3 * 60 { return 16_384 }
            return 4_096
        }()
        var finished = false
        var peaks: [Float] = []
        var rawMax: Float = 0
        let maxInt: Float = 32_767
        var gateProcessor = GateProcessor()
        gateProcessor.reconfigure(
            gate: gate,
            sampleRate: Float(targetFormat.sampleRate),
            profile: profile
        )
        
        while !finished {
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: inputCapacity) else { break }
            var conversionError: NSError?
            let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
                if finished {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: inputCapacity) else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                do {
                    try file.read(into: inputBuffer, frameCount: inputCapacity)
                } catch {
                    finished = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                if inputBuffer.frameLength == 0 {
                    finished = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return inputBuffer
            }
            
            if let conversionError { throw conversionError }
            
            switch status {
            case .haveData:
                guard let channelData = convertedBuffer.int16ChannelData else { continue }
                let frames = Int(convertedBuffer.frameLength)
                if frames == 0 { continue }
                
                for frame in 0..<frames {
                    rawMax = max(rawMax, fabsf(Float(channelData[0][frame])) / maxInt)
                }
                
                gateProcessor.process(buffer: convertedBuffer)
                
                let chunkSize: Int = {
                    if durationSeconds > 10 * 60 { return 8_192 }
                    if durationSeconds > 5 * 60 { return 4_096 }
                    if durationSeconds > 3 * 60 { return 2_048 }
                    return 1_024
                }()
                var chunkPeak: Float = 0
                for frame in 0..<frames {
                    let sample = fabsf(Float(channelData[0][frame])) / maxInt
                    chunkPeak = max(chunkPeak, sample)
                    if (frame + 1) % chunkSize == 0 {
                        peaks.append(chunkPeak)
                        chunkPeak = 0
                    }
                }
                if chunkPeak > 0 {
                    peaks.append(chunkPeak)
                }
                
                do {
                    try writer.write(from: convertedBuffer)
                } catch {
                    throw error
                }
            case .inputRanDry, .error, .endOfStream:
                finished = true
            default:
                break
            }
        }
        
        let downsampled = downsample(peaks, to: targetSamples)
        let norm = max(rawMax, 0.0001)
        let normalized = downsampled.map { min(1, max(0, $0 / norm)) }
        return GatePreviewResult(peaks: normalized, renderedURL: previewURL)
    }
    
    private static func downsample(_ data: [Float], to target: Int) -> [Float] {
        guard data.count > target, target > 0 else { return data }
        let stride = Double(data.count) / Double(target)
        return (0..<target).map { idx in
            let start = Int(Double(idx) * stride)
            let end = min(data.count, Int(Double(idx + 1) * stride))
            if start >= end { return 0 }
            let slice = data[start..<end]
            return slice.max() ?? 0
        }
    }
}
