import Foundation
import AVFoundation
import Accelerate

public struct WaveformData: Sendable {
    public let amplitudes: [Float] // Normalized 0...1 for UI
    public let peak: Float         // Absolute peak amplitude prior to normalization
    public let duration: TimeInterval
    public let binDuration: TimeInterval
    
    public init(amplitudes: [Float], peak: Float, duration: TimeInterval, binDuration: TimeInterval) {
        self.amplitudes = amplitudes
        self.peak = peak
        self.duration = duration
        self.binDuration = binDuration
    }
}

public enum WaveformLoader {
    public static func loadAmplitudes(from url: URL, maxSamples: Int = 1_200) throws -> [Float] {
        try loadAmplitudesWithPeak(from: url, maxSamples: maxSamples).amplitudes
    }
    
    public static func loadAmplitudesWithPeak(from url: URL, maxSamples: Int = 1_200) throws -> WaveformData {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: 1,
            interleaved: false
        )!
        guard let converter = AVAudioConverter(from: format, to: monoFormat) else {
            throw NSError(domain: "WaveformLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to create converter"])
        }
        converter.downmix = true
        
        let inputCapacity: AVAudioFrameCount = 2048
        var amplitudes: [Float] = []
        
        var finished = false
        
        while !finished {
            guard let converted = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: inputCapacity) else { break }
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, outStatus in
                if finished {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                guard let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: inputCapacity) else {
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
            
            if let error {
                throw error
            }
            
            switch status {
            case .haveData:
                guard let channelData = converted.floatChannelData else { continue }
                let frames = Int(converted.frameLength)
                if frames == 0 { continue }
                var sliceIndex = 0
                while sliceIndex < frames {
                    let windowSize = min(Int(inputCapacity), frames - sliceIndex)
                    let window = UnsafeBufferPointer(start: channelData[0] + sliceIndex, count: windowSize)
                    
                    if let peak = window.lazy.map(abs).max() {
                        amplitudes.append(peak)
                    }
                    sliceIndex += windowSize
                }
            case .inputRanDry, .error, .endOfStream:
                finished = true
            default:
                break
            }
        }
        
        let trimmedAmps = downsample(amplitudes, to: maxSamples)
        let ampMax = max(trimmedAmps.max() ?? 1, 0.0001)
        let normalized = trimmedAmps.map { min(1, max(0, $0 / ampMax)) }
        let duration = Double(file.length) / file.processingFormat.sampleRate
        let binDuration = duration / Double(max(normalized.count, 1))
        return WaveformData(amplitudes: normalized, peak: ampMax, duration: duration, binDuration: binDuration)
    }
    
    public static func loadSpectrogram(from url: URL, bands: Int = 48, maxColumns: Int = 240) throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: 1,
            interleaved: false
        )!
        guard let converter = AVAudioConverter(from: format, to: monoFormat) else {
            throw NSError(domain: "WaveformLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to create converter"])
        }
        converter.downmix = true
        
        let inputCapacity: AVAudioFrameCount = 2048
        var spectrogram: [[Float]] = Array(repeating: [], count: bands)
        var finished = false
        let dftSize = 1024
        guard let forwardDCT = vDSP.DCT(count: dftSize, transformType: .II) else {
            return []
        }
        
        while !finished {
            guard let converted = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: inputCapacity) else { break }
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, outStatus in
                if finished {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                guard let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: inputCapacity) else {
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
                guard let channelData = converted.floatChannelData else { continue }
                let frames = Int(converted.frameLength)
                if frames == 0 { continue }
                var sliceIndex = 0
                while sliceIndex < frames {
                    let windowSize = min(Int(inputCapacity), frames - sliceIndex)
                    var window = Array(UnsafeBufferPointer(start: channelData[0] + sliceIndex, count: windowSize))
                    
                    if window.count < dftSize {
                        window.append(contentsOf: repeatElement(0, count: dftSize - window.count))
                    } else if window.count > dftSize {
                        window = Array(window.prefix(dftSize))
                    }
                    
                    let spectrum = forwardDCT.transform(window)
                    let half = dftSize / 2
                    let magnitudes = spectrum.prefix(half).map { abs($0) }
                    let chunked = chunk(magnitudes, into: bands)
                    for band in 0..<bands {
                        spectrogram[band].append(chunked[band])
                    }
                    
                    sliceIndex += windowSize
                }
            case .inputRanDry, .error, .endOfStream:
                finished = true
            default:
                break
            }
        }
        
        let trimmedSpec = spectrogram.map { downsample($0, to: maxColumns) }
        let maxSpec = trimmedSpec.flatMap { $0 }.max() ?? 1
        let normalizedSpec = trimmedSpec.map { row in
            row.map { maxSpec > 0 ? min(1, $0 / maxSpec) : 0 }
        }
        return normalizedSpec
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
    
    private static func chunk(_ data: [Float], into bands: Int) -> [Float] {
        guard bands > 0 else { return [] }
        let stride = max(1, data.count / bands)
        return (0..<bands).map { idx in
            let start = idx * stride
            let end = min(data.count, start + stride)
            guard start < end else { return 0 }
            let slice = data[start..<end]
            return slice.max() ?? 0
        }
    }
}
