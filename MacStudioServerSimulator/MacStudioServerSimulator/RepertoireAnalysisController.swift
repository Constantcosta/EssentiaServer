//
//  RepertoireAnalysisController.swift
//  MacStudioServerSimulator
//
//  Controller for Repertoire tab analysis with proper concurrency.
//

import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif
import UniformTypeIdentifiers

@MainActor
final class RepertoireAnalysisController: ObservableObject {
    @Published var rows: [RepertoireRow] = []
    @Published var spotifyTracks: [RepertoireSpotifyTrack] = []
    @Published var isAnalyzing = false
    @Published var alertMessage: String?
    
    let manager: MacStudioServerManager
    let rowTimeoutSeconds: TimeInterval = 180
    var analysisTask: Task<Void, Never>?
    let defaultNamespace = "repertoire-subset"
    let excludedRowNumbers: Set<Int> = [64, 73]
    let excludedBpmTruthTitles: Set<String> = []
    var bpmReferenceRows: [BpmReferenceRow] = []
    var truthRows: [TruthReferenceRow] = []
    var hasLoadedDefaults = false
    
    init(manager: MacStudioServerManager) {
        self.manager = manager
    }
}
