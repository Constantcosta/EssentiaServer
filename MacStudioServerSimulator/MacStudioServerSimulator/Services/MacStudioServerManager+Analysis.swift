import Foundation
import Combine
import AVFoundation
import UniformTypeIdentifiers
import OSLog
#if os(macOS)
import AppKit
#endif

extension MacStudioServerManager {
    // MARK: - File helpers
    
    struct AudioMetadata {
        let title: String
        let artist: String
    }
    
    nonisolated static func loadAudioData(from fileURL: URL) throws -> Data {
        try Data(contentsOf: fileURL)
    }
    
    nonisolated func inferredMetadata(for fileURL: URL) async -> AudioMetadata {
        // Best-effort read of common metadata; fall back to filename.
        let asset = AVURLAsset(url: fileURL)
        var title = fileURL.deletingPathExtension().lastPathComponent
        var artist = ""
        
        do {
            let metadata = try await asset.load(.metadata)
            for item in metadata {
                guard let value = try await item.load(.value) as? String else { continue }
                switch item.commonKey?.rawValue {
                case "title":
                    title = value
                case "artist":
                    artist = value
                default:
                    break
                }
            }
        } catch {
            // Fall back to filename if metadata loading fails
        }
        
        return AudioMetadata(title: title, artist: artist)
    }
    
    nonisolated func contentType(for fileURL: URL) -> String {
        if let type = UTType(filenameExtension: fileURL.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "audio/mpeg"
    }

// MARK: - Audio Analysis
    
    nonisolated func analyzeAudioFile(
        at fileURL: URL,
        skipChunkAnalysis: Bool = false,
        forceFreshAnalysis: Bool = false,
        cacheNamespace: String? = nil,
        requestTimeout: TimeInterval? = nil,
        titleOverride: String? = nil,
        artistOverride: String? = nil,
        clientRequestId: String? = nil
    ) async throws -> AnalysisResult {
        // Ensure the analyzer is running. If it's offline, ask the manager
        // to auto-start it so callers (Repertoire, Quick Analyze, calibration)
        // don't have to manage server lifecycle manually.
        var serverRunning = await MainActor.run { isServerRunning }
        if !serverRunning {
            await autoStartServerIfNeeded(autoManageEnabled: true, overrideUserStop: true)
            serverRunning = await MainActor.run { isServerRunning }
        }
        guard serverRunning else {
            throw AudioAnalysisError.serverOffline
        }
        
        let baseURLString = await MainActor.run { baseURL }
        guard let requestURL = URL(string: "\(baseURLString)/analyze_data") else {
            throw URLError(.badURL)
        }
        
        let fileData: Data
        do {
            fileData = try Self.loadAudioData(from: fileURL)
        } catch {
            throw error
        }
        
        guard !fileData.isEmpty else {
            throw AudioAnalysisError.emptyFile
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.httpBody = fileData
        // Use a generous default for full tracks, but allow callers
        // (e.g. 30s previews in the Repertoire tab) to specify a
        // shorter per-request timeout.
        request.timeoutInterval = requestTimeout ?? 900  // seconds
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        let metadata: AudioMetadata
        if let titleOverride, let artistOverride {
            metadata = AudioMetadata(title: titleOverride, artist: artistOverride)
        } else {
            metadata = await inferredMetadata(for: fileURL)
        }
        let apiKeyValue = await MainActor.run { apiKey }
        
        request.setValue(metadata.title, forHTTPHeaderField: "X-Song-Title")
        request.setValue(metadata.artist, forHTTPHeaderField: "X-Song-Artist")
        request.setValue(apiKeyValue, forHTTPHeaderField: "X-API-Key")
        request.setValue(contentType(for: fileURL), forHTTPHeaderField: "Content-Type")
        if let clientRequestId, !clientRequestId.isEmpty {
            request.setValue(clientRequestId, forHTTPHeaderField: "X-Client-Request-Id")
        }
        if skipChunkAnalysis {
            request.setValue("1", forHTTPHeaderField: "X-Skip-Chunk-Analysis")
        }
        if forceFreshAnalysis {
            request.setValue("1", forHTTPHeaderField: "X-Force-Reanalyze")
        }
        if let cacheNamespace, !cacheNamespace.isEmpty {
            request.setValue(cacheNamespace, forHTTPHeaderField: "X-Cache-Namespace")
        }
        
        // Perform the actual network call - now truly concurrent!
        return try await performNetworkRequest(request)
    }
    
    // This helper runs off the main actor, allowing true concurrent network requests
    nonisolated private func performNetworkRequest(_ request: URLRequest) async throws -> AnalysisResult {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AudioAnalysisError.serverError(
                status: httpResponse.statusCode,
                message: String(data: data, encoding: .utf8)
            )
        }
        
        return try JSONDecoder().decode(AnalysisResult.self, from: data)
    }
    
    func analyzeBatchFiles(
        _ fileURLs: [URL],
        skipChunkAnalysis: Bool = false,
        forceFreshAnalysis: Bool = false,
        cacheNamespace: String? = nil
    ) async throws -> [AnalysisResult] {
        guard isServerRunning else {
            throw AudioAnalysisError.serverOffline
        }
        
        guard let requestURL = URL(string: "\(baseURL)/analyze_batch") else {
            throw URLError(.badURL)
        }
        
        // Prepare batch payload
        var batchItems: [[String: String]] = []
        
        for fileURL in fileURLs {
            let fileData = try Self.loadAudioData(from: fileURL)
            let base64Audio = fileData.base64EncodedString()
            let metadata = await inferredMetadata(for: fileURL)
            
            batchItems.append([
                "audio_data": base64Audio,
                "title": metadata.title,
                "artist": metadata.artist
            ])
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 900 // 15 minutes for batch (6 songs × ~2.5 min each)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        if skipChunkAnalysis {
            request.setValue("1", forHTTPHeaderField: "X-Skip-Chunk-Analysis")
        }
        if forceFreshAnalysis {
            request.setValue("1", forHTTPHeaderField: "X-Force-Reanalyze")
        }
        if let cacheNamespace, !cacheNamespace.isEmpty {
            request.setValue(cacheNamespace, forHTTPHeaderField: "X-Cache-Namespace")
        }
        
        request.httpBody = try JSONEncoder().encode(batchItems)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AudioAnalysisError.serverError(
                status: httpResponse.statusCode,
                message: String(data: data, encoding: .utf8)
            )
        }
        
        return try JSONDecoder().decode([AnalysisResult].self, from: data)
    }
    
    func analyzeAudio(url: String, title: String, artist: String) async throws -> AnalysisResult {
        guard let requestURL = URL(string: "\(baseURL)/analyze") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        
        let body: [String: String] = [
            "url": url,
            "title": title,
            "artist": artist
        ]
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw URLError(.init(rawValue: httpResponse.statusCode))
        }
        
        let result = try JSONDecoder().decode(AnalysisResult.self, from: data)
        return result
    }
    
    func exportCache(limit: Int = 5000, offset: Int = 0) async throws -> URL {
        guard let requestURL = URL(string: "\(baseURL)/cache/export?limit=\(limit)&offset=\(offset)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AudioAnalysisError.serverError(status: httpResponse.statusCode, message: message)
        }
        
        let filename = suggestedFilename(from: httpResponse) ?? "cache_export.csv"
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: destination, options: .atomic)
        return destination
    }
    
    func quickAnalyzeFile(_ fileURL: URL) async {
        do {
            let result = try await analyzeAudioFile(at: fileURL)
            let entry = QuickAnalyzeResultEntry(fileName: fileURL.lastPathComponent, result: result)
            quickAnalyzeHistory.insert(entry, at: 0)
            if quickAnalyzeHistory.count > 12 {
                quickAnalyzeHistory = Array(quickAnalyzeHistory.prefix(12))
            }
            quickAnalyzeErrors.removeAll { $0.fileName == entry.fileName }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let dropError = DropErrorEntry(fileName: fileURL.lastPathComponent, message: message)
            quickAnalyzeErrors.removeAll { $0.fileName == dropError.fileName }
            quickAnalyzeErrors.append(dropError)
        }
    }

}
