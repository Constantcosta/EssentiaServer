import Foundation
#if os(macOS)
import AppKit
#endif

// Real calibration workflow: analyze staged songs, export analyzer cache, build
// the calibration Parquet via Python, then optionally compare against Spotify.
extension MacStudioServerManager {
    /// Run the full calibration sweep and build a Parquet dataset + review CSV.
    func runCalibrationSuite(featureSetVersion: String, notes: String) async {
        guard !isCalibrationRunning else { return }
        guard !calibrationSongs.isEmpty else {
            calibrationError = CalibrationWorkflowError.noSongs.errorDescription
            return
        }
        guard isServerRunning else {
            calibrationError = "Start the analyzer server before running calibration."
            return
        }

        isCalibrationRunning = true
        calibrationError = nil
        calibrationLog = []
        calibrationProgress = 0.0
        lastCalibrationComparison = nil
        lastCalibrationComparisonURL = nil

        let timestamp = calibrationFilenameFormatter.string(from: Date())
        let cacheNamespace = "calibration_\(timestamp)"

        do {
            let pythonURL = try resolvePythonExecutableURL()
            let builderScript = repoRootURL.appendingPathComponent("tools/build_calibration_dataset.py")
            let spotifyMetrics = repoRootURL.appendingPathComponent("csv/spotify metrics.csv")
            let datasetURL = repoRootURL
                .appendingPathComponent("data/calibration", isDirectory: true)
                .appendingPathComponent("mac_gui_calibration_\(timestamp).parquet")
            ensureDirectoryExists(at: datasetURL.deletingLastPathComponent())
            ensureDirectoryExists(at: calibrationExportsDirectory)

            guard FileManager.default.fileExists(atPath: builderScript.path) else {
                throw CalibrationWorkflowError.builderScriptMissing(builderScript.path)
            }
            guard FileManager.default.fileExists(atPath: spotifyMetrics.path) else {
                throw CalibrationWorkflowError.spotifyMetricsMissing(spotifyMetrics.path)
            }

            calibrationLog.append("🚀 Calibration run started (\(calibrationSongs.count) songs).")

            // Analyze every staged song into a dedicated cache namespace.
            let perSongIncrement = calibrationSongs.isEmpty ? 0.0 : 0.5 / Double(calibrationSongs.count)
            for (index, song) in calibrationSongs.enumerated() {
                calibrationLog.append("🎧 Analyzing \(song.title) — \(song.artist)")
                _ = try await analyzeAudioFile(
                    at: fileURL(for: song),
                    skipChunkAnalysis: false,
                    forceFreshAnalysis: true,
                    cacheNamespace: cacheNamespace
                )
                calibrationProgress = Double(index + 1) * perSongIncrement
            }

            // Export the analyzer cache for this namespace to CSV.
            calibrationLog.append("📤 Exporting analyzer cache (namespace: \(cacheNamespace))")
            let exportURL = try await exportCalibrationCache(
                namespace: cacheNamespace,
                preferredFilename: "calibration_run_\(timestamp).csv"
            )
            lastCalibrationExportURL = exportURL
            calibrationProgress = max(calibrationProgress, 0.55)

            // Run the Python builder to create the Parquet + human review CSV.
            calibrationLog.append("🛠️ Building calibration dataset (feature set \(featureSetVersion))")
            let builderResult = try await runPythonScript(
                pythonURL: pythonURL,
                arguments: [
                    builderScript.path,
                    "--analyzer-export", exportURL.path,
                    "--spotify-metrics", spotifyMetrics.path,
                    "--feature-set-version", featureSetVersion,
                    "--notes", notes,
                    "--output", datasetURL.path
                ]
            )
            appendLogLines(builderResult.output)
            guard builderResult.status == 0 else {
                throw CalibrationWorkflowError.processFailed(builderResult.output)
            }

            lastCalibrationOutputURL = datasetURL
            calibrationProgress = 1.0
            calibrationLog.append("✅ Calibration dataset ready: \(datasetURL.lastPathComponent)")
        } catch {
            calibrationError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            calibrationLog.append("❌ Calibration error: \(calibrationError ?? error.localizedDescription)")
        }

        isCalibrationRunning = false
    }

    /// Compare the latest calibration dataset against Spotify references.
    func compareLatestCalibrationDataset() async {
        guard let datasetURL = lastCalibrationOutputURL else {
            calibrationError = "No calibration dataset available to compare."
            return
        }
        guard !isComparingCalibration else { return }

        isComparingCalibration = true
        calibrationError = nil

        do {
            let pythonURL = try resolvePythonExecutableURL()
            let compareScript = repoRootURL.appendingPathComponent("tools/compare_calibration_subset.py")
            guard FileManager.default.fileExists(atPath: compareScript.path) else {
                throw CalibrationWorkflowError.comparisonScriptMissing(compareScript.path)
            }

            let comparisonURL = makeComparisonReportURL(for: datasetURL)
            calibrationLog.append("📊 Comparing against Spotify → \(comparisonURL.lastPathComponent)")

            let compareResult = try await runPythonScript(
                pythonURL: pythonURL,
                arguments: [
                    compareScript.path,
                    "--dataset", datasetURL.path,
                    "--csv-output", comparisonURL.path
                ]
            )
            appendLogLines(compareResult.output)
            guard compareResult.status == 0 else {
                throw CalibrationWorkflowError.processFailed(compareResult.output)
            }

            lastCalibrationComparison = compareResult.output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            lastCalibrationComparisonURL = comparisonURL
        } catch {
            calibrationError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            calibrationLog.append("❌ Comparison error: \(calibrationError ?? error.localizedDescription)")
        }

        isComparingCalibration = false
    }

    // MARK: - Helpers

    private func exportCalibrationCache(namespace: String, preferredFilename: String) async throws -> URL {
        guard let requestURL = URL(string: "\(baseURL)/cache/export") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(namespace, forHTTPHeaderField: "X-Cache-Namespace")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CalibrationWorkflowError.processFailed(String(data: data, encoding: .utf8) ?? "")
        }

        let filename = suggestedFilename(from: httpResponse) ?? preferredFilename
        let destination = calibrationExportsDirectory.appendingPathComponent(filename)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private func runPythonScript(pythonURL: URL, arguments: [String]) async throws -> (status: Int32, output: String) {
        let workingDirectory = repoRootURL
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    let process = Process()
                    process.executableURL = pythonURL
                    process.arguments = arguments
                    process.currentDirectoryURL = workingDirectory
                    var environment = ProcessInfo.processInfo.environment
                    environment["PYTHONUNBUFFERED"] = "1"
                    process.environment = environment

                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe

                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: (process.terminationStatus, output))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func appendLogLines(_ output: String) {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !lines.isEmpty {
            calibrationLog.append(contentsOf: lines)
        }
    }

    func suggestedFilename(from response: HTTPURLResponse) -> String? {
        guard let disposition = response.value(forHTTPHeaderField: "Content-Disposition") else {
            return nil
        }
        for part in disposition.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("filename=") {
                let value = trimmed.dropFirst("filename=".count)
                return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }
}
