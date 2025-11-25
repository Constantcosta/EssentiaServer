//
//  MacStudioServerManager.swift
//  repapp
//
//  Created on 29/10/2025.
//  iOS client for Mac Studio Audio Analysis Server
//  Note: iOS apps cannot launch external processes - server must be started manually on Mac Studio
//

import Foundation
import Combine

// SUMMARY
// ObservableObject client for the external Mac Studio audio-analysis server.
// Tracks server status/cache, wraps REST endpoints (health, stats, cache ops),
// and reminds users to manually run the Python service.

@MainActor
class MacStudioServerManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isServerRunning = false
    @Published var serverStats: ServerStats?
    @Published var cachedAnalyses: [CachedAnalysis] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var serverPort = 5050
    
    // MARK: - Constants
    
    private let apiKey = "8sxO1R8TM3Jv9AVyzbh-Kej0xYKrHWj87CLHRTufHv0"
    
    private var baseURL: String {
        #if targetEnvironment(simulator)
        return "http://127.0.0.1:\(serverPort)"
        #else
        return "http://Costass-Mac-Studio.local:\(serverPort)"
        #endif
    }
    
    // MARK: - Server Control
    // Note: iOS apps cannot launch external processes
    // The Python server must be started manually on the Mac Studio
    
    func startServer() async {
        isLoading = true
        errorMessage = "⚠️ iOS apps cannot start external servers.\n\nPlease start the server manually on your Mac Studio:\n\n1. Open Terminal on Mac Studio\n2. cd ~/Documents/Git\\ repo/Songwise\\ 1/mac-studio-server/\n3. python3 analyze_server.py\n\nThen tap 'Check Status' to verify connection."
        isLoading = false
        
        // Still check if server is already running
        await checkServerStatus()
    }
    
    func stopServer() async {
        isLoading = true
        errorMessage = nil
        
        // Try to shutdown via API
        do {
            guard let url = URL(string: "\(baseURL)/shutdown") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 5
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            
            let (_, _) = try await URLSession.shared.data(for: request)
            isServerRunning = false
        } catch {
            errorMessage = "Failed to stop server: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func restartServer() async {
        await stopServer()
        try? await Task.sleep(for: .seconds(1))
        await checkServerStatus()
    }
    
    // MARK: - Server Status
    
    func checkServerStatus() async {
        do {
            guard let url = URL(string: "\(baseURL)/health") else { return }
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            let (data, _) = try await URLSession.shared.data(for: request)
            let status = try JSONDecoder().decode(ServerStatus.self, from: data)
            isServerRunning = status.running
        } catch {
            isServerRunning = false
        }
    }
    
    // MARK: - Statistics
    
    func fetchServerStats() async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let url = URL(string: "\(baseURL)/stats") else { return }
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            let (data, _) = try await URLSession.shared.data(for: request)
            serverStats = try JSONDecoder().decode(ServerStats.self, from: data)
            isLoading = false
        } catch {
            errorMessage = "Failed to fetch stats: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    // MARK: - Cache Management
    
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
    
    func clearAllCache() async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let url = URL(string: "\(baseURL)/cache/clear") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            
            let (_, _) = try await URLSession.shared.data(for: request)
            
            cachedAnalyses.removeAll()
            isLoading = false
        } catch {
            errorMessage = "Failed to clear cache: \(error.localizedDescription)"
            isLoading = false
        }
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
