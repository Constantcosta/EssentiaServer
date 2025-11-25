//
//  DrumStockpileAudio.swift
//  MacStudioServerSimulator
//
//  Preview engine for Drum Stockpile.
//

import Foundation
import AVFoundation
@preconcurrency import AVFAudio
import AudioToolbox
import SwiftUI

private extension AudioComponentDescription {
    var componentKey: String {
        "\(componentType)-\(componentSubType)-\(componentManufacturer)"
    }
}

struct AudioInsertDescriptor: Identifiable, Hashable {
    let description: AudioComponentDescription
    let name: String
    let manufacturer: String
    let hasCustomView: Bool
    
    var id: String { description.componentKey }
    
    static func == (lhs: AudioInsertDescriptor, rhs: AudioInsertDescriptor) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@MainActor
final class AudioInsertSlot: ObservableObject, Identifiable {
    let id = UUID()
    let descriptor: AudioInsertDescriptor
    let node: AVAudioUnit
    @Published var isBypassed: Bool {
        didSet {
            node.auAudioUnit.shouldBypassEffect = isBypassed
        }
    }
    
    init(node: AVAudioUnit, descriptor: AudioInsertDescriptor) {
        self.node = node
        self.descriptor = descriptor
        self.isBypassed = node.auAudioUnit.shouldBypassEffect
    }
}

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
    @Published private(set) var waveformPeak: Float?
    @Published var errorMessage: String?
    @Published private(set) var availablePlugins: [AudioInsertDescriptor] = []
    @Published private(set) var pluginSlots: [AudioInsertSlot] = []
    @Published var pluginError: String?
    
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var setupTask: Task<Void, Never>?
    private var gateNode: AVAudioUnit?
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
    private var currentClassification: DrumClass?
    private var gatePreviewCache: [GatePreviewCacheKey: GatePreviewResult] = [:]
    private var cachedPreviewURLs: Set<URL> = []
    private var gateInsertEnabled = true
    
    private var realtimeGate: RealtimeGateAudioUnit? {
        gateNode?.auAudioUnit as? RealtimeGateAudioUnit
    }
    
    init() {
        refreshAvailablePlugins()
        setupTask = Task { [weak self] in
            guard let self else { return }
            await self.setupEngine()
        }
    }
    
    deinit {
        setupTask?.cancel()
        engine.stop()
        for slot in pluginSlots where engine.attachedNodes.contains(slot.node) {
            engine.detach(slot.node)
        }
        if let gateNode, engine.attachedNodes.contains(gateNode) {
            engine.detach(gateNode)
        }
        timer?.invalidate()
        let fm = FileManager.default
        if let gatePreviewURL, !cachedPreviewURLs.contains(gatePreviewURL) {
            try? fm.removeItem(at: gatePreviewURL)
        }
        for url in cachedPreviewURLs {
            try? fm.removeItem(at: url)
        }
    }
    
    private func setupEngine() async {
        RealtimeGateAudioUnit.register()
        engine.attach(player)
        
        await configureGateInsert()
        rebuildSignalChain()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePlaybackTime()
            }
        }
        
        do {
            try engine.start()
            applyGateToPlayback()
        } catch {
            print("Engine start failed: \(error.localizedDescription)")
        }
    }
    
    private func configureGateInsert() async {
        do {
            let gateUnit = try await instantiateGateUnit()
            gateNode = gateUnit
            if !engine.attachedNodes.contains(gateUnit) {
                engine.attach(gateUnit)
            }
        } catch {
            print("Realtime gate init failed: \(error.localizedDescription)")
            gateNode = nil
        }
    }
    
    private func instantiateGateUnit() async throws -> AVAudioUnit {
        try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: RealtimeGateAudioUnit.componentDescription, options: []) { unit, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let unit else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "DrumPreviewEngine",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Unable to instantiate realtime gate"]
                        )
                    )
                    return
                }
                continuation.resume(returning: unit)
            }
        }
    }
    
    func reloadAvailablePlugins() {
        refreshAvailablePlugins()
    }
    
    func addPlugin(_ descriptor: AudioInsertDescriptor) {
        Task { @MainActor in
            await ensureEngineReady()
            pluginError = nil
            do {
                let unit = try await instantiateAudioUnit(for: descriptor.description)
                let slot = AudioInsertSlot(node: unit, descriptor: descriptor)
                pluginSlots.append(slot)
                rebuildSignalChain(format: playbackFile?.processingFormat)
            } catch {
                pluginError = "Unable to load \(descriptor.name): \(error.localizedDescription)"
            }
        }
    }
    
    func removePlugin(_ slot: AudioInsertSlot) {
        guard let idx = pluginSlots.firstIndex(where: { $0.id == slot.id }) else { return }
        if engine.attachedNodes.contains(slot.node) {
            engine.disconnectNodeOutput(slot.node)
            engine.detach(slot.node)
        }
        pluginSlots.remove(at: idx)
        rebuildSignalChain(format: playbackFile?.processingFormat)
    }
    
    func movePlugin(_ slot: AudioInsertSlot, direction: Int) {
        guard let idx = pluginSlots.firstIndex(where: { $0.id == slot.id }) else { return }
        let target = idx + direction
        guard target >= 0, target < pluginSlots.count else { return }
        pluginSlots.swapAt(idx, target)
        rebuildSignalChain(format: playbackFile?.processingFormat)
    }
    
    private func makeEffectChain() -> [AVAudioUnit] {
        var nodes: [AVAudioUnit] = []
        if gateInsertEnabled, let gateNode {
            nodes.append(gateNode)
        }
        nodes.append(contentsOf: pluginSlots.map { $0.node })
        return nodes
    }
    
    private func refreshAvailablePlugins() {
        let manager = AVAudioUnitComponentManager.shared()
        let matcher = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        let components = manager.components(matching: matcher)
        availablePlugins = components.map {
            AudioInsertDescriptor(
                description: $0.audioComponentDescription,
                name: $0.name,
                manufacturer: $0.manufacturerName,
                hasCustomView: $0.hasCustomView
            )
        }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
    
    private func instantiateAudioUnit(for description: AudioComponentDescription) async throws -> AVAudioUnit {
        try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: description, options: []) { unit, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let unit else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "DrumPreviewEngine",
                            code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "Unable to instantiate audio unit"]
                        )
                    )
                    return
                }
                continuation.resume(returning: unit)
            }
        }
    }
    
    private func rebuildSignalChain(format: AVAudioFormat? = nil) {
        if format != nil, gateNode != nil {
            gateInsertEnabled = true // retry gate insert when a new file format arrives
        }
        let wasRunning = engine.isRunning
        let wasPlaying = player.isPlaying || isPlaying
        let resumeFrame = playbackFile.map { file in
            AVAudioFramePosition(currentTime * file.processingFormat.sampleRate)
        }
        let chain = makeEffectChain()
        if wasRunning {
            engine.stop()
        }
        engine.reset()
        engine.disconnectNodeOutput(player)
        for node in chain {
            engine.disconnectNodeOutput(node)
        }
        
        let targetFormat = format ?? player.outputFormat(forBus: 0)
        if let gateAU = gateNode?.auAudioUnit {
            try? gateAU.inputBusses[0].setFormat(targetFormat)
            try? gateAU.outputBusses[0].setFormat(targetFormat)
        }
        for slot in pluginSlots {
            let au = slot.node.auAudioUnit
            if au.inputBusses.count > 0 {
                try? au.inputBusses[0].setFormat(targetFormat)
            }
            if au.outputBusses.count > 0 {
                try? au.outputBusses[0].setFormat(targetFormat)
            }
        }
        
        func connect(chain: [AVAudioUnit]) {
            var previous: AVAudioNode = player
            for node in chain {
                if !engine.attachedNodes.contains(node) {
                    engine.attach(node)
                }
                engine.connect(previous, to: node, format: targetFormat)
                previous = node
            }
            engine.connect(previous, to: engine.mainMixerNode, format: targetFormat)
        }
        
        connect(chain: chain)
        
        let restartNeeded = wasRunning || format != nil
        if restartNeeded {
            do {
                try engine.start()
                if wasPlaying, let resumeFrame {
                    schedulePlayback(at: resumeFrame)
                    player.play()
                    isPlaying = true
                }
            } catch {
                print("Engine restart failed (with gate): \(error.localizedDescription). Falling back to dry chain.")
                gateInsertEnabled = false
                engine.stop()
                engine.reset()
                engine.disconnectNodeOutput(player)
                for node in chain {
                    engine.disconnectNodeOutput(node)
                }
                connect(chain: chain)
                do {
                    try engine.start()
                    if wasPlaying, let resumeFrame {
                        schedulePlayback(at: resumeFrame)
                        player.play()
                        isPlaying = true
                    }
                } catch {
                    print("Engine restart failed (dry): \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func ensureEngineReady() async {
        if let setupTask {
            _ = await setupTask.result
        }
    }
    
    
    func load(url: URL, gate: GateSettings, classification: DrumClass? = nil) async {
        await ensureEngineReady()
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
            self.errorMessage = nil
            self.currentClassification = classification
            self.sourceFile = nil
            self.playbackFile = nil
        }
        
        do {
            guard FileManager.default.fileExists(atPath: url.path) else {
                await MainActor.run { [weak self] in
                    guard let self, self.waveformToken == token else { return }
                    self.errorMessage = "File not found: \(url.lastPathComponent)"
                    self.duration = 0
                    self.currentTime = 0
                }
                return
            }
            
            let file = try AVAudioFile(forReading: url)
            let fileDuration = Double(file.length) / file.processingFormat.sampleRate
            
            await MainActor.run { [weak self] in
                guard let self, self.waveformToken == token else { return }
                self.sourceFile = file
                self.playbackFile = file
                self.rebuildSignalChain(format: file.processingFormat)
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
            await MainActor.run { [weak self] in
                guard let self, self.waveformToken == token else { return }
                self.errorMessage = "Unable to load \(url.lastPathComponent): \(error.localizedDescription)"
                self.duration = 0
                self.currentTime = 0
            }
        }
    }
    
    func updateGate(_ gate: GateSettings) {
        currentGate = gate
        applyGateToPlayback()
        scheduleGateOverlay(gate: gate)
    }
    
    private func applyGateToPlayback() {
        guard let realtimeGate else { return }
        let profile = DrumProfiles.profile(for: currentClassification)
        realtimeGate.update(settings: currentGate, profile: profile)
    }
    
    func autoGate(from gate: GateSettings, classification: DrumClass? = nil) async -> GateSettings? {
        let token = waveformToken
        guard let data = await fetchWaveformData(), token == waveformToken else { return nil }
        let profile = DrumProfiles.profile(for: classification ?? currentClassification)
        let spectralTask: Task<GateAutoDetector.SpectralSnapshot?, Never>? = {
            guard let url = sourceFile?.url, let profile else { return nil }
            return Task.detached(priority: .userInitiated) {
                GateAutoDetector.spectralSnapshot(from: url, profile: profile)
            }
        }()
        let spectral = await spectralTask?.value
        guard token == waveformToken else { return nil }
        guard let suggestion = GateAutoDetector.suggestSettings(from: data, profile: profile, spectral: spectral) else { return nil }
        var updated = gate
        updated.threshold = suggestion.threshold
        if let suggestedRelease = suggestion.release {
            updated.release = max(updated.release, Float(suggestedRelease))
        } else {
            // Fallback to a generous minimum.
            updated.release = max(updated.release, 0.14)
        }
        if let floor = suggestion.floorDb {
            updated.floorDb = floor
        }
        updated.active = true
        updated.autoApplied = true
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
        guard gate.active else {
            gateRenderTask = nil
            return
        }
        gatedWaveform = nil
        guard let sourceURL = sourceFile?.url else { return }
        
        let cacheKey = GatePreviewCacheKey(url: sourceURL, gate: gate, classification: currentClassification)
        if let cached = gatePreviewCache[cacheKey], FileManager.default.fileExists(atPath: cached.renderedURL.path) {
            applyGatePreview(cached)
            return
        }

        let targetSamples = amplitudes?.count ?? 1_200
        let fallbackOverlay = amplitudes ?? []
        let profile = DrumProfiles.profile(for: currentClassification)
        let previewRate = sourceFile?.processingFormat.sampleRate ?? previewRenderSampleRate(duration: duration)
        
        gateRenderTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard !Task.isCancelled else { return }
            let peaks: [Float]
            let renderResult: GatePreviewResult?
            do {
                renderResult = try GatePreviewLoader.renderPreview(
                    from: sourceURL,
                    gate: gate,
                    targetSamples: targetSamples,
                    renderSampleRate: previewRate,
                    profile: profile
                )
                peaks = renderResult?.peaks ?? []
            } catch {
                print("Gate preview render failed for \(sourceURL.lastPathComponent): \(error.localizedDescription)")
                renderResult = nil
                peaks = fallbackOverlay
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self, token] in
                guard let self, token == self.gateRenderToken else { return }
                if let renderResult {
                    self.applyGatePreview(renderResult)
                    self.gatePreviewCache[cacheKey] = renderResult
                } else {
                    self.applyGateOverlay(peaks: peaks, cacheKey: nil)
                }
            }
        }
    }
    
    private func applyGateOverlay(peaks: [Float], cacheKey: GatePreviewCacheKey?) {
        let overlay: [Float]
        if peaks.count < 2 {
            let count = max(2, amplitudes?.count ?? 2)
            overlay = Array(repeating: 0, count: count)
        } else {
            overlay = peaks
        }
        gatedWaveform = overlay
        if let cacheKey, let gatePreviewURL {
            gatePreviewCache[cacheKey] = GatePreviewResult(peaks: overlay, renderedURL: gatePreviewURL)
        }
    }

    private func applyGatePreview(_ result: GatePreviewResult) {
        // Keep a visible overlay even if the render produced silence.
        if result.peaks.count < 2 {
            let count = max(2, amplitudes?.count ?? 2)
            gatedWaveform = Array(repeating: 0, count: count)
        } else {
            gatedWaveform = result.peaks
        }
        
        if let gatePreviewURL, gatePreviewURL != result.renderedURL {
            if !cachedPreviewURLs.contains(gatePreviewURL) {
                try? FileManager.default.removeItem(at: gatePreviewURL)
            }
        }
        gatePreviewURL = result.renderedURL
        cachedPreviewURLs.insert(result.renderedURL)
    }
    
    private func updatePlaybackTime() {
        guard isPlaying, let nodeTime = player.lastRenderTime else { return }
        guard nodeTime.isSampleTimeValid || nodeTime.isHostTimeValid else { return }
        guard let playerTime = player.playerTime(forNodeTime: nodeTime) else { return }
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
