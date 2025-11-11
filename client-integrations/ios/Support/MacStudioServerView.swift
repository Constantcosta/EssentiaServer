//
//  MacStudioServerView.swift
//  repapp
//
//  Created on 27/10/2025.!
//  Mac Studio Audio Analysis Server GUI
//

import SwiftUI
import Combine

struct MacStudioServerView: View {
    @StateObject private var viewModel = MacStudioServerViewModel()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Dark background for better contrast
                Color(white: 0.05)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Connection Error Alert
                        if let error = viewModel.connectionError {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Connection Error")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                }
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                Text("Make sure the server is running:\ncd mac-studio-server\npython3 analyze_server.py")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.top, 4)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.orange.opacity(0.15))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        
                        // Server Status Card
                        serverStatusCard
                        
                        // Statistics Card
                        statisticsCard
                        
                        // Actions Card
                        actionsCard
                        
                        // Recent Analyses
                        if !viewModel.recentSongs.isEmpty {
                            recentAnalysesCard
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Mac Studio Server")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                viewModel.onAppear()
            }
        }
    }
    
    // MARK: - Server Status Card
    
    private var serverStatusCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: viewModel.isServerRunning ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(viewModel.isServerRunning ? .green : .red)
                
                VStack(alignment: .leading) {
                    Text("Server Status")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(viewModel.isServerRunning ? "Running" : "Offline")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
            
            if let stats = viewModel.serverStats {
                Divider()
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Total Analyses")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("\(stats.totalAnalyses)")
                            .font(.title2)
                            .bold()
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("Cache Hit Rate")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(stats.cacheHitRate)
                            .font(.title2)
                            .bold()
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Statistics Card
    
    private var statisticsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.blue)
                Text("Statistics")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                
                Button(action: {
                    viewModel.refreshStats()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.white)
                }
            }
            
            if let stats = viewModel.serverStats {
                VStack(spacing: 12) {
                    StatRow(label: "Cached Songs", value: "\(stats.totalCachedSongs ?? 0)")
                    StatRow(label: "Cache Hits", value: "\(stats.cacheHits)")
                    StatRow(label: "Cache Misses", value: "\(stats.cacheMisses)")
                    StatRow(label: "Database", value: stats.databasePath?.components(separatedBy: "/").last ?? "Unknown")
                }
            } else {
                Text("Server offline or unreachable")
                    .foregroundColor(.gray)
                    .italic()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Actions Card
    
    private var actionsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.orange)
                Text("Actions")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            
            VStack(spacing: 10) {
                ActionButton(
                    title: "Test Connection",
                    icon: "network",
                    color: .blue,
                    action: {
                        viewModel.testConnection()
                    }
                )
                
                ActionButton(
                    title: "View All Cached Songs",
                    icon: "music.note.list",
                    color: .purple,
                    action: {
                        viewModel.loadAllCachedSongs()
                    }
                )
                
                ActionButton(
                    title: "Export Cache",
                    icon: "square.and.arrow.up",
                    color: .green,
                    action: {
                        viewModel.exportCache()
                    }
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Recent Analyses Card
    
    private var recentAnalysesCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.cyan)
                Text("Recent Analyses")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            
            VStack(spacing: 8) {
                ForEach(viewModel.recentSongs.prefix(10), id: \.title) { song in
                    SongRow(song: song)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Supporting Views

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .foregroundColor(.white)
                .bold()
        }
        .font(.subheadline)
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .padding(.vertical, 8)
        }
    }
}

struct SongRow: View {
    let song: CachedSong
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(song.title)
                .font(.subheadline)
                .foregroundColor(.white)
                .bold()
            HStack {
                Text(song.artist)
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Text("\(Int(song.bpm)) BPM")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text(song.key)
                    .font(.caption)
                    .foregroundColor(.purple)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - View Model

class MacStudioServerViewModel: ObservableObject {
    @Published var isServerRunning = false
    @Published var serverStats: ServerStats?
    @Published var recentSongs: [CachedSong] = []
    @Published var connectionError: String?
    @Published private(set) var lastCheckTimestamp: Date?
    
    // Store the working URL once found
    private var workingURL: String? {
        didSet {
            if let url = workingURL {
                UserDefaults.standard.set(url, forKey: "MacStudioServerWorkingURL")
                print("✅ Saved working URL: \(url)")
            }
        }
    }
    
    // Try multiple connection methods
    private var possibleURLs: [String] {
        var urls: [String] = []
        
        // Priority 1: Last known working URL
        if let savedURL = UserDefaults.standard.string(forKey: "MacStudioServerWorkingURL") {
            urls.append(savedURL)
        }
        
        // Priority 2-4: Standard URLs
        urls.append(contentsOf: [
            "http://127.0.0.1:5050",      // IPv4 localhost
            "http://localhost:5050",       // Standard localhost
            "http://192.168.4.247:5050"   // Network IP (from server logs)
        ])
        
        return urls
    }
    
    private var baseURL: String {
        // Return the working URL if found, otherwise default to IPv4 localhost
        return workingURL ?? possibleURLs.first ?? "http://127.0.0.1:5050"
    }
    
    func onAppear() {
        if UserDefaults.standard.string(forKey: "MacStudioServerWorkingURL") != nil {
            checkServerStatus(allowFallbacks: false)
        } else {
            connectionError = "Server offline. Start the Mac Studio analysis server, then tap “Test Connection”."
        }
    }
    
    func checkServerStatus(allowFallbacks: Bool = true) {
        // Throttle duplicate attempts within 30 seconds
        if let lastCheck = lastCheckTimestamp, Date().timeIntervalSince(lastCheck) < 30 {
            return
        }
        lastCheckTimestamp = Date()
        connectionError = nil
        // Try each possible URL until we find one that works
        let urls: [String]
        if allowFallbacks {
            urls = possibleURLs
        } else if let savedURL = UserDefaults.standard.string(forKey: "MacStudioServerWorkingURL") {
            urls = [savedURL]
        } else {
            connectionError = "Server offline. Start the Mac Studio analysis server, then tap “Test Connection”."
            return
        }
        tryNextURL(urls: urls, index: 0)
    }
    
    private func tryNextURL(urls: [String], index: Int) {
        guard index < urls.count else {
            DispatchQueue.main.async {
                self.isServerRunning = false
                self.connectionError = "Server not reachable on any URL. Make sure the Mac Studio server is running and accessible."
            }
            return
        }
        
        let urlString = urls[index]
        guard let url = URL(string: "\(urlString)/health") else {
            tryNextURL(urls: urls, index: index + 1)
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0 // Increased timeout for iPad network reliability
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if error == nil,
               let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                // Found a working URL!
                DispatchQueue.main.async {
                    self?.workingURL = urlString
                    self?.isServerRunning = true
                    self?.connectionError = nil
                    print("✅ Connected to server at: \(urlString)")
                    self?.refreshStats()
                }
            } else {
                // Try next URL
                self?.tryNextURL(urls: urls, index: index + 1)
            }
        }.resume()
    }
    
    func refreshStats() {
        guard let url = URL(string: "\(baseURL)/stats") else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data, error == nil else { return }
            
            do {
                let stats = try JSONDecoder().decode(ServerStats.self, from: data)
                DispatchQueue.main.async {
                    self?.serverStats = stats
                }
            } catch {
                print("Failed to decode stats: \(error)")
            }
        }.resume()
    }
    
    func testConnection() {
        checkServerStatus(allowFallbacks: true)
        #if os(iOS)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let generator = UINotificationFeedbackGenerator()
            if self.isServerRunning {
                generator.notificationOccurred(.success)
            } else {
                generator.notificationOccurred(.error)
            }
        }
        #endif
    }
    
    func loadAllCachedSongs() {
        guard let url = URL(string: "\(baseURL)/cache/export") else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data, error == nil else { return }
            
            do {
                let response = try JSONDecoder().decode(CacheExportResponse.self, from: data)
                DispatchQueue.main.async {
                    self?.recentSongs = response.songs
                }
            } catch {
                print("Failed to decode cache: \(error)")
            }
        }.resume()
    }
    
    func exportCache() {
        // This would open a share sheet with the exported JSON
        loadAllCachedSongs()
    }
}

// MARK: - Models
// Model definitions moved to ServerModels.swift to avoid duplicate declarations

#Preview {
    MacStudioServerView()
        .preferredColorScheme(.dark)
}
