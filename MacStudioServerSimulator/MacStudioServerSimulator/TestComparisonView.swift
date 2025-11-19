//
//  TestComparisonView.swift
//  MacStudioServerSimulator
//
//  Spotify reference comparison for ABCD test results
//

import SwiftUI
import AppKit

struct TestComparisonView: View {
    let results: [ABCDTestType: ABCDTestResult]
    @State private var isExpanded = false
    @State private var detailWindow: NSWindow?
    
    private var allComparisons: [TrackComparison] {
        var comparisons: [TrackComparison] = []
        
        for test in ABCDTestType.allCases {
            guard let result = results[test] else { continue }
            let comparisonResults = ComparisonEngine.compareResults(
                analyses: result.analysisResults,
                testType: test
            )
            comparisons.append(contentsOf: comparisonResults)
        }
        
        return comparisons
    }
    
    private var matchStats: (matches: Int, total: Int) {
        let total = allComparisons.count
        let matches = allComparisons.filter { $0.overallMatch }.count
        return (matches, total)
    }
    
    private var comparisonExportText: String {
        guard !allComparisons.isEmpty else { return "" }
        var lines = ["Test\tSong\tArtist\tOur BPM\tSpotify BPM\tOur Key\tSpotify Key\tStatus"]
        for comparison in allComparisons {
            // Clean field values - remove tabs and newlines that could corrupt TSV format
            let testLabel = (comparison.testType?.name ?? "—").replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
            let song = comparison.song.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
            let artist = comparison.artist.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
            let oursBPM = comparison.analyzedBPM.map(String.init) ?? "—"
            let spotifyBPM = comparison.spotifyBPM.map(String.init) ?? "—"
            let oursKey = (comparison.analyzedKey ?? "—").replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
            let spotifyKey = (comparison.spotifyKey ?? "—").replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
            let status = comparison.overallMatch ? "Match" : "Diff"
            lines.append("\(testLabel)\t\(song)\t\(artist)\t\(oursBPM)\t\(spotifyBPM)\t\(oursKey)\t\(spotifyKey)\t\(status)")
        }
        return lines.joined(separator: "\n")
    }
    
    private func copyComparisonsToClipboard() {
        guard !allComparisons.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(comparisonExportText, forType: .string)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle")
                        .foregroundColor(.accentColor)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse" : "Expand")
                
                Label("Spotify Reference Comparison", systemImage: "chart.bar.doc.horizontal")
                    .font(.headline)
                
                Spacer()
                
                let stats = matchStats
                if stats.total > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(stats.matches == stats.total ? .green : .orange)
                        Text("\(stats.matches)/\(stats.total) matches")
                            .font(.subheadline)
                        
                        Text("(\(Int(Double(stats.matches) / Double(stats.total) * 100))%)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Button(action: { openDetailWindow() }) {
                    Label("Detail View", systemImage: "arrow.up.left.and.arrow.down.right")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .disabled(allComparisons.isEmpty)
                .buttonStyle(.borderless)
                .help("Open detailed comparison view in separate window")
                
                Button(action: copyComparisonsToClipboard) {
                    Label("Copy All", systemImage: "doc.on.doc")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .disabled(allComparisons.isEmpty)
                .buttonStyle(.borderless)
                .help("Copy the Spotify comparison rows to the clipboard")
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            if !isExpanded {
                // Collapsed: Show only summary
                if !allComparisons.isEmpty {
                    CollapsedSummaryView(comparisons: allComparisons)
                }
            } else if allComparisons.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 36))
                        .foregroundColor(.gray)
                    
                    Text("No comparison data")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Run tests to compare your results with Spotify's reference data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                } else {
                    // Comparison table
                    VStack(spacing: 0) {
                        // Header row - COMPACT VERSION
                        HStack(spacing: 8) {
                            Text("Test")
                                .frame(width: 70, alignment: .leading)
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            Divider()
                                .frame(height: 12)
                            
                            Text("Song / Artist")
                                .frame(width: 160, alignment: .leading)
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            Divider()
                                .frame(height: 12)
                            
                            Text("BPM (Ours → Spotify)")
                                .frame(width: 100)
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            Divider()
                                .frame(height: 12)
                            
                            Text("Key (Ours → Spotify)")
                                .frame(width: 80)
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            Divider()
                                .frame(height: 12)
                            
                            Text("Status")
                                .frame(width: 60, alignment: .center)
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .frame(height: 20)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 8)
                    .background(Color.secondary.opacity(0.1))
                    
                    Divider()
                    
                    // Scrollable rows
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(allComparisons) { comparison in
                                ComparisonRow(comparison: comparison)
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: isExpanded ? 500 : 300)
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                .cornerRadius(8)
                
                // Legend
                HStack(spacing: 12) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    HStack(spacing: 8) {
                        Label("Match", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                        
                        Label("Diff", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    Spacer()
                    
                    Text("±3 BPM tolerance · Enharmonic keys accepted")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func openDetailWindow() {
        // Close existing window if any
        detailWindow?.close()
        
        // Create new window - WIDER to fit all columns
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Spotify Reference Comparison"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: DetailedComparisonWindow(
                comparisons: allComparisons,
                exportText: comparisonExportText
            )
        )
        window.makeKeyAndOrderFront(nil)
        detailWindow = window
    }
}

// MARK: - Collapsed Summary View

struct CollapsedSummaryView: View {
    let comparisons: [TrackComparison]
    
    private var matchCount: Int {
        comparisons.filter { $0.overallMatch }.count
    }
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.title3)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(comparisons.count) tracks compared")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 12) {
                    Label("\(matchCount) matches", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    if matchCount < comparisons.count {
                        Label("\(comparisons.count - matchCount) differences", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Spacer()
            
            Text("\(Int(Double(matchCount) / Double(comparisons.count) * 100))% accuracy")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(matchCount == comparisons.count ? .green : .orange)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(8)
    }
}

// MARK: - Detailed Comparison Window

struct DetailedComparisonWindow: View {
    let comparisons: [TrackComparison]
    let exportText: String
    @State private var searchText = ""
    @State private var filterMode: FilterMode = .all
    @State private var copiedMessage = false
    
    enum FilterMode: String, CaseIterable {
        case all = "All"
        case matches = "Matches"
        case differences = "Differences"
    }
    
    private var filteredComparisons: [TrackComparison] {
        let filtered: [TrackComparison]
        switch filterMode {
        case .all:
            filtered = comparisons
        case .matches:
            filtered = comparisons.filter { $0.overallMatch }
        case .differences:
            filtered = comparisons.filter { !$0.overallMatch }
        }
        
        if searchText.isEmpty {
            return filtered
        }
        
        return filtered.filter {
            $0.song.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText) ||
            ($0.testType?.name.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(exportText, forType: .string)
        copiedMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedMessage = false
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Compact toolbar
            HStack(spacing: 12) {
                // Search
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(4)
                .frame(maxWidth: 200)
                
                // Filter
                Picker("", selection: $filterMode) {
                    ForEach(FilterMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
                
                Spacer()
                
                // Stats
                Text("\(filteredComparisons.count)/\(comparisons.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Copy button
                Button(action: copyToClipboard) {
                    Label(copiedMessage ? "✓" : "Copy", systemImage: copiedMessage ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(comparisons.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Table Header - COMPACT with flexible columns
            HStack(spacing: 0) {
                Text("Test")
                    .frame(width: 90, alignment: .leading)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.leading, 12)
                
                Divider()
                    .frame(height: 12)
                    .padding(.horizontal, 8)
                
                Text("Song / Artist")
                    .frame(width: 280, alignment: .leading)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.leading, 4)
                
                Divider()
                    .frame(height: 12)
                    .padding(.horizontal, 8)
                
                Text("BPM (Ours → Spotify)")
                    .frame(width: 200, alignment: .leading)
                    .font(.caption2)
                    .fontWeight(.semibold)
                
                Divider()
                    .frame(height: 12)
                    .padding(.horizontal, 8)
                
                Text("Key (Ours → Spotify)")
                    .frame(width: 240, alignment: .leading)
                    .font(.caption2)
                    .fontWeight(.semibold)
                
                Divider()
                    .frame(height: 12)
                    .padding(.horizontal, 8)
                
                Text("Status")
                    .frame(width: 100, alignment: .center)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.trailing, 12)
                
                Spacer()
            }
            .frame(height: 18)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.08))
            
            Divider()
            
            // Table Content
            if filteredComparisons.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: searchText.isEmpty ? "music.note.list" : "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "No results" : "No matches found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filteredComparisons) { comparison in
                            DetailedComparisonRow(comparison: comparison)
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

struct DetailedComparisonRow: View {
    let comparison: TrackComparison
    
    var body: some View {
        HStack(spacing: 0) {
            // Test label
            TestBadge(testType: comparison.testType)
                .frame(width: 90, alignment: .leading)
                .padding(.leading, 12)
            
            Divider()
                .padding(.horizontal, 8)
            
            // Song/Artist - Fixed width for visibility
            VStack(alignment: .leading, spacing: 2) {
                Text(comparison.song)
                    .font(.body)
                    .lineLimit(1)
                Text(comparison.artist)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 280, alignment: .leading)
            .padding(.leading, 4)
            
            Divider()
                .padding(.horizontal, 8)
            
            // BPM - More width
            HStack(spacing: 6) {
                Text(comparison.analyzedBPM.map { String($0) } ?? "—")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(comparison.bpmMatch.color)
                    .frame(minWidth: 50, alignment: .trailing)
                
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(comparison.spotifyBPM.map { String($0) } ?? "—")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 50, alignment: .leading)
                
                if case .mismatch = comparison.bpmMatch {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                Spacer()
            }
            .frame(width: 200, alignment: .leading)
            
            Divider()
                .padding(.horizontal, 8)
            
            // Key - Much more width
            HStack(spacing: 6) {
                Text(comparison.analyzedKey ?? "—")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(comparison.keyMatch.color)
                    .frame(minWidth: 80, alignment: .trailing)
                    .lineLimit(1)
                
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(comparison.spotifyKey ?? "—")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 80, alignment: .leading)
                    .lineLimit(1)
                
                if case .mismatch = comparison.keyMatch {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                Spacer()
            }
            .frame(width: 240, alignment: .leading)
            
            Divider()
                .padding(.horizontal, 8)
            
            // Status - More width
            HStack(spacing: 4) {
                Image(systemName: comparison.overallMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(comparison.overallMatch ? .green : .red)
                Text(comparison.overallMatch ? "Match" : "Diff")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(width: 100)
            .padding(.trailing, 12)
            
            Spacer()
        }
        .padding(.vertical, 8)
        .background(comparison.overallMatch ? Color.green.opacity(0.03) : Color.red.opacity(0.05))
        .contextMenu {
            Button("Copy Song: \(comparison.song)") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(comparison.song, forType: .string)
            }
            Button("Copy Artist: \(comparison.artist)") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(comparison.artist, forType: .string)
            }
            Divider()
            Button("Copy Row") {
                let row = "\(comparison.testType?.name ?? "—")\t\(comparison.song)\t\(comparison.artist)\t\(comparison.analyzedBPM ?? 0)\t\(comparison.spotifyBPM ?? 0)\t\(comparison.analyzedKey ?? "")\t\(comparison.spotifyKey ?? "")"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row, forType: .string)
            }
        }
    }
}

// MARK: - Original Row

struct ComparisonRow: View {
    let comparison: TrackComparison
    
    var body: some View {
        HStack(spacing: 8) {
            TestBadge(testType: comparison.testType)
                .frame(width: 70, alignment: .leading)
            
            Divider()
            
            // Song
            VStack(alignment: .leading, spacing: 1) {
                Text(comparison.song)
                    .font(.caption)
                    .lineLimit(1)
                Text(comparison.artist)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 160, alignment: .leading)
            
            Divider()
            
            // BPM
            HStack(spacing: 3) {
                ComparisonValueBadge(
                    value: comparison.analyzedBPM.map { String($0) } ?? "—",
                    match: comparison.bpmMatch
                )
                
                Text("·")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(comparison.spotifyBPM.map { String($0) } ?? "—")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 100)
            
            Divider()
            
            // Key
            HStack(spacing: 3) {
                ComparisonValueBadge(
                    value: comparison.analyzedKey ?? "—",
                    match: comparison.keyMatch
                )
                .lineLimit(1)
                .truncationMode(.tail)
                
                Text("·")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(comparison.spotifyKey ?? "—")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 80)
            
            Divider()
            
            // Status
            HStack(spacing: 2) {
                Image(systemName: comparison.overallMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(comparison.overallMatch ? .green : .red)
                    .font(.caption)
            }
            .frame(width: 60)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(comparison.overallMatch ? Color.green.opacity(0.03) : Color.red.opacity(0.03))
    }
}

struct TestBadge: View {
    let testType: ABCDTestType?
    
    var body: some View {
        Text(testType?.name ?? "—")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12))
            .foregroundColor(.accentColor)
            .cornerRadius(6)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

struct ComparisonValueBadge: View {
    let value: String
    let match: MetricMatch
    
    // Clean the value to ensure it doesn't contain garbage
    private var cleanValue: String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // If it looks like a key (short string with musical note), return it
        // Otherwise return placeholder
        if trimmed.count > 20 {
            return "—"  // Too long to be a key, likely corrupted
        }
        return trimmed
    }
    
    var body: some View {
        Text(cleanValue)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(match.color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(match.color.opacity(0.12))
            .cornerRadius(3)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

#Preview {
    TestComparisonView(results: [:])
        .frame(width: 500, height: 400)
}
