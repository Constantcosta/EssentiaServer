//
//  ContentView.swift
//  MacStudioServerSimulator
//
//  Main view for testing the Mac Studio Server
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var serverManager: MacStudioServerManager
    
    var body: some View {
        NavigationView {
            List {
                Section("Server Connection") {
                    ServerConnectionView()
                }
                
                Section("Test Features") {
                    NavigationLink("Audio Analysis Test") {
                        ServerTestView()
                    }
                    
                    NavigationLink("Phase 1 Features Test") {
                        Phase1FeaturesTestView()
                    }
                }
                
                Section("Server Info") {
                    if let stats = serverManager.serverStats {
                        LabeledContent("Total Analyses", value: "\(stats.totalAnalyses)")
                        LabeledContent("Cache Hits", value: "\(stats.cacheHits)")
                        LabeledContent("Cache Misses", value: "\(stats.cacheMisses)")
                        LabeledContent("Hit Rate", value: String(format: "%.1f%%", stats.cacheHitRate * 100))
                    } else {
                        Text("Connect to server to view stats")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Server Simulator")
            .refreshable {
                await serverManager.checkServerStatus()
            }
        }
    }
}

struct ServerConnectionView: View {
    @EnvironmentObject var serverManager: MacStudioServerManager
    @State private var portString = "5050"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Status:")
                    .font(.headline)
                Circle()
                    .fill(serverManager.isServerRunning ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                Text(serverManager.isServerRunning ? "Connected" : "Disconnected")
                    .foregroundColor(serverManager.isServerRunning ? .green : .red)
            }
            
            HStack {
                TextField("Port", text: $portString)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onChange(of: portString) { oldValue, newValue in
                        if let port = Int(newValue) {
                            serverManager.serverPort = port
                        }
                    }
                
                Button("Check Status") {
                    Task {
                        await serverManager.checkServerStatus()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(serverManager.isLoading)
            }
            
            if let error = serverManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(nil)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    ContentView()
        .environmentObject(MacStudioServerManager())
}
