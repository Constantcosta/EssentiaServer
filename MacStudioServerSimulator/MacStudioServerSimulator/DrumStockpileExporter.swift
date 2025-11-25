//
//  DrumStockpileExporter.swift
//  MacStudioServerSimulator
//
//  Export pipeline for Drum Stockpile items.
//

import Foundation
import AVFoundation
import AVFAudio

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
        var gateProcessor = GateProcessor(
            gate: item.gateSettings,
            sampleRate: Float(targetFormat.sampleRate),
            profile: DrumProfiles.profile(for: item.classification)
        )
        
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
                gateProcessor?.process(buffer: convertedBuffer)
                try writer.write(from: convertedBuffer)
            case .inputRanDry, .error, .endOfStream:
                finished = true
            default:
                break
            }
        }
    }
}

