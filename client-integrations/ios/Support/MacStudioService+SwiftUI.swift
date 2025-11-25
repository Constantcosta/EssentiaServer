import Foundation
import Combine

extension MacStudioService {
// MARK: - SwiftUI Integration Helper

import SwiftUI

/// View modifier to integrate Mac Studio analysis
struct MacStudioAnalysisModifier: ViewModifier {
    let previewURL: String
    let title: String
    let artist: String
    @Binding var analysisResult: MacStudioService.AnalysisResult?
    @Binding var isAnalyzing: Bool
    @State private var error: Error?
    
    func body(content: Content) -> some View {
        content
            .task {
                await performAnalysis()
            }
    }
    
    @available(iOS 15.0, *)
    private func performAnalysis() async {
        isAnalyzing = true
        do {
            let result = try await MacStudioService.shared.analyzeSong(
                previewURL: previewURL,
                title: title,
                artist: artist
            )
            analysisResult = result
        } catch {
            self.error = error
            print("Analysis failed: \(error.localizedDescription)")
        }
        isAnalyzing = false
    }
}

extension View {
    /// Automatically analyze a song when view appears
    func macStudioAnalysis(
        previewURL: String,
        title: String,
        artist: String,
        result: Binding<MacStudioService.AnalysisResult?>,
        isAnalyzing: Binding<Bool>
    ) -> some View {
        modifier(MacStudioAnalysisModifier(
            previewURL: previewURL,
            title: title,
            artist: artist,
            analysisResult: result,
            isAnalyzing: isAnalyzing
        ))
    }
}

}
