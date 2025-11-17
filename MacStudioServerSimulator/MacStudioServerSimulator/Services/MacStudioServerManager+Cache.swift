import Foundation
import Combine
import AVFoundation
import UniformTypeIdentifiers
import OSLog
#if os(macOS)
import AppKit
#endif

extension MacStudioServerManager {
// MARK: - Cache Management
    
    func refreshCacheList(limit: Int = 100, offset: Int = 0, showLoadingIndicator: Bool = true) async {
        await fetchCachedAnalyses(limit: limit, offset: offset, showLoadingIndicator: showLoadingIndicator)
    }
    
    func fetchCachedAnalyses(limit: Int = 100, offset: Int = 0, showLoadingIndicator: Bool = true) async {
        if showLoadingIndicator {
            isLoading = true
        }
        errorMessage = nil
        
        defer {
            if showLoadingIndicator {
                isLoading = false
            }
        }
        
        do {
            guard let url = URL(string: "\(baseURL)/cache?limit=\(limit)&offset=\(offset)") else { return }
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            let (data, _) = try await URLSession.shared.data(for: request)
            cachedAnalyses = try JSONDecoder().decode([CachedAnalysis].self, from: data)
        } catch {
            errorMessage = "Failed to fetch cache: \(error.localizedDescription)"
        }
    }
    
    func searchCache(query: String, showLoadingIndicator: Bool = true) async {
        if showLoadingIndicator {
            isLoading = true
        }
        errorMessage = nil
        
        defer {
            if showLoadingIndicator {
                isLoading = false
            }
        }
        
        do {
            guard let url = URL(string: "\(baseURL)/cache/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else { return }
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            let (data, _) = try await URLSession.shared.data(for: request)
            cachedAnalyses = try JSONDecoder().decode([CachedAnalysis].self, from: data)
        } catch {
            errorMessage = "Failed to search cache: \(error.localizedDescription)"
        }
    }
    
    func deleteFromCache(id: Int) async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let url = URL(string: "\(baseURL)/cache/\(id)") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            
            let (_, _) = try await URLSession.shared.data(for: request)
            
            // Remove from local array
            cachedAnalyses.removeAll { $0.id == id }
            isLoading = false
        } catch {
            errorMessage = "Failed to delete: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    func clearCache(namespace: String? = nil, showLoadingIndicator: Bool = true) async {
        if showLoadingIndicator {
            isLoading = true
        }
        errorMessage = nil
        
        defer {
            if showLoadingIndicator {
                isLoading = false
            }
        }
        
        do {
            guard var components = URLComponents(string: "\(baseURL)/cache/clear") else { return }
            if let namespace, !namespace.isEmpty {
                components.queryItems = [URLQueryItem(name: "namespace", value: namespace)]
            }
            guard let url = components.url else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            
            let (_, _) = try await URLSession.shared.data(for: request)
            
            if namespace == nil || namespace?.isEmpty == true || namespace == "default" {
                cachedAnalyses.removeAll()
            }
        } catch {
            errorMessage = "Failed to clear cache: \(error.localizedDescription)"
        }
    }
    
    func clearAllCache() async {
        await clearCache()
    }
    
    


// MARK: - Database Info
    
    func getDatabaseInfo() async -> (size: String, location: String, itemCount: Int) {
        // Note: Database is on Mac Studio, not on iOS device
        // This info comes from server stats
        let location = serverStats?.databasePath ?? "On Mac Studio"
        let size = "See server stats"
        let itemCount = serverStats?.totalCachedSongs ?? cachedAnalyses.count
        
        return (size: size, location: location, itemCount: itemCount)
    }

}
