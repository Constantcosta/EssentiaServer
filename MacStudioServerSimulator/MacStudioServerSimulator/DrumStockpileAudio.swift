//
//  DrumStockpileAudio.swift
//  MacStudioServerSimulator
//
//  Preview engine + export pipeline for Drum Stockpile.
//

import Foundation
import AVFoundation
import AVFAudio
import SwiftUI
import Accelerate

// MARK: - Preview Engine

@MainActor
final class DrumPreviewEngine: ObservableObject {
    @Published var isPlaying = false
    @Published var duration: TimeInterval = 0
    @Published var currentTime: TimeInterval = 0
    @Published var loopEnabled = false
    @Published var loopRange: ClosedRange<TimeInterval>?
    @Published var amplitudes: [Float]?
    @Published var spectrogram: [[Float]]?
    @Published var spectrogramLoading = false
    @Published var gatedWaveform: [Float]?
    
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var timer: Timer?
    private var sourceFile: AVAudioFile?
    private var playbackFile: AVAudioFile?
    private var gatePreviewURL: URL?
    private var waveformTask: Task<WaveformData, Error>?
    private var spectrogramTask: Task<Void, Never>?
    private var waveformToken = UUID()
    private var spectrogramToken = UUID()
    private var activeScheduleID = UUID()
    private var scheduledStartTime: TimeInterval = 0
    private var gateRenderTask: Task<Void, Never>?
    private var gateRenderToken = UUID()
    private var currentGate = GateSettings()
    private var waveformPeak: Float?
    
    init() {
        setupEngine()
    }
    
    deinit {
        engine.stop()
        timer?.invalidate()
        if let gatePreviewURL {
            try? FileManager.default.removeItem(at: gatePreviewURL)
        }
    }
    
    private func setupEngine() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePlaybackTime()
            }
        }
        
        do {
            try engine.start()
        } catch {
            print("Engine start failed: \(error.localizedDescription)")
        }
    }
    
    func load(url: URL, gate: GateSettings) async {
        let token = UUID()
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.waveformToken = token
            self.waveformTask?.cancel()
            self.waveformTask = nil
            self.spectrogramTask?.cancel()
            self.spectrogramTask = nil
            self.gateRenderTask?.cancel()
            self.gatedWaveform = nil
            self.spectrogram = nil
            self.spectrogramLoading = false
            self.stop()
            self.amplitudes = nil
            self.waveformPeak = nil
            if let gatePreviewURL = self.gatePreviewURL {
                try? FileManager.default.removeItem(at: gatePreviewURL)
                self.gatePreviewURL = nil
            }
            self.sourceFile = nil
            self.playbackFile = nil
        }
        
        do {
            let file = try AVAudioFile(forReading: url)
            let fileDuration = Double(file.length) / file.processingFormat.sampleRate
            
            await MainActor.run { [weak self] in
                guard let self, self.waveformToken == token else { return }
                self.sourceFile = file
                self.playbackFile = file
                self.duration = fileDuration
                self.currentTime = 0
                self.updateGate(gate)
                self.schedulePlayback(at: 0)
            }
            
            let task = Task.detached(priority: .userInitiated) {
                try WaveformLoader.loadAmplitudesWithPeak(from: url)
            }
            
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.waveformTask = task
            }
            
            let data = try await task.value
            try Task.checkCancellation()
            
            await MainActor.run { [weak self] in
                guard let self, self.waveformToken == token else { return }
                self.waveformTask = nil
                self.amplitudes = data.amplitudes
                self.waveformPeak = data.peak
                if self.currentGate.active {
                    self.scheduleGateOverlay(gate: self.currentGate)
                }
            }
        } catch is CancellationError {
            await MainActor.run { [weak self] in self?.waveformTask = nil }
        } catch {
            await MainActor.run { [weak self] in self?.waveformTask = nil }
            print("Preview load failed: \(error.localizedDescription)")
        }
    }
    
    func updateGate(_ gate: GateSettings) {
        currentGate = gate
        scheduleGateOverlay(gate: gate)
    }
    
    func autoGate(from gate: GateSettings) async -> GateSettings? {
        let token = waveformToken
        guard let data = await fetchWaveformData(), token == waveformToken else { return nil }
        guard let suggestion = GateAutoDetector.suggestSettings(from: data) else { return nil }
        var updated = gate
        updated.threshold = suggestion.threshold
        if let suggestedRelease = suggestion.release {
            updated.release = max(updated.release, Float(suggestedRelease))
        } else {
            // Fallback to a generous minimum.
            updated.release = max(updated.release, 0.14)
        }
        updated.active = true
        return updated
    }
    
    private func fetchWaveformData() async -> WaveformData? {
        let token = waveformToken
        if let amps = amplitudes, let peak = waveformPeak {
            let duration = self.duration
            let binDuration = duration > 0 ? duration / Double(max(amps.count, 1)) : 0
            return WaveformData(amplitudes: amps, peak: peak, duration: duration, binDuration: binDuration)
        }
        
        if let task = waveformTask {
            guard let data = try? await task.value else {
                if token == waveformToken { waveformTask = nil }
                return nil
            }
            guard token == waveformToken else { return nil }
            waveformTask = nil
            if amplitudes == nil { amplitudes = data.amplitudes }
            waveformPeak = data.peak
            return data
        }
        
        guard let sourceURL = sourceFile?.url else { return nil }
        let task = Task.detached(priority: .userInitiated) {
            try WaveformLoader.loadAmplitudesWithPeak(from: sourceURL)
        }
        waveformTask = task
        guard let data = try? await task.value else {
            if token == waveformToken { waveformTask = nil }
            return nil
        }
        guard token == waveformToken else { return nil }
        waveformTask = nil
        if amplitudes == nil { amplitudes = data.amplitudes }
        waveformPeak = data.peak
        return data
    }
    
    func play() {
        guard !isPlaying else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        player.play()
        isPlaying = true
    }
    
    func pause() {
        guard isPlaying else { return }
        player.pause()
        isPlaying = false
    }
    
    func togglePlayPause() {
        isPlaying ? pause() : play()
    }
    
    func seek(to time: TimeInterval) {
        guard let audioFile = playbackFile else { return }
        let wasPlaying = player.isPlaying || isPlaying
        let upperBound = loopRange?.upperBound ?? duration
        let lowerBound = loopRange?.lowerBound ?? 0
        let clamped = max(lowerBound, min(time, upperBound))
        let frame = AVAudioFramePosition(clamped * audioFile.processingFormat.sampleRate)
        currentTime = clamped
        schedulePlayback(at: max(0, frame))
        if wasPlaying {
            player.play()
            isPlaying = true
        }
    }
    
    func setLoop(range: ClosedRange<TimeInterval>?) {
        loopRange = range
        if isPlaying {
            let target = max(range?.lowerBound ?? 0, min(currentTime, range?.upperBound ?? duration))
            let frame = AVAudioFramePosition(target * (playbackFile?.processingFormat.sampleRate ?? 1))
            schedulePlayback(at: max(0, frame))
            player.play()
            isPlaying = true
        }
    }
    
    func stop() {
        player.stop()
        isPlaying = false
        activeScheduleID = UUID() // Invalidate any pending completions
    }
    
    private func schedulePlayback(at startFrame: AVAudioFramePosition) {
        guard let audioFile = playbackFile else { return }
        let scheduleID = UUID()
        activeScheduleID = scheduleID
        player.stop()
        
        let sr = audioFile.processingFormat.sampleRate
        let loopUpperFrame: AVAudioFramePosition? = {
            guard loopEnabled, let loopRange else { return nil }
            return AVAudioFramePosition(loopRange.upperBound * sr)
        }()
        
        // Clamp to loop bounds/EOF.
        let effectiveEnd = min(audioFile.length, loopUpperFrame ?? audioFile.length)
        var clampedStart = max(0, startFrame)
        if clampedStart >= effectiveEnd {
            clampedStart = max(0, effectiveEnd - 1)
        }
        audioFile.framePosition = clampedStart
        currentTime = Double(clampedStart) / audioFile.processingFormat.sampleRate
        scheduledStartTime = currentTime
        
        let remaining = max(0, effectiveEnd - clampedStart)
        let remainingFrames = AVAudioFrameCount(remaining)
        guard remainingFrames > 0 else {
            isPlaying = false
            return
        }
        
        player.scheduleSegment(
            audioFile,
            startingFrame: clampedStart,
            frameCount: remainingFrames,
            at: nil
        ) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard scheduleID == self.activeScheduleID else { return }
                let shouldLoop = self.loopEnabled
                let loopRangeCopy = self.loopRange
                guard shouldLoop, let loopRangeCopy else {
                    self.isPlaying = false
                    return
                }
                let loopStartFrame = AVAudioFramePosition(loopRangeCopy.lowerBound * sr)
                self.schedulePlayback(at: loopStartFrame)
                self.player.play()
            }
        }
    }
    
    private func scheduleGateOverlay(gate: GateSettings) {
        gateRenderTask?.cancel()
        gateRenderToken = UUID()
        let token = gateRenderToken
        gatedWaveform = nil
        guard gate.active else {
            gatedWaveform = nil
            gateRenderTask = nil
            switchToSourcePlayback()
            return
        }
        guard let sourceURL = sourceFile?.url else { return }
        
        let targetSamples = amplitudes?.count ?? 1_200
        gateRenderTask = Task.detached(priority: .utility) { [weak self] in
            // Brief debounce so rapid slider drags don't trigger multiple renders.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            guard let result = try? GatePreviewLoader.renderPreview(from: sourceURL, gate: gate, targetSamples: targetSamples) else { return }
            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: result.renderedURL)
                return
            }
            await MainActor.run { [weak self, token] in
                guard let self, token == self.gateRenderToken else {
                    try? FileManager.default.removeItem(at: result.renderedURL)
                    return
                }
                self.applyGatePreview(result)
            }
        }
    }
    
    private func applyGatePreview(_ result: GatePreviewResult) {
        gatedWaveform = result.peaks
        
        if let gatePreviewURL, gatePreviewURL != result.renderedURL {
            try? FileManager.default.removeItem(at: gatePreviewURL)
        }
        gatePreviewURL = result.renderedURL
        
        do {
            let playback = try AVAudioFile(forReading: result.renderedURL)
            playbackFile = playback
            let wasPlaying = player.isPlaying || isPlaying
            let resumeTime = currentTime
            schedulePlayback(at: AVAudioFramePosition(resumeTime * playback.processingFormat.sampleRate))
            if wasPlaying {
                player.play()
                isPlaying = true
            }
        } catch {
            try? FileManager.default.removeItem(at: result.renderedURL)
            gatePreviewURL = nil
            print("Gate preview apply failed: \(error.localizedDescription)")
        }
    }
    
    private func switchToSourcePlayback() {
        gateRenderTask = nil
        if let gatePreviewURL {
            try? FileManager.default.removeItem(at: gatePreviewURL)
            self.gatePreviewURL = nil
        }
        guard let sourceFile else {
            playbackFile = nil
            stop()
            return
        }
        playbackFile = sourceFile
        let wasPlaying = player.isPlaying || isPlaying
        let resumeTime = currentTime
        schedulePlayback(at: AVAudioFramePosition(resumeTime * sourceFile.processingFormat.sampleRate))
        if wasPlaying {
            player.play()
            isPlaying = true
        }
    }
    
    private func updatePlaybackTime() {
        guard isPlaying, let nodeTime = player.lastRenderTime, let playerTime = player.playerTime(forNodeTime: nodeTime) else { return }
        let elapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
        currentTime = min(duration, scheduledStartTime + elapsed)
    }
    
    func loadSpectrogramIfNeeded(bands: Int = 48) {
        guard spectrogram == nil, !spectrogramLoading, let sourceURL = sourceFile?.url else { return }
        spectrogramLoading = true
        let token = UUID()
        spectrogramToken = token
        spectrogramTask?.cancel()
        spectrogramTask = Task.detached(priority: .utility) { [weak self] in
            defer {
                Task { @MainActor [weak self, token] in
                    guard let self, token == self.spectrogramToken else { return }
                    self.spectrogramLoading = false
                }
            }
            let data = try? WaveformLoader.loadSpectrogram(from: sourceURL, bands: bands)
            guard !Task.isCancelled, let data else { return }
            await MainActor.run { [weak self, token] in
                guard let self, token == self.spectrogramToken else { return }
                self.spectrogram = data
            }
        }
    }
}

// MARK: - Exporter

enum DrumStockpileExporter {
    static func export(
        items: [StockpileItem],
        destination: URL,
        progress: @escaping (Double) -> Void
    ) async throws -> StockpileManifest {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        var entries: [StockpileManifestEntry] = []
        let total = max(1, items.count)
        
        for (index, item) in items.enumerated() {
            let outputName = "\(item.id.uuidString)_\(item.classification.manifestLabel).wav"
            let outputURL = destination.appendingPathComponent(outputName)
            try await process(item: item, outputURL: outputURL)
            
            var midiFilename: String?
            if let midi = item.metadata.midiRef {
                let midiName = "\(item.id.uuidString)_\(midi.lastPathComponent)"
                let midiTarget = destination.appendingPathComponent(midiName)
                if fm.fileExists(atPath: midiTarget.path) {
                    try? fm.removeItem(at: midiTarget)
                }
                try? fm.copyItem(at: midi, to: midiTarget)
                midiFilename = midiName
            }
            
            entries.append(
                StockpileManifestEntry(
                    id: item.id,
                    groupID: item.groupID,
                    classification: item.classification.manifestLabel,
                    bpm: item.metadata.bpm,
                    key: item.metadata.key,
                    midiFilename: midiFilename,
                    midiOffset: item.metadata.midiOffset,
                    originalFilename: item.originalFilename,
                    outputFilename: outputName
                )
            )
            
            progress(Double(index + 1) / Double(total))
        }
        
        return StockpileManifest(items: entries)
    }
    
    private static func process(item: StockpileItem, outputURL: URL) async throws {
        let sourceFile = try AVAudioFile(forReading: item.originalURL)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 44_100,
            channels: 1,
            interleaved: true
        )!
        guard let converter = AVAudioConverter(from: sourceFile.processingFormat, to: targetFormat) else {
            throw NSError(domain: "DrumStockpileExporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to create converter"])
        }
        converter.downmix = true
        
        let writer = try AVAudioFile(
            forWriting: outputURL,
            settings: targetFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        
        let inputCapacity: AVAudioFrameCount = 4096
        var finished = false
        
        while !finished {
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: inputCapacity) else { break }
            var conversionError: NSError?
            let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
                if finished {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFile.processingFormat, frameCapacity: inputCapacity) else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                do {
                    try sourceFile.read(into: inputBuffer, frameCount: inputCapacity)
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
            
            if let conversionError {
                throw conversionError
            }
            
            switch status {
            case .haveData:
                guard convertedBuffer.frameLength > 0 else { continue }
                applyGateIfNeeded(to: convertedBuffer, gate: item.gateSettings)
                try writer.write(from: convertedBuffer)
            case .inputRanDry, .error, .endOfStream:
                finished = true
            default:
                break
            }
        }
    }
    
    private static func applyGateIfNeeded(to buffer: AVAudioPCMBuffer, gate: GateSettings) {
        guard gate.active else { return }
        guard let channelData = buffer.int16ChannelData else { return }
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        let sampleRate = Float(buffer.format.sampleRate)
        let thresholdLinear = powf(10.0, gate.threshold / 20.0)
        let gateFloor: Float = 0.005 // Higher floor to keep highs/tails audible
        let gateShape: Float = 1.6   // Gentler curve to avoid dulling
        let attackCoeff = gate.attack > 0 ? expf(-1.0 / (sampleRate * gate.attack)) : 0
        // Target roughly -60 dB decay over the release time for an audible tail.
        let releaseCoeff = gate.release > 0 ? expf(-6.90775527898 / (sampleRate * gate.release)) : 0
        let maxInt: Float = 32_767.0
        // Keep the gate open for most of the release window to avoid premature clamp.
        let holdSamples = max(1, Int(sampleRate * max(0.02, gate.release * 0.9)))
        var envelope: Float = 0
        var holdCounter = 0
        
        for frame in 0..<frames {
            var peak: Float = 0
            for channel in 0..<channels {
                let sample = Float(channelData[channel][frame]) / maxInt
                peak = max(peak, fabsf(sample))
            }
            
            if peak > envelope {
                envelope = attackCoeff * (envelope - peak) + peak
            } else {
                envelope = releaseCoeff * (envelope - peak) + peak
            }
            
            let ratio = envelope / max(thresholdLinear, 0.000001)
            if ratio >= 1 {
                holdCounter = holdSamples
            }
            
            let gain: Float
            if holdCounter > 0 {
                gain = 1
                holdCounter -= 1
            } else {
                gain = ratio >= 1
                    ? 1
                    : max(gateFloor, powf(max(0, ratio), gateShape))
            }
            
            for channel in 0..<channels {
                let rawSample = Float(channelData[channel][frame])
                let processed = rawSample * gain
                channelData[channel][frame] = Int16(max(-32_768, min(32_767, processed)))
            }
        }
    }
}

// MARK: - Waveform + Spectrogram

struct GatePreviewResult {
    let peaks: [Float]
    let renderedURL: URL
}

struct WaveformData: Sendable {
    let amplitudes: [Float] // Normalized 0...1 for UI
    let peak: Float         // Absolute peak amplitude prior to normalization
    let duration: TimeInterval
    let binDuration: TimeInterval
}

enum GatePreviewLoader {
    static func loadRenderedPeaks(from url: URL, gate: GateSettings, targetSamples: Int = 1_200) throws -> [Float] {
        let result = try renderPreview(from: url, gate: gate, targetSamples: targetSamples)
        try? FileManager.default.removeItem(at: result.renderedURL)
        return result.peaks
    }
    
    static func renderPreview(from url: URL, gate: GateSettings, targetSamples: Int = 1_200, renderSampleRate: Double = 22_050) throws -> GatePreviewResult {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: renderSampleRate,
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
        
        let inputCapacity: AVAudioFrameCount = 4096
        var finished = false
        var peaks: [Float] = []
        var rawMax: Float = 0
        let maxInt: Float = 32_767
        
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
                
                applyGate(to: convertedBuffer, gate: gate)
                
                // Capture gated peak per chunk for overlay.
                let chunkSize = 1024
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
    
    private static func applyGate(to buffer: AVAudioPCMBuffer, gate: GateSettings) {
        guard gate.active, let channelData = buffer.int16ChannelData else { return }
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        let sampleRate = Float(buffer.format.sampleRate)
        let thresholdLinear = powf(10.0, gate.threshold / 20.0)
        let gateFloor: Float = 0.005 // Higher floor to keep highs/tails audible
        let gateShape: Float = 1.6   // Gentler curve to avoid dulling
        let attackCoeff = gate.attack > 0 ? expf(-1.0 / (sampleRate * gate.attack)) : 0
        let releaseCoeff = gate.release > 0 ? expf(-6.90775527898 / (sampleRate * gate.release)) : 0
        let maxInt: Float = 32_767.0
        let holdSamples = max(1, Int(sampleRate * max(0.02, gate.release * 0.9)))
        var envelope: Float = 0
        var holdCounter = 0
        
        for frame in 0..<frames {
            var peak: Float = 0
            for channel in 0..<channels {
                let sample = Float(channelData[channel][frame]) / maxInt
                peak = max(peak, fabsf(sample))
            }
            
            if peak > envelope {
                envelope = attackCoeff * (envelope - peak) + peak
            } else {
                envelope = releaseCoeff * (envelope - peak) + peak
            }
            
            let ratio = envelope / max(thresholdLinear, 0.000001)
            if ratio >= 1 {
                holdCounter = holdSamples
            }
            
            let gain: Float
            if holdCounter > 0 {
                gain = 1
                holdCounter -= 1
            } else {
                gain = ratio >= 1
                    ? 1
                    : max(gateFloor, powf(max(0, ratio), gateShape))
            }
            
            for channel in 0..<channels {
                let rawSample = Float(channelData[channel][frame])
                let processed = rawSample * gain
                channelData[channel][frame] = Int16(max(-32_768, min(32_767, processed)))
            }
        }
    }
}

enum GateAutoDetector {
    struct Suggestion {
        let threshold: Float
        let release: TimeInterval?
    }
    
    static func suggestSettings(from data: WaveformData) -> Suggestion? {
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
        guard peakLiftDb >= 6 || tailLiftDb >= 4 || floorLiftDb >= 8 else { return nil }
        
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
                return max(gapBased, noiseAnchor * 1.8)
            } else {
                // Fallback: bias toward top 5–10% amplitudes.
                let high = max(p95 * 0.9, p90 * 1.1, body * 1.35)
                return max(high, noiseAnchor * 1.8)
            }
        }()
        
        let strongSeparation = bestGapDb >= 4.5 || peakLiftDb >= 12 || tailLiftDb >= 6
        let softenedLinear = strongSeparation ? thresholdLinear * 0.7 : thresholdLinear * 0.5
        let clampedLinear = min(maxAmp * 0.98, max(0.00005, softenedLinear))
        let thresholdDb = max(-60, min(-1, 20 * log10f(clampedLinear)))
        
        let normThreshold = clampedLinear / peakScale
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
        
        return Suggestion(threshold: thresholdDb, release: releaseSuggestion)
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

enum WaveformLoader {
    static func loadAmplitudes(from url: URL, maxSamples: Int = 1_200) throws -> [Float] {
        try loadAmplitudesWithPeak(from: url, maxSamples: maxSamples).amplitudes
    }
    
    static func loadAmplitudesWithPeak(from url: URL, maxSamples: Int = 1_200) throws -> WaveformData {
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
    
    static func loadSpectrogram(from url: URL, bands: Int = 48, maxColumns: Int = 240) throws -> [[Float]] {
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
    
    private static func chunk(_ data: [Float], into buckets: Int) -> [Float] {
        guard buckets > 0 else { return [] }
        let stride = Double(data.count) / Double(buckets)
        return (0..<buckets).map { idx in
            let start = Int(Double(idx) * stride)
            let end = min(data.count, Int(Double(idx + 1) * stride))
            if start >= end { return 0 }
            let slice = data[start..<end]
            return (slice.max() ?? 0)
        }
    }
}
