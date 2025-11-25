import Foundation
import Combine

extension MacStudioService {
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

}
