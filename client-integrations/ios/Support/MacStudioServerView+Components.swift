//
//  MacStudioServerView+Components.swift
//

import SwiftUI
import Combine

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label.uppercased())
                .font(.caption)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.headline)
                .foregroundColor(.white)
        }
    }
}

struct ActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(color.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(color.opacity(0.4), lineWidth: 1)
                    )
            )
        }
    }
}

struct SongRow: View {
    let title: String
    let artist: String
    let bpm: Int
    let confidence: Int
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(artist)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(bpm) BPM")
                    .font(.headline)
                    .foregroundColor(.green)
                Text("\(confidence)% conf.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.1))
        )
    }
}

class MacStudioServerViewModel: ObservableObject {
    @Published var isServerRunning = false
    @Published var connectionError: String?
    @Published var serverStats: ServerStats?
    @Published var recentSongs: [RecentSong] = []
    
    func onAppear() {
        fetchServerStatus()
        fetchServerStats()
        fetchRecentSongs()
    }
    
    func refreshStats() {
        fetchServerStats()
        fetchRecentSongs()
    }
    
    private func fetchServerStatus() {
        MacStudioService.shared.checkHealth { [weak self] isHealthy in
            DispatchQueue.main.async {
                self?.isServerRunning = isHealthy
                self?.connectionError = isHealthy ? nil : "Cannot connect to the Mac Studio server. Make sure your Mac Studio is running analyze_server.py."
            }
        }
    }
    
    private func fetchServerStats() {
        Task { @MainActor in
            do {
                let stats = try await MacStudioService.shared.fetchStats()
                serverStats = stats
            } catch {
                connectionError = error.localizedDescription
            }
        }
    }
    
    private func fetchRecentSongs() {
        Task { @MainActor in
            let samples = [
                RecentSong(title: "Hot In It", artist: "Tiësto", bpm: 125, confidence: 92),
                RecentSong(title: "Underwater", artist: "RÜFÜS DU SOL", bpm: 122, confidence: 88),
                RecentSong(title: "Rumble", artist: "Skrillex & Fred again..", bpm: 140, confidence: 95)
            ]
            recentSongs = samples
        }
    }
}

struct RecentSong: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let bpm: Int
    let confidence: Int
}
