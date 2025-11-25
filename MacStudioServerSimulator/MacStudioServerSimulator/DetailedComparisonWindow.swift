//
//  DetailedComparisonWindow.swift
//  MacStudioServerSimulator
//
//  Expanded comparison table for Spotify references.
//

import SwiftUI
import AppKit

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
            HStack(spacing: 12) {
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
                
                Picker("", selection: $filterMode) {
                    ForEach(FilterMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
                
                Spacer()
                
                Text("\(filteredComparisons.count)/\(comparisons.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
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
            TestBadge(testType: comparison.testType)
                .frame(width: 90, alignment: .leading)
                .padding(.leading, 12)
            
            Divider()
                .padding(.horizontal, 8)
            
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
