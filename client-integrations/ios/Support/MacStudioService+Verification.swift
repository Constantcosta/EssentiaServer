import Foundation
import Combine

extension MacStudioService {
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

}
