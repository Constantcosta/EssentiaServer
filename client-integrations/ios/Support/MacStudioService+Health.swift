import Foundation
import Combine

extension MacStudioService {
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

}
