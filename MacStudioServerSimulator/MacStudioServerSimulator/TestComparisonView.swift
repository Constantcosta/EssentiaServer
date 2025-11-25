//
//  TestComparisonView.swift
//  MacStudioServerSimulator
//
//  Spotify reference comparison for ABCD test results.
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
                if !allComparisons.isEmpty {
                    CollapsedSummaryView(comparisons: allComparisons)
                }
            } else if allComparisons.isEmpty {
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
                VStack(spacing: 0) {
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
        detailWindow?.close()
        
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

#Preview {
    TestComparisonView(results: [:])
        .frame(width: 500, height: 400)
}
