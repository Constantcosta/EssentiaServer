//
//  ServerManagementLogStore.swift
//  MacStudioServerSimulator
//

import Foundation
import Combine

@MainActor
final class LogStore: ObservableObject {
    @Published var logContent: String = "Loading log…"
    @Published var autoRefresh = false {
        didSet { configureTimer() }
    }
    @Published var lastUpdate: Date?
    @Published var logFileSize: Int64 = 0
    
    private var refreshCancellable: AnyCancellable?
    private let logURL: URL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Music/AudioAnalysisCache/server.log")
    private let linesToKeep = 1000  // Show more lines for better context
    private var lastFilePosition: Int = 0
    
    func loadLogs() {
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            logContent = "⚠️ Log file not found at \(logURL.path)\n\nThe server may not be running or hasn't logged anything yet."
            return
        }
        
        // Get file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
           let size = attrs[.size] as? Int64 {
            logFileSize = size
        }
        
        guard let data = try? String(contentsOf: logURL) else {
            logContent = "❌ Failed to read log file"
            return
        }
        
        let lines = data.split(whereSeparator: \.isNewline)
        let tail = lines.suffix(linesToKeep)
        logContent = tail.joined(separator: "\n")
        
        if logContent.isEmpty {
            logContent = "📝 Log is currently empty"
        }
        
        lastUpdate = Date()
    }
    
    func clearLogs() {
        do {
            try "".write(to: logURL, atomically: true, encoding: .utf8)
            logContent = "(Log cleared)"
        } catch {
            logContent = "Failed to clear log: \(error.localizedDescription)"
        }
    }
    
    private func configureTimer() {
        refreshCancellable?.cancel()
        guard autoRefresh else { return }
        // Refresh every 1 second when auto-refresh is on for near real-time updates
        refreshCancellable = Timer
            .publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.loadLogs()
                }
            }
    }
    
    deinit {
        refreshCancellable?.cancel()
    }
}
