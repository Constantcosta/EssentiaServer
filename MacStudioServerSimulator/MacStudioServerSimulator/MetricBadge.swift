//
//  MetricBadge.swift
//  MacStudioServerSimulator
//
//  Small badge for match/mismatch display.
//

import SwiftUI

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
