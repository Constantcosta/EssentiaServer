//
//  TestComparisonRowViews.swift
//  MacStudioServerSimulator
//
//  Row components for Spotify comparison summaries.
//

import SwiftUI

struct ComparisonRow: View {
    let comparison: TrackComparison
    
    var body: some View {
        HStack(spacing: 8) {
            TestBadge(testType: comparison.testType)
                .frame(width: 70, alignment: .leading)
            
            Divider()
            
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
    
    private var cleanValue: String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 20 {
            return "—"
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
