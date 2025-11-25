//
//  ServerManagementCacheTab.swift
//  MacStudioServerSimulator
//

import SwiftUI
import AppKit

struct CacheTab: View {
    @ObservedObject var manager: MacStudioServerManager
    @Binding var searchQuery: String
    @Binding var showingClearAlert: Bool
    @State private var exportError: String?
    @State private var isExporting = false
    @State private var isTitleAscending = true
    private let autoRefreshIntervalNanoseconds: UInt64 = 30 * 1_000_000_000
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                TextField("Search title, artist, or URL", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    .frame(maxWidth: 320)
                    .onSubmit {
                        Task { await manager.searchCache(query: searchQuery) }
                    }
                
                Button {
                    Task { await manager.searchCache(query: searchQuery) }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .disabled(manager.isLoading)
                
                Button {
                    searchQuery = ""
                    Task { await manager.searchCache(query: "") }
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .disabled(searchQuery.isEmpty || manager.isLoading)
                
                Spacer()
                
                Button {
                    isTitleAscending.toggle()
                } label: {
                    Label(isTitleAscending ? "Title A→Z" : "Title Z→A", systemImage: "textformat")
                }
                .disabled(manager.isLoading)
                
                Button {
                    Task { await manager.refreshCacheList() }
                } label: {
                    Label("Refresh Cache", systemImage: "arrow.clockwise")
                }
                .disabled(manager.isLoading)
                
                Button {
                    showingClearAlert = true
                } label: {
                    Label("Clear Cache", systemImage: "trash")
                }
                .tint(.red)
                .disabled(manager.isLoading)
                .alert("Clear Cached Analyses?", isPresented: $showingClearAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Clear", role: .destructive) {
                        Task { await manager.clearCache() }
                    }
                } message: {
                    Text("This removes all cached analyses. Are you sure?")
                }
            }
            
            Divider()
            
            if manager.cachedAnalyses.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No cached analyses found")
                        .font(.title3)
                        .padding(.bottom, 4)
                    Text("Drop Apple Music URLs into the Mac menu bar app or analyze via the API to populate this view.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(sortedAnalyses) { analysis in
                            CachedAnalysisRow(analysis: analysis, manager: manager)
                        }
                    }
                    .padding(.bottom)
                }
            }
        }
        .padding()
        .task(id: manager.isServerRunning) {
            await autoRefreshCache()
        }
        .onChange(of: searchQuery) { _, newValue in
            if newValue.isEmpty {
                Task { await manager.searchCache(query: "") }
            }
        }
    }
    
    private var sortedAnalyses: [CachedAnalysis] {
        manager.cachedAnalyses.sorted { first, second in
            let comparison = first.title.localizedCaseInsensitiveCompare(second.title)
            if comparison == .orderedSame {
                return first.id < second.id
            }
            return isTitleAscending ? comparison != .orderedDescending : comparison == .orderedDescending
        }
    }
    
    @MainActor
    private func autoRefreshCache() async {
        guard manager.isServerRunning else { return }
        let shouldShowLoading = manager.cachedAnalyses.isEmpty
        if searchQuery.isEmpty {
            await manager.refreshCacheList(showLoadingIndicator: shouldShowLoading)
        } else {
            await manager.searchCache(query: searchQuery, showLoadingIndicator: shouldShowLoading)
        }
        
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: autoRefreshIntervalNanoseconds)
            } catch {
                break
            }
            
            guard manager.isServerRunning else { break }
            if searchQuery.isEmpty {
                await manager.refreshCacheList(showLoadingIndicator: false)
            } else {
                await manager.searchCache(query: searchQuery, showLoadingIndicator: false)
            }
        }
    }
}
