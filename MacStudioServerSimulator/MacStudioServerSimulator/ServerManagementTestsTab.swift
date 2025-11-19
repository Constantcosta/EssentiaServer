//
//  ServerManagementTestsTab.swift
//  MacStudioServerSimulator
//
//  Tests tab: ABCD test suite + Repertoire comparison view.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TestsTab: View {
    @ObservedObject var manager: MacStudioServerManager
    @StateObject private var testRunner = ABCDTestRunner()
    @State private var selectedMode: TestsTabMode = .repertoire
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $selectedMode) {
                Label("ABCD Tests", systemImage: "checklist").tag(TestsTabMode.abcd)
                Label("Repertoire", systemImage: "music.note.list").tag(TestsTabMode.repertoire)
            }
            .pickerStyle(.segmented)
            .padding([.top, .horizontal])
            
            Divider()
            
            if selectedMode == .abcd {
                abcdBody
            } else {
                RepertoireComparisonTab(manager: manager)
            }
        }
    }
    
    private var abcdBody: some View {
        HSplitView {
            // Left: Test Controls and Console
            VStack(spacing: 0) {
                // Test Runner Section
                ScrollView {
                    VStack(spacing: 16) {
                        Text("🧪 ABCD Test Suite")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top)
                        
                        Text("Run comprehensive performance tests")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        // Test A
                        TestButton(
                            title: "Test A: 6 Preview Files",
                            subtitle: "Basic multithread test (~5-10s)",
                            testType: .testA,
                            runner: testRunner,
                            serverRunning: manager.isServerRunning
                        )
                        
                        // Test B
                        TestButton(
                            title: "Test B: 6 Full Songs",
                            subtitle: "Full song processing (~30-60s)",
                            testType: .testB,
                            runner: testRunner,
                            serverRunning: manager.isServerRunning
                        )
                        
                        // Test C
                        TestButton(
                            title: "Test C: 12 Preview Files",
                            subtitle: "Batch sequencing test (~10-20s)",
                            testType: .testC,
                            runner: testRunner,
                            serverRunning: manager.isServerRunning
                        )
                        
                        // Test D
                        TestButton(
                            title: "Test D: 12 Full Songs",
                            subtitle: "Full stress test (~60-120s)",
                            testType: .testD,
                            runner: testRunner,
                            serverRunning: manager.isServerRunning
                        )
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        // Run All Button
                        Button {
                            Task { await testRunner.runAllTests() }
                        } label: {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                Text("Run All Tests")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(testRunner.isRunning)
                        
                        // Open CSV Folder Button
                        Button {
                            openCSVFolder()
                        } label: {
                            Label("Open CSV Folder", systemImage: "folder.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
                .frame(height: 520) // Fixed height for test controls
                
                Divider()
                
                // Console Output - expands to fill remaining space
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Console Output")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button("Copy All") {
                            let allText = testRunner.outputLines.joined(separator: "\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(allText, forType: .string)
                            testRunner.addOutput("📋 Copied \(testRunner.outputLines.count) lines to clipboard")
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Clear") {
                            testRunner.clearOutput()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding([.horizontal, .top], 12)
                    
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(testRunner.outputLines.enumerated()), id: \.offset) { index, line in
                                    Text(line)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(index)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        }
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                        .onChange(of: testRunner.outputLines.count) { _, _ in
                            if let lastIndex = testRunner.outputLines.indices.last {
                                withAnimation {
                                    proxy.scrollTo(lastIndex, anchor: .bottom)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: .infinity) // Expands to fill available space
            }
            .frame(minWidth: 350, maxWidth: 400)
            
            // Right: Results Dashboard
            ABCDResultsDashboard(testRunner: testRunner)
        }
    }
    
    private func openCSVFolder() {
        // Use the same project path logic as the test runner
        var projectPath = ""
        
        // Try to find the EssentiaServer directory
        if let bundlePath = Bundle.main.bundlePath as NSString? {
            // From app bundle, go up to find EssentiaServer
            var searchPath = bundlePath as String
            
            // Keep going up directories until we find run_test.sh or hit root
            for _ in 0..<10 {
                let testScriptPath = (searchPath as NSString).appendingPathComponent("run_test.sh")
                if FileManager.default.fileExists(atPath: testScriptPath) {
                    projectPath = searchPath
                    break
                }
                searchPath = (searchPath as NSString).deletingLastPathComponent
            }
            
            // If we didn't find it, try hardcoded path
            if projectPath.isEmpty || projectPath == "/" {
                let documentsPath = NSHomeDirectory() + "/Documents/GitHub/EssentiaServer"
                if FileManager.default.fileExists(atPath: documentsPath + "/run_test.sh") {
                    projectPath = documentsPath
                }
            }
        } else {
            // Fallback to hardcoded path
            projectPath = NSHomeDirectory() + "/Documents/GitHub/EssentiaServer"
        }
        
        let csvPath = (projectPath as NSString).appendingPathComponent("csv")
        
        if FileManager.default.fileExists(atPath: csvPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: csvPath))
            testRunner.addOutput("📂 Opened CSV folder: \(csvPath)")
        } else {
            testRunner.addOutput("⚠️ CSV folder not found at: \(csvPath)")
            testRunner.addOutput("Project path: \(projectPath)")
        }
    }
}

enum TestsTabMode: Hashable {
    case abcd
    case repertoire
}

// MARK: - Test Button

struct TestButton: View {
    let title: String
    let subtitle: String
    let testType: ABCDTestType
    @ObservedObject var runner: ABCDTestRunner
    let serverRunning: Bool  // Not used anymore but kept for compatibility
    
    private var isRunning: Bool {
        runner.currentTest == testType
    }
    
    private var result: ABCDTestResult? {
        runner.results[testType]
    }
    
    var body: some View {
        Button {
            Task { await runner.runTest(testType) }
        } label: {
            HStack(spacing: 12) {
                // Status Icon
                ZStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 40, height: 40)
                    
                    if isRunning {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                    } else {
                        Image(systemName: statusIcon)
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let result = result {
                        HStack(spacing: 6) {
                            Text("\(String(format: "%.2f", result.duration))s")
                                .font(.caption2)
                            Text("•")
                            Text("\(result.successCount)/\(result.totalCount)")
                                .font(.caption2)
                                .foregroundColor(result.passed ? .green : .red)
                        }
                        .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(runner.isRunning)
    }
    
    private var statusColor: Color {
        if isRunning {
            return .blue
        } else if let result = result {
            return result.passed ? .green : .red
        } else {
            return .gray
        }
    }
    
    private var statusIcon: String {
        if let result = result {
            return result.passed ? "checkmark" : "xmark"
        } else {
            return "play.fill"
        }
    }
    
    private var borderColor: Color {
        if isRunning {
            return .blue
        } else if let result = result {
            return result.passed ? .green.opacity(0.5) : .red.opacity(0.5)
        } else {
            return .clear
        }
    }
}

// MARK: - Repertoire Comparison

struct RepertoireComparisonTab: View {
    @ObservedObject var manager: MacStudioServerManager
    @StateObject private var controller: RepertoireAnalysisController
    @State private var isTargeted = false
    
    init(manager: MacStudioServerManager) {
        self.manager = manager
        _controller = StateObject(wrappedValue: RepertoireAnalysisController(manager: manager))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            controls
            Divider()
            content
        }
        .padding(12)
        .task {
            await controller.loadDefaultSpotify()
            await controller.loadDefaultFolder()
        }
        .alert("Repertoire Comparison", isPresented: Binding(
            get: { controller.alertMessage != nil },
            set: { if !$0 { controller.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { controller.alertMessage = nil }
        } message: {
            Text(controller.alertMessage ?? "")
        }
    }
    
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Repertoire Comparison")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Import preview clips, match to Spotify reference, and compare BPM/Key results.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if !controller.rows.isEmpty {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(controller.summaryLine)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let folder = controller.currentFolderPath {
                        Text(folder)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                controller.pickFolder()
            } label: {
                Label("Choose Preview Folder…", systemImage: "folder")
            }
            
            Button {
                Task { await controller.reloadSpotify() }
            } label: {
                Label("Reload Spotify CSV", systemImage: "arrow.clockwise")
            }
            
            Spacer()

            Button {
                controller.copyDetectedBpmKeyToClipboard()
            } label: {
                Label("Copy Detected BPM / Key", systemImage: "doc.on.doc")
            }
            .disabled(!controller.rows.contains { $0.analysis != nil })

            Button {
                controller.startAnalysisFromButton()
            } label: {
                Label("Analyze with Latest Algorithms", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(controller.rows.isEmpty || controller.isAnalyzing)
        }
    }
    
    private var content: some View {
        Group {
            if controller.rows.isEmpty {
                VStack(spacing: 12) {
                    Text("Drop preview files or choose a folder to begin.")
                        .foregroundColor(.secondary)
                    Text("Default: Songwise 1 / preview_samples_repertoire_90 if available.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(controller.rows) {
                    TableColumn("#") { row in
                        Text("\(row.index)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .width(30)
                    
                    TableColumn("File") { row in
                        Text(row.fileName)
                            .lineLimit(1)
                    }
                    .width(min: 140)
                    
                    TableColumn("Artist") { row in
                        Text(row.displayArtist)
                            .lineLimit(1)
                    }
                    .width(min: 120)
                    
                    TableColumn("Title") { row in
                        Text(row.displayTitle)
                            .lineLimit(1)
                    }
                    .width(min: 160)
                    
                    TableColumn("Spotify BPM / Key") { row in
                        VStack(alignment: .leading, spacing: 2) {
                            if let sp = row.spotify {
                                Text(sp.bpmText)
                                Text(sp.key)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("—")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .width(min: 110)
                    
                    TableColumn("Detected BPM / Key") { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.detectedBpmText)
                                .foregroundColor(row.bpmMatch.color)
                            Text(row.detectedKeyText)
                                .font(.caption)
                                .foregroundColor(row.keyMatch.color)
                        }
                    }
                    .width(min: 130)
                    
                    TableColumn("BPM Match") { row in
                        MetricBadge(match: row.bpmMatch)
                    }
                    .width(min: 90)
                    
                    TableColumn("Key Match") { row in
                        MetricBadge(match: row.keyMatch)
                    }
                    .width(min: 90)
                    
                    TableColumn("Status") { row in
                        Text(row.statusText)
                            .font(.caption)
                            .foregroundColor(row.statusColor)
                    }
                    .width(min: 80)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .dropDestination(for: URL.self) { items, _ in
                    controller.handleDrop(items)
                } isTargeted: { hovering in
                    isTargeted = hovering
                }
                .overlay {
                    if controller.isAnalyzing {
                        ProgressView("Analyzing…")
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.windowBackgroundColor))
                                    .shadow(radius: 4)
                            )
                    }
                }
            }
        }
    }
}

struct RepertoireRow: Identifiable {
    let id = UUID()
    let index: Int
    let url: URL
    let fileName: String
    let artistGuess: String
    let titleGuess: String
    
    // Prefer Spotify metadata when available; file-name parsing is a fallback.
    var displayArtist: String { spotify?.artist ?? artistGuess }
    var displayTitle: String { spotify?.song ?? titleGuess }
    
    var spotify: RepertoireSpotifyTrack?
    var analysis: MacStudioServerManager.AnalysisResult?
    var bpmMatch: MetricMatch = .unavailable
    var keyMatch: MetricMatch = .unavailable
    var status: RepertoireStatus = .pending
    var error: String?
    
    var detectedBpmText: String {
        guard let bpm = analysis?.bpm else { return "—" }
        return String(format: "%.1f", bpm)
    }
    
    var detectedKeyText: String {
        analysis?.key ?? "—"
    }
    
    var statusText: String {
        switch status {
        case .pending: return "Pending"
        case .running: return "Running"
        case .done: return "Done"
        case .failed: return "Failed"
        }
    }
    
    var statusColor: Color {
        switch status {
        case .pending: return .secondary
        case .running: return .blue
        case .done: return .green
        case .failed: return .red
        }
    }
}

enum RepertoireStatus {
    case pending
    case running
    case done
    case failed
}

struct RepertoireSpotifyTrack: Identifiable {
    let id = UUID()
    let csvIndex: Int?
    let song: String
    let artist: String
    let bpm: Double
    let key: String
    
    var bpmText: String {
        String(format: "%.0f", bpm)
    }
}

struct MetricBadge: View {
    let match: MetricMatch
    
    var body: some View {
        switch match {
        case .match:
            label(text: "Match", color: .green)
        case .mismatch(let expected, let actual):
            label(text: "Mismatch", color: .red, tooltip: "Expected \(expected), got \(actual)")
        case .unavailable:
            label(text: "–", color: .secondary)
        }
    }
    
    private func label(text: String, color: Color, tooltip: String? = nil) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(color == .secondary ? 0.15 : 0.18)))
            .foregroundColor(color)
            .help(tooltip ?? "")
    }
}

enum RepertoireFileParser {
    static func isAudio(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "m4a" || ext == "mp3"
    }
    
    static func parse(fileName: String) -> (artist: String, title: String) {
        var stem = fileName
        if stem.lowercased().hasSuffix(".m4a") {
            stem.removeLast(4)
        } else if stem.lowercased().hasSuffix(".mp3") {
            stem.removeLast(4)
        }
        var parts = stem.split(separator: "_").map { String($0) }
        if let first = parts.first, Int(first) != nil {
            parts.removeFirst()
        }
        guard !parts.isEmpty else {
            return ("Unknown", stem)
        }
        let artist = parts.first ?? "Unknown"
        let title = parts.dropFirst().joined(separator: " ")
        return (artist, title)
    }
}

enum RepertoireMatchNormalizer {
    static func normalize(_ value: String) -> String {
        let lowered = value.lowercased()
        let trimmed = lowered.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
        return cleaned
    }
}

enum RepertoireSpotifyParser {
    static func parse(text: String) throws -> [RepertoireSpotifyTrack] {
        var lines = text.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return [] }
        let header = parseRow(lines.removeFirst())
        guard let indexIdx = header.firstIndex(of: "#"),
              let songIdx = header.firstIndex(of: "Song"),
              let artistIdx = header.firstIndex(of: "Artist"),
              let bpmIdx = header.firstIndex(of: "BPM"),
              let keyIdx = header.firstIndex(of: "Key") else {
            throw NSError(domain: "csv", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing required columns (Song, Artist, BPM, Key)"])
        }
        var result: [RepertoireSpotifyTrack] = []
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let cols = parseRow(line)
            guard cols.count > max(indexIdx, songIdx, artistIdx, bpmIdx, keyIdx) else { continue }
            let csvIndex = Int(cols[indexIdx])
            let song = cols[songIdx]
            let artist = cols[artistIdx]
            let bpm = Double(cols[bpmIdx]) ?? 0
            let key = cols[keyIdx]
            result.append(RepertoireSpotifyTrack(csvIndex: csvIndex, song: song, artist: artist, bpm: bpm, key: key))
        }
        return result
    }
    
    private static func parseRow(_ row: String) -> [String] {
        var columns: [String] = []
        var current = ""
        var insideQuotes = false
        for char in row {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                columns.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        columns.append(current)
        return columns
    }
}

#Preview {
    TestsTab(manager: MacStudioServerManager())
}
