//
//  RepertoireAnalysisController+Analysis.swift
//  MacStudioServerSimulator
//
//  Core analysis workflow for repertoire runs.
//

import Foundation

extension RepertoireAnalysisController {
    func startAnalysisFromButton() {
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            await self?.runFullAnalysisSession()
        }
    }
    
    private func runFullAnalysisSession() async {
        print("[ENTRY] runFullAnalysisSession() called")
        print("[STATE] rows.count=\(rows.count), isAnalyzing=\(isAnalyzing)")
        
        guard !isAnalyzing else {
            print("⚠️ Already analyzing; ignoring new request")
            return
        }
        guard !rows.isEmpty else {
            print("⚠️ Cannot start analysis: rows are empty")
            alertMessage = "Load preview files before analyzing."
            return
        }
        
        isAnalyzing = true
        alertMessage = nil
        defer {
            isAnalyzing = false
            analysisTask = nil
        }
        
        print("🚀 Starting analysis for \(rows.count) rows")
        print("[SERVER] Launching dedicated analyzer for Repertoire run…")
        
        await manager.startServer()
        print("[SERVER] startServer() returned (isServerRunning=\(manager.isServerRunning))")
        
        guard manager.isServerRunning else {
            print("❌ Server is not running after startServer()")
            alertMessage = AudioAnalysisError.serverOffline.errorDescription ?? "Server offline"
            return
        }
        
        print("✓ Server is running, proceeding with analysis")
        print("[STEP 1] Calling runAnalysisBatches...")
        await runAnalysisBatches()
        print("[STEP 2] runAnalysisBatches returned")
        print("🏁 Analysis complete")
        
        print("[LOG] Exporting calibration summary log…")
        exportCalibrationLog()
        
        print("[SERVER] Stopping analyzer after Repertoire run…")
        await manager.stopServer(userTriggered: false)
        print("[SERVER] stopServer() returned (isServerRunning=\(manager.isServerRunning))")
        print("[EXIT] runFullAnalysisSession() complete")
    }
    
    private func runAnalysisBatches() async {
        print("[BATCH ENTRY] runAnalysisBatches() called")
        
        let indices = Array(rows.indices)
        let maxConcurrent = 6
        print("[POOL] Bounded concurrent analysis for \(indices.count) rows (max \(maxConcurrent))")
        
        var start = 0
        while start < indices.count {
            let end = min(start + maxConcurrent, indices.count)
            let batch = Array(indices[start..<end])
            print("[POOL] Starting batch \(start + 1)-\(end) (size \(batch.count))")
            
            if !manager.isServerRunning {
                let label = "\(start + 1)-\(end)"
                print("[POOL] Analyzer offline before batch \(label); starting now")
                await manager.startServer(skipPreflight: start > 0)
                guard manager.isServerRunning else {
                    print("❌ Analyzer failed to start before batch \(label); aborting run")
                    return
                }
            }
            
            await withTaskGroup(of: Void.self) { group in
                for idx in batch {
                    print("[POOL] Starting task for row index \(idx)")
                    group.addTask { [weak self] in
                        await self?.analyzeRowNonisolated(at: idx)
                    }
                }
                await group.waitForAll()
            }
            
            print("[POOL] Finished batch \(start + 1)-\(end)")
            start = end
        }
        
        print("[POOL EXIT] All rows processed")
    }
    
    private func analyzeRow(at index: Int) async {
        print("[ROW \(index)] analyzeRow() called")
        
        guard rows.indices.contains(index) else {
            print("[ROW \(index)] ERROR: Index out of bounds")
            return
        }
        
        print("[ROW \(index)] Setting status to .running")
        rows[index].status = .running
        let fileURL = rows[index].url
        print("[ROW \(index)] File: \(rows[index].fileName)")
        print("[ROW \(index)] URL: \(fileURL.path)")
        
        do {
            let clientId = "repertoire-row-\(index + 1)"
            print("[ROW \(index)] Calling manager.analyzeAudioFile… (clientId=\(clientId))")
            let result = try await manager.analyzeAudioFile(
                at: fileURL,
                skipChunkAnalysis: false,
                forceFreshAnalysis: true,
                cacheNamespace: defaultNamespace,
                clientRequestId: clientId
            )
            print("[ROW \(index)] manager.analyzeAudioFile returned successfully")
            
            guard rows.indices.contains(index) else {
                print("[ROW \(index)] WARNING: Index out of bounds after analysis")
                return
            }
            
            print("[ROW \(index)] Updating row with results")
            rows[index].analysis = result
            rows[index].status = .done
            rows[index].bpmMatch = bpmMatch(for: rows[index])
            rows[index].keyMatch = keyMatch(for: rows[index])
            
            print("✓ Row \(index + 1): \(rows[index].fileName) - BPM: \(result.bpm), Key: \(result.key)")
        } catch {
            print("[ROW \(index)] ERROR caught: \(error.localizedDescription)")
            guard rows.indices.contains(index) else {
                print("[ROW \(index)] WARNING: Index out of bounds in catch block")
                return
            }
            rows[index].status = .failed
            rows[index].error = error.localizedDescription
            
            print("✗ Row \(index + 1): \(rows[index].fileName) - Error: \(error.localizedDescription)")
        }
        
        print("[ROW \(index)] analyzeRow() exiting")
    }
    
    nonisolated private func analyzeRowNonisolated(at index: Int) async {
        print("[ROW \(index)] analyzeRowNonisolated() called (nonisolated)")
        
        let rowData: (url: URL, title: String, artist: String, fileName: String)? = await MainActor.run {
            guard rows.indices.contains(index) else {
                print("[ROW \(index)] ERROR: Index out of bounds")
                return nil
            }
            print("[ROW \(index)] Setting status to .running")
            rows[index].status = .running
            let row = rows[index]
            print("[ROW \(index)] File: \(row.fileName)")
            print("[ROW \(index)] URL: \(row.url.path)")
            return (url: row.url, title: row.displayTitle, artist: row.displayArtist, fileName: row.fileName)
        }
        
        guard let rowData else { return }
        guard !rowData.url.path.isEmpty else { return }
        
        let namespace: String = await MainActor.run { defaultNamespace }
        let timeout: TimeInterval = await MainActor.run { rowTimeoutSeconds }
        let clientId = "repertoire-row-\(index + 1)"
        
        var attempt = 0
        while attempt < 2 {
            attempt += 1
            do {
                let serverRunning = await MainActor.run { manager.isServerRunning }
                if !serverRunning {
                    print("[ROW \(index)] Analyzer not running; restarting before attempt \(attempt)")
                    await manager.startServer()
                }
                
                print("[ROW \(index)] Calling manager.analyzeAudioFile… (off main actor, timeout=\(timeout)s, titleOverride=\(rowData.title), artistOverride=\(rowData.artist), clientId=\(clientId), attempt=\(attempt))")
                let result = try await self.manager.analyzeAudioFile(
                    at: rowData.url,
                    skipChunkAnalysis: false,
                    forceFreshAnalysis: true,
                    cacheNamespace: namespace,
                    requestTimeout: timeout,
                    titleOverride: rowData.title,
                    artistOverride: rowData.artist,
                    clientRequestId: clientId
                )
                print("[ROW \(index)] manager.analyzeAudioFile returned successfully")
                
                await MainActor.run {
                    guard rows.indices.contains(index) else {
                        print("[ROW \(index)] WARNING: Index out of bounds after analysis")
                        return
                    }
                    
                    print("[ROW \(index)] Updating row with results")
                    rows[index].analysis = result
                    rows[index].status = .done
                    rows[index].bpmMatch = bpmMatch(for: rows[index])
                    rows[index].keyMatch = keyMatch(for: rows[index])
                    
                    print("✓ Row \(index + 1): \(rows[index].fileName) - BPM: \(result.bpm), Key: \(result.key)")
                }
                return
            } catch {
                let nsError = error as NSError
                if let urlError = error as? URLError, urlError.code == .timedOut {
                    print("[ROW \(index)] ERROR: Network timed out (\(timeout)s) on attempt \(attempt)")
                } else if nsError.domain == NSURLErrorDomain && nsError.code == URLError.timedOut.rawValue {
                    print("[ROW \(index)] ERROR: Network timed out (\(timeout)s) [NSError] on attempt \(attempt)")
                } else {
                    print("[ROW \(index)] ERROR caught on attempt \(attempt): \(error.localizedDescription)")
                }
                
                if attempt < 2 {
                    print("[ROW \(index)] Restarting analyzer after failure; will retry")
                    await manager.restartServer()
                    continue
                }
                
                await MainActor.run {
                    guard rows.indices.contains(index) else {
                        print("[ROW \(index)] WARNING: Index out of bounds in catch block")
                        return
                    }
                    rows[index].status = .failed
                    rows[index].error = error.localizedDescription
                    let message = rows[index].error ?? "Unknown error"
                    print("✗ Row \(index + 1): \(rows[index].fileName) - Error: \(message)")
                }
            }
        }
        
        print("[ROW \(index)] analyzeRowNonisolated() exiting")
    }
}
