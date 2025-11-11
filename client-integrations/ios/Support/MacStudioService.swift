//
//  MacStudioService.swift
//  repapp
//
//  Created on 27/10/2025.
//  Service layer for Mac Studio Audio Analysis Server integration
//

import Foundation

/// Service for communicating with Mac Studio Audio Analysis Server
class MacStudioService {
    
    // MARK: - Configuration
    
    static let shared = MacStudioService()
    
    private var baseURL: String {
        #if targetEnvironment(simulator)
        // Use explicit IPv4 address to avoid IPv6 connection issues
        return "http://127.0.0.1:5050"
        #else
        // For device: use Mac's actual hostname (Bonjour/mDNS)
        // If this doesn't work, user should update to their Mac's actual hostname
        // Run `hostname` in Terminal on Mac to find it
        return "http://Costass-Mac-Studio.local:5050"
        #endif
    }
    
    // Fallback URLs to try if primary fails
    private let fallbackURLs: [String] = [
        "http://192.168.4.247:5050",  // Direct IP (fastest if on same network)
        "http://Costass-Mac-Studio.local:5050",  // mDNS hostname
        "http://127.0.0.1:5050"  // localhost (works if on same machine)
    ]
    
    // Persist the last URL that succeeded so we prefer it on future requests
    private let resolvedURLQueue = DispatchQueue(label: "app.songwise.macstudio.baseurl", qos: .utility)
    private var resolvedBaseURLValue: String?
    
    private func preferredBaseURLs() -> [String] {
        var urls: [String] = []
        
        resolvedURLQueue.sync {
            if let resolved = resolvedBaseURLValue {
                urls.append(resolved)
            }
        }
        
        // Add the platform-specific default followed by the static fallbacks
        for candidate in [baseURL] + fallbackURLs {
            if !urls.contains(candidate) {
                urls.append(candidate)
            }
        }
        
        return urls
    }
    
    private func updateResolvedBaseURL(_ url: String) {
        resolvedURLQueue.async {
            self.resolvedBaseURLValue = url
        }
    }
    
    // MARK: - Models
    
    struct AnalysisRequest: Codable {
        let url: String
        let title: String
        let artist: String
    }
    
    struct AnalysisResult: Codable {
        let bpm: Double
        let bpmConfidence: Double
        let key: String
        let keyConfidence: Double
        let energy: Double
        let danceability: Double
        let acousticness: Double
        let spectralCentroid: Double
        let cached: Bool
        let analysisDuration: Double?
        let analyzedAt: String?
        
        enum CodingKeys: String, CodingKey {
            case bpm
            case bpmConfidence = "bpm_confidence"
            case key
            case keyConfidence = "key_confidence"
            case energy, danceability, acousticness
            case spectralCentroid = "spectral_centroid"
            case cached
            case analysisDuration = "analysis_duration"
            case analyzedAt = "analyzed_at"
        }
        
        // MARK: - NaN-Safe Accessors (Critical for iPad stability)
        
        /// Safe BPM value that never returns NaN - returns 0 if invalid
        var safeBPM: Double {
            guard !bpm.isNaN, bpm.isFinite, bpm > 0, bpm < 500 else { return 0 }
            return bpm
        }
        
        /// Safe confidence values (0-1 range)
        var safeBPMConfidence: Double {
            guard !bpmConfidence.isNaN, bpmConfidence.isFinite else { return 0 }
            return max(0, min(1, bpmConfidence))
        }
        
        var safeKeyConfidence: Double {
            guard !keyConfidence.isNaN, keyConfidence.isFinite else { return 0 }
            return max(0, min(1, keyConfidence))
        }
        
        /// Safe audio features (0-1 range)
        var safeEnergy: Double {
            guard !energy.isNaN, energy.isFinite else { return 0 }
            return max(0, min(1, energy))
        }
        
        var safeDanceability: Double {
            guard !danceability.isNaN, danceability.isFinite else { return 0 }
            // Clamp to 0-1 range (server may return negative values from librosa)
            return max(0, min(1, danceability))
        }
        
        var safeAcousticness: Double {
            guard !acousticness.isNaN, acousticness.isFinite else { return 0 }
            return max(0, min(1, acousticness))
        }
        
        /// Validate all numeric fields are valid (not NaN or infinite)
        /// Note: Some values like danceability may be negative (librosa quirk), which is OK
        var isValid: Bool {
            return !bpm.isNaN && bpm.isFinite && bpm > 0 &&
                   !bpmConfidence.isNaN && bpmConfidence.isFinite &&
                   !keyConfidence.isNaN && keyConfidence.isFinite &&
                   !energy.isNaN && energy.isFinite &&
                   !danceability.isNaN && danceability.isFinite &&
                   !acousticness.isNaN && acousticness.isFinite
        }
    }
    
    // MARK: - Server Health
    
    /// Check if server is available
    func checkHealth(completion: @escaping (Bool) -> Void) {
        // Try resolved URL first, then fallbacks (IP first for best performance)
        tryHealthCheckWithFallbacks(urls: preferredBaseURLs(), index: 0, completion: completion)
    }
    
    /// Try multiple URLs in sequence until one succeeds
    private func tryHealthCheckWithFallbacks(urls: [String], index: Int, completion: @escaping (Bool) -> Void) {
        guard index < urls.count else {
            print("❌ All server URLs failed")
            completion(false)
            return
        }
        
        let url = "\(urls[index])/health"
        print("🔍 Trying server at: \(url)")
        
        tryHealthCheck(url: url) { success in
            if success {
                print("✅ Connected to server at: \(urls[index])")
                self.updateResolvedBaseURL(urls[index])
                completion(true)
            } else {
                // Try next URL
                self.tryHealthCheckWithFallbacks(urls: urls, index: index + 1, completion: completion)
            }
        }
    }
    
    private func tryHealthCheck(url: String, completion: @escaping (Bool) -> Void) {
        guard let healthURL = URL(string: url) else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 3.0 // Shorter timeout for faster fallback
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Health check failed for \(url): \(error.localizedDescription)")
            }
            let isHealthy = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
            if isHealthy {
                print("✅ Health check succeeded: \(url)")
            }
            DispatchQueue.main.async {
                completion(isHealthy)
            }
        }.resume()
    }
    
    // MARK: - Request Handling
    
    private func performRequest(
        path: String,
        method: String,
        body: Data?,
        headers: [String: String],
        timeout: TimeInterval,
        completion: @escaping (Result<(Data, HTTPURLResponse, String), Error>) -> Void
    ) {
        let urls = preferredBaseURLs()
        attemptRequest(
            urls: urls,
            index: 0,
            path: path,
            method: method,
            body: body,
            headers: headers,
            timeout: timeout,
            lastError: nil,
            completion: completion
        )
    }
    
    private func attemptRequest(
        urls: [String],
        index: Int,
        path: String,
        method: String,
        body: Data?,
        headers: [String: String],
        timeout: TimeInterval,
        lastError: Error?,
        completion: @escaping (Result<(Data, HTTPURLResponse, String), Error>) -> Void
    ) {
        guard index < urls.count else {
            let fallbackError = lastError ?? NSError(
                domain: "MacStudioService",
                code: -1004,
                userInfo: [NSLocalizedDescriptionKey: "All Mac Studio endpoints failed for \(path)"]
            )
            completion(.failure(fallbackError))
            return
        }
        
        let base = urls[index]
        let urlString = "\(base)\(path)"
        
        guard let url = URL(string: urlString) else {
            let error = NSError(
                domain: "MacStudioService",
                code: -1000,
                userInfo: [NSLocalizedDescriptionKey: "Invalid URL constructed for \(urlString)"]
            )
            attemptRequest(
                urls: urls,
                index: index + 1,
                path: path,
                method: method,
                body: body,
                headers: headers,
                timeout: timeout,
                lastError: error,
                completion: completion
            )
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = body
        
        print("🌐 MacStudio: \(method) \(urlString)")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ MacStudio: \(method) \(urlString) failed - \(error.localizedDescription)")
                self.attemptRequest(
                    urls: urls,
                    index: index + 1,
                    path: path,
                    method: method,
                    body: body,
                    headers: headers,
                    timeout: timeout,
                    lastError: error,
                    completion: completion
                )
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                let error = NSError(
                    domain: "MacStudioService",
                    code: -1001,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid response from \(urlString)"]
                )
                print("❌ MacStudio: \(method) \(urlString) failed - \(error.localizedDescription)")
                self.attemptRequest(
                    urls: urls,
                    index: index + 1,
                    path: path,
                    method: method,
                    body: body,
                    headers: headers,
                    timeout: timeout,
                    lastError: error,
                    completion: completion
                )
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let message = data.flatMap { String(data: $0, encoding: .utf8) } ??
                    HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                let error = NSError(
                    domain: "MacStudioService",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Status \(httpResponse.statusCode) from \(urlString): \(message)"]
                )
                print("❌ MacStudio: \(method) \(urlString) failed - \(error.localizedDescription)")
                self.attemptRequest(
                    urls: urls,
                    index: index + 1,
                    path: path,
                    method: method,
                    body: body,
                    headers: headers,
                    timeout: timeout,
                    lastError: error,
                    completion: completion
                )
                return
            }
            
            let responseData = data ?? Data()
            self.updateResolvedBaseURL(base)
            completion(.success((responseData, httpResponse, base)))
        }.resume()
    }
    
    // MARK: - Audio Analysis
    
    /// Analyze a song's preview URL
    /// - Parameters:
    ///   - previewURL: Apple Music preview URL
    ///   - title: Song title
    ///   - artist: Artist name
    ///   - completion: Returns analysis result or error
    func analyzeSong(
        previewURL: String,
        title: String,
        artist: String,
        completion: @escaping (Result<AnalysisResult, Error>) -> Void
    ) {
        let requestData = AnalysisRequest(url: previewURL, title: title, artist: artist)
        
        do {
            let body = try JSONEncoder().encode(requestData)
            
            performRequest(
                path: "/analyze",
                method: "POST",
                body: body,
                headers: ["Content-Type": "application/json"],
                timeout: 30.0
            ) { result in
                switch result {
                case .success(let (data, _, baseURL)):
                    do {
                        let analysis = try JSONDecoder().decode(AnalysisResult.self, from: data)
                        
                        if !analysis.isValid {
                            print("⚠️ Analysis result contains invalid (NaN/Infinite) values from \(baseURL)")
                            print("   BPM: \(analysis.bpm), Energy: \(analysis.energy), Danceability: \(analysis.danceability)")
                            let error = NSError(
                                domain: "MacStudioService",
                                code: -3,
                                userInfo: [NSLocalizedDescriptionKey: "Server returned invalid analysis data (NaN values)"]
                            )
                            DispatchQueue.main.async {
                                completion(.failure(error))
                            }
                            return
                        }
                        
                        DispatchQueue.main.async {
                            completion(.success(analysis))
                        }
                    } catch {
                        print("❌ Failed to decode analysis result: \(error)")
                        DispatchQueue.main.async {
                            completion(.failure(error))
                        }
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Async/Await Interface (iOS 15+)
    
    @available(iOS 15.0, *)
    func analyzeSong(previewURL: String, title: String, artist: String) async throws -> AnalysisResult {
        try await withCheckedThrowingContinuation { continuation in
            analyzeSong(previewURL: previewURL, title: title, artist: artist) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    /// Analyze audio data directly (for Apple Music previews that require iOS authentication)
    /// Downloads audio in iOS app, then sends data to Mac Studio server
    @available(iOS 15.0, *)
    func analyzeAudioData(audioData: Data, title: String, artist: String) async throws -> AnalysisResult {
        var lastError: Error?
        
        for base in preferredBaseURLs() {
            guard let url = URL(string: "\(base)/analyze_data") else {
                continue
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue(title, forHTTPHeaderField: "X-Song-Title")
            request.setValue(artist, forHTTPHeaderField: "X-Song-Artist")
            request.httpBody = audioData
            
            do {
                print("🌐 MacStudio: POST \(url.absoluteString) (\(audioData.count) bytes)")
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "MacStudioService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from \(url.absoluteString)"])
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    let errorMessage = String(data: data, encoding: .utf8) ??
                        HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                    throw NSError(
                        domain: "MacStudioService",
                        code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "Status \(httpResponse.statusCode) from \(url.absoluteString): \(errorMessage)"]
                    )
                }
                
                updateResolvedBaseURL(base)
                
                let decoder = JSONDecoder()
                let result = try decoder.decode(AnalysisResult.self, from: data)
                
                guard result.isValid else {
                    print("⚠️ Analysis result contains invalid (NaN/Infinite) values from \(base)")
                    print("   BPM: \(result.bpm), Energy: \(result.energy), Danceability: \(result.danceability)")
                    throw NSError(
                        domain: "MacStudioService",
                        code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "Server returned invalid analysis data (NaN values)"]
                    )
                }
                
                return result
            } catch {
                print("❌ MacStudio: POST \(url.absoluteString) failed - \(error.localizedDescription)")
                lastError = error
                continue
            }
        }
        
        throw lastError ?? NSError(
            domain: "MacStudioService",
            code: -1004,
            userInfo: [NSLocalizedDescriptionKey: "All Mac Studio endpoints failed for /analyze_data"]
        )
    }
    
    @available(iOS 15.0, *)
    func checkHealth() async -> Bool {
        await withCheckedContinuation { continuation in
            checkHealth { isHealthy in
                continuation.resume(returning: isHealthy)
            }
        }
    }
    
    // MARK: - Manual Verification
    
    struct VerificationRequest: Codable {
        let url: String
        let manualBpm: Double?
        let manualKey: String?
        let bpmNotes: String?
        
        enum CodingKeys: String, CodingKey {
            case url
            case manualBpm = "manual_bpm"
            case manualKey = "manual_key"
            case bpmNotes = "bpm_notes"
        }
    }
    
    /// Submit manual verification/correction for a song
    func verifySong(
        previewURL: String,
        manualBpm: Double? = nil,
        manualKey: String? = nil,
        notes: String? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let requestData = VerificationRequest(
            url: previewURL,
            manualBpm: manualBpm,
            manualKey: manualKey,
            bpmNotes: notes
        )
        
        do {
            let body = try JSONEncoder().encode(requestData)
            performRequest(
                path: "/verify",
                method: "POST",
                body: body,
                headers: ["Content-Type": "application/json"],
                timeout: 10.0
            ) { result in
                switch result {
                case .success:
                    DispatchQueue.main.async {
                        completion(.success(()))
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }
}

// MARK: - SwiftUI Integration Helper

import SwiftUI

/// View modifier to integrate Mac Studio analysis
struct MacStudioAnalysisModifier: ViewModifier {
    let previewURL: String
    let title: String
    let artist: String
    @Binding var analysisResult: MacStudioService.AnalysisResult?
    @Binding var isAnalyzing: Bool
    @State private var error: Error?
    
    func body(content: Content) -> some View {
        content
            .task {
                await performAnalysis()
            }
    }
    
    @available(iOS 15.0, *)
    private func performAnalysis() async {
        isAnalyzing = true
        do {
            let result = try await MacStudioService.shared.analyzeSong(
                previewURL: previewURL,
                title: title,
                artist: artist
            )
            analysisResult = result
        } catch {
            self.error = error
            print("Analysis failed: \(error.localizedDescription)")
        }
        isAnalyzing = false
    }
}

extension View {
    /// Automatically analyze a song when view appears
    func macStudioAnalysis(
        previewURL: String,
        title: String,
        artist: String,
        result: Binding<MacStudioService.AnalysisResult?>,
        isAnalyzing: Binding<Bool>
    ) -> some View {
        modifier(MacStudioAnalysisModifier(
            previewURL: previewURL,
            title: title,
            artist: artist,
            analysisResult: result,
            isAnalyzing: isAnalyzing
        ))
    }
}
