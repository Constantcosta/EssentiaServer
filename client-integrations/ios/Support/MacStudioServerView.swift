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
                        Text(stats.cacheHitRateFormatted)
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
