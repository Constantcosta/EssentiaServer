import Foundation
import Combine

extension MacStudioService {
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

}
