//
//  ServerManagementTestsTab.swift
//  MacStudioServerSimulator
//
//  Tests tab: ABCD test suite + Repertoire comparison view.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation

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
    @StateObject private var audioPlayer = RepertoireAudioPlayer()
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
            await controller.loadDefaultBpmReferences()
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
    
    private func handleDropFromProviders(_ providers: [NSItemProvider]) -> Bool {
        let typeIdentifier = "public.file-url"
        var found = false
        let group = DispatchGroup()
        var urls: [URL] = []
        
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                found = true
                group.enter()
                provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            urls.append(url)
                            group.leave()
                        }
                    } else {
                        DispatchQueue.main.async {
                            group.leave()
                        }
                    }
                }
            }
        }
        
        guard found else { return false }
        
        group.notify(queue: .main) {
            _ = controller.handleDrop(urls)
        }
        
        return true
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
                    HStack(spacing: 6) {
                        Text("Overall winner:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(controller.overallWinnerLabel)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(controller.overallWinnerColor.opacity(controller.overallWinnerLabel == "—" ? 0.15 : 0.2))
                            )
                            .foregroundColor(controller.overallWinnerColor)
                            .help(controller.overallWinnerDetail)
                    }
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
                controller.exportMismatches()
            } label: {
                Label("Export Mismatches", systemImage: "square.and.arrow.down")
            }
            .disabled(controller.rows.isEmpty)
            
            Button {
                controller.exportResults()
            } label: {
                Label("Export All Results", systemImage: "tray.and.arrow.down")
            }
            .disabled(controller.rows.isEmpty)

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
                            .padding(.trailing, 22)
                            .overlay(alignment: .trailing) {
                                Button {
                                    audioPlayer.togglePlayback(for: row)
                                } label: {
                                    Image(systemName: audioPlayer.isPlaying(row) ? "pause.circle.fill" : "play.circle.fill")
                                        .foregroundColor(audioPlayer.isPlaying(row) ? .accentColor : .secondary)
                                        .imageScale(.medium)
                                }
                                .buttonStyle(.plain)
                                .help(audioPlayer.isPlaying(row) ? "Pause preview" : "Play preview")
                            }
                    }
                    .width(min: 140)
                    
                    TableColumn("Artist / Title") { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.displayArtist)
                                .lineLimit(1)
                            Text(row.displayTitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .width(min: 200)
                    
                    TableColumn("Spotify BPM / Key") { row in
                        VStack(alignment: .leading, spacing: 2) {
                            if let sp = row.spotify {
                                let bpmColor = row.spotifyBpmVsTruth.color
                                let keyColor = row.spotifyKeyVsTruth.color
                                Text(sp.bpmText)
                                    .foregroundColor(bpmColor)
                                Text(sp.key)
                                    .font(.caption)
                                    .foregroundColor(keyColor)
                            } else {
                                Text("—")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .width(min: 110)
                    
                    TableColumn("Google BPM / Key") { row in
                        VStack(alignment: .leading, spacing: 2) {
                            if let sp = row.spotify,
                               sp.googleBpm != nil || (sp.googleKey != nil && !sp.googleKey!.isEmpty) || (sp.keyQuality != nil && !sp.keyQuality!.isEmpty) {
                                if let gbpmText = sp.googleBpmText {
                                    Text(gbpmText)
                                        .foregroundColor(row.googleBpmVsTruth.color)
                                }
                                if let gkey = sp.googleKey {
                                    Text(gkey)
                                        .font(.caption)
                                        .foregroundColor(row.googleKeyVsTruth.color)
                                }
                                if let quality = sp.keyQuality {
                                    Text(quality)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("—")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .width(min: 120)
                    
                    TableColumn("SongBPM / Deezer") { row in
                        VStack(alignment: .leading, spacing: 2) {
                            if row.spotify?.songBpm != nil || row.deezerBpmValue != nil {
                                if row.spotify?.songBpm != nil {
                                    Text(row.songBpmText)
                                        .foregroundColor(row.songBpmVsTruth.color)
                                }
                                if row.deezerBpmValue != nil {
                                    Text(row.deezerBpmText)
                                        .font(.caption)
                                        .foregroundColor(row.deezerBpmVsTruth.color)
                                }
                            } else {
                                Text("—")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .width(min: 110)
                    
                    TableColumn("Truth BPM / Key") { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.truthBpmText)
                                .font(.caption)
                                .foregroundColor(row.truthBpmText == "—" ? .secondary : .green)
                            Text(row.truthKeyText)
                                .font(.caption)
                                .foregroundColor(row.truthKeyText == "—" ? .secondary : .green)
                            if let confidence = row.truthConfidenceLabel {
                                Text(confidence)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(row.truthConfidenceColor.opacity(0.18))
                                    )
                                    .foregroundColor(row.truthConfidenceColor)
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
                    
                    TableColumn("Winner / Status") { row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text("BPM")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(row.bpmWinnerLabel)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(row.bpmWinnerColor.opacity(row.bpmWinnerLabel == "—" ? 0.15 : 0.2))
                                    )
                                    .foregroundColor(row.bpmWinnerColor)
                            }
                            HStack(spacing: 6) {
                                Text("Key")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(row.keyWinnerLabel)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(row.keyWinnerColor.opacity(row.keyWinnerLabel == "—" ? 0.15 : 0.2))
                                    )
                                    .foregroundColor(row.keyWinnerColor)
                            }
                            Text(row.statusText)
                                .font(.caption2)
                                .foregroundColor(row.statusColor)
                        }
                    }
                    .width(min: 140)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: ["public.file-url"], isTargeted: $isTargeted, perform: handleDropFromProviders)
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

// Lightweight local preview player for repertoire rows.
@MainActor
final class RepertoireAudioPlayer: NSObject, ObservableObject {
    @Published private(set) var currentlyPlayingRowID: UUID?
    
    private var player: AVAudioPlayer?
    
    func togglePlayback(for row: RepertoireRow) {
        if currentlyPlayingRowID == row.id {
            stopPlayback()
        } else {
            startPlayback(url: row.url, rowID: row.id)
        }
    }
    
    func isPlaying(_ row: RepertoireRow) -> Bool {
        currentlyPlayingRowID == row.id && (player?.isPlaying ?? false)
    }
    
    private func startPlayback(url: URL, rowID: UUID) {
        stopPlayback()
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            player = newPlayer
            currentlyPlayingRowID = rowID
            newPlayer.delegate = self
            newPlayer.prepareToPlay()
            newPlayer.play()
        } catch {
            NSSound.beep()
            currentlyPlayingRowID = nil
            player = nil
        }
    }
    
    private func stopPlayback() {
        player?.stop()
        player = nil
        currentlyPlayingRowID = nil
    }
    
}

// Delegate callbacks can fire off the main thread; hop onto the main actor before mutating state.
extension RepertoireAudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.stopPlayback()
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            self?.stopPlayback()
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
    var bpmTruthExcluded: Bool = false
    var status: RepertoireStatus = .pending
    var error: String?
    
    var detectedBpmText: String {
        guard let bpm = analysis?.bpm else { return "—" }
        return String(format: "%.1f", bpm)
    }
    
    var detectedKeyText: String {
        analysis?.key ?? "—"
    }
    
    var hasBpmTruth: Bool {
        truthBpmValue != nil && !bpmTruthExcluded
    }
    
    var hasAnyTruth: Bool {
        hasTruthKey || hasBpmTruth
    }
    
    var songBpmText: String {
        guard let bpm = spotify?.songBpm else { return "—" }
        return String(format: "%.0f", bpm)
    }
    
    var deezerBpmValue: Double? {
        spotify?.deezerApiBpm ?? spotify?.deezerBpm
    }
    
    var deezerBpmText: String {
        guard let bpm = deezerBpmValue else { return "—" }
        return String(format: "%.0f", bpm)
    }
    
    private var truthBpmCandidates: [Double] {
        [
            spotify?.googleBpm,
            spotify?.deezerApiBpm,
            spotify?.deezerBpm,
            spotify?.songBpm,
            spotify?.bpm
        ].compactMap { $0 }
    }
    
    var truthBpmValue: Double? {
        guard !truthBpmCandidates.isEmpty else { return nil }
        let sorted = truthBpmCandidates.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        } else {
            return sorted[mid]
        }
    }
    
    var truthBpmText: String {
        guard let bpm = truthBpmValue else { return "—" }
        return String(format: "%.0f", bpm)
    }
    
    var truthKeyText: String {
        spotify?.truthKeyLabel ?? "—"
    }
    
    var hasTruthKey: Bool {
        spotify?.truthKeyLabel != nil
    }
    
    var truthConfidenceLabel: String? {
        guard !truthBpmCandidates.isEmpty else { return nil }
        let spread = (truthBpmCandidates.max() ?? 0) - (truthBpmCandidates.min() ?? 0)
        if truthBpmCandidates.count <= 1 {
            return "Low confidence"
        } else if spread <= 3 {
            return "High confidence"
        } else if spread <= 6 {
            return "Medium confidence"
        } else {
            return "Low confidence"
        }
    }
    
    var truthConfidenceColor: Color {
        guard let label = truthConfidenceLabel else { return .secondary }
        switch label {
        case "High confidence": return .green
        case "Medium confidence": return .orange
        case "Low confidence": return .red
        default: return .secondary
        }
    }
    
    var spotifyKeyVsTruth: MetricMatch {
        guard let truth = spotify?.truthKeyLabel else {
            return .unavailable
        }
        return ComparisonEngine.compareKey(
            analyzed: spotify?.key,
            reference: truth
        )
    }
    
    var spotifyBpmVsTruth: MetricMatch {
        guard let truth = truthBpmValue,
              let spotifyBpm = spotify?.bpm else {
            return .unavailable
        }
        return ComparisonEngine.compareBPM(
            analyzed: Int(round(spotifyBpm)),
            spotify: Int(round(truth))
        )
    }
    
    var googleKeyVsTruth: MetricMatch {
        guard let truth = spotify?.truthKeyLabel,
              let googleKey = spotify?.googleKey else {
            return .unavailable
        }
        return ComparisonEngine.compareKey(
            analyzed: googleKey,
            reference: truth
        )
    }
    
    var googleBpmVsTruth: MetricMatch {
        guard let truth = truthBpmValue,
              let googleBpm = spotify?.googleBpm else {
            return .unavailable
        }
        return ComparisonEngine.compareBPM(
            analyzed: Int(round(googleBpm)),
            spotify: Int(round(truth))
        )
    }
    
    var songBpmVsTruth: MetricMatch {
        guard let truth = truthBpmValue,
              let songBpm = spotify?.songBpm else {
            return .unavailable
        }
        return ComparisonEngine.compareBPM(
            analyzed: Int(round(songBpm)),
            spotify: Int(round(truth))
        )
    }
    
    var deezerBpmVsTruth: MetricMatch {
        guard let truth = truthBpmValue,
              let deezer = deezerBpmValue else {
            return .unavailable
        }
        return ComparisonEngine.compareBPM(
            analyzed: Int(round(deezer)),
            spotify: Int(round(truth))
        )
    }
    
    private func wins(key: MetricMatch, bpm: MetricMatch) -> Bool {
        let keyOk = hasTruthKey ? key.isMatch : true
        let bpmOk = hasBpmTruth ? bpm.isMatch : true
        return keyOk && bpmOk
    }
    
    var spotifyWins: Bool {
        wins(key: spotifyKeyVsTruth, bpm: spotifyBpmVsTruth)
    }
    
    var googleWins: Bool {
        wins(key: googleKeyVsTruth, bpm: googleBpmVsTruth)
    }
    
    var songwiseWins: Bool {
        wins(key: keyMatch, bpm: bpmMatch)
    }
    
    private func winnerLabel(for matches: [(String, Bool)]) -> String {
        let winners = matches.filter { $0.1 }.map { $0.0 }
        guard !winners.isEmpty else { return "—" }
        return winners.count == 1 ? winners[0] : "Tie"
    }
    
    var bpmWinnerLabel: String {
        guard hasBpmTruth else { return "—" }
        return winnerLabel(
            for: [
                ("Spotify", spotifyBpmVsTruth.isMatch),
                ("Google", googleBpmVsTruth.isMatch),
                ("Songwise", bpmMatch.isMatch)
            ]
        )
    }
    
    var keyWinnerLabel: String {
        guard hasTruthKey else { return "—" }
        return winnerLabel(
            for: [
                ("Spotify", spotifyKeyVsTruth.isMatch),
                ("Google", googleKeyVsTruth.isMatch),
                ("Songwise", keyMatch.isMatch)
            ]
        )
    }
    
    var bpmWinnerColor: Color {
        bpmWinnerLabel == "—" ? .secondary : .green
    }
    
    var keyWinnerColor: Color {
        keyWinnerLabel == "—" ? .secondary : .green
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
    var googleBpm: Double?
    var songBpm: Double?
    var deezerBpm: Double?
    var deezerApiBpm: Double?
    let googleKey: String?
    let truthKey: String?
    let keyQuality: String?
    
    var bpmText: String {
        String(format: "%.0f", bpm)
    }
    
    var googleBpmText: String? {
        guard let googleBpm else { return nil }
        return String(format: "%.0f", googleBpm)
    }
    
    var truthKeyLabel: String? {
        let trimmed = truthKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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
        let googleBpmIdx = header.firstIndex(of: "Google BPM")
        let googleKeyIdx = header.firstIndex(of: "Google Key")
        let truthKeyIdx = header.firstIndex(of: "Truth Key")
        let keyQualityIdx = header.firstIndex(of: "Key Quality")
        var result: [RepertoireSpotifyTrack] = []
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let cols = parseRow(line)
            guard cols.count > max(indexIdx, songIdx, artistIdx, bpmIdx, keyIdx) else { continue }
            let csvIndex = Int(cols[indexIdx])
            let song = cols[songIdx]
            let artist = cols[artistIdx]
            let bpm = Double(cols[bpmIdx]) ?? 0
            let key = cols[keyIdx]
            let googleBpm: Double?
            if let idx = googleBpmIdx, idx < cols.count {
                googleBpm = Double(cols[idx])
            } else {
                googleBpm = nil
            }
            let googleKey: String?
            if let idx = googleKeyIdx, idx < cols.count {
                let value = cols[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                googleKey = value.isEmpty ? nil : value
            } else {
                googleKey = nil
            }
            let truthKey: String?
            if let idx = truthKeyIdx, idx < cols.count {
                let value = cols[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                truthKey = value.isEmpty ? nil : value
            } else {
                truthKey = nil
            }
            let keyQuality: String?
            if let idx = keyQualityIdx, idx < cols.count {
                let value = cols[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                keyQuality = value.isEmpty ? nil : value
            } else {
                keyQuality = nil
            }
            result.append(
                RepertoireSpotifyTrack(
                    csvIndex: csvIndex,
                    song: song,
                    artist: artist,
                    bpm: bpm,
                    key: key,
                    googleBpm: googleBpm,
                    songBpm: nil,
                    deezerBpm: nil,
                    deezerApiBpm: nil,
                    googleKey: googleKey,
                    truthKey: truthKey,
                    keyQuality: keyQuality
                )
            )
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
