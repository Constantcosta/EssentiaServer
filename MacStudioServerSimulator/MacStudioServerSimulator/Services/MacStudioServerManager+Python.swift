import Foundation
import OSLog
#if os(macOS)
import AppKit
#endif

#if os(macOS)
private let pythonPathLogger = Logger(subsystem: "com.macstudio.serverapp", category: "PythonPath")

private enum PythonEnvironmentError: LocalizedError {
    case virtualEnvironmentMissing(URL)
    case overrideInvalid(String)

    var errorDescription: String? {
        switch self {
        case .virtualEnvironmentMissing(let url):
            return "Virtual environment Python not found at \(url.path)."
        case .overrideInvalid(let path):
            return "Python override at \(path) is not executable."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .virtualEnvironmentMissing:
            return """
            Run tools/verify_python_setup.sh or recreate the virtual environment with:
            python3.12 -m venv .venv && .venv/bin/pip install -r requirements-calibration.txt
            """
        case .overrideInvalid:
            return "Update the override via defaults write com.macstudio.serversimulator MacStudioServerPython \"/path/to/python\" or delete the key to fall back to the repo .venv."
        }
    }
}

extension MacStudioServerManager {
    func resolvePythonExecutableURL() throws -> URL {
        let repoRoot = serverScriptURL.deletingLastPathComponent().deletingLastPathComponent()
        let venvPython = repoRoot.appendingPathComponent(".venv/bin/python")
        let defaults = UserDefaults.standard
        if FileManager.default.fileExists(atPath: venvPython.path) {
            if !FileManager.default.isExecutableFile(atPath: venvPython.path) {
                pythonPathLogger.warning("Virtual environment Python exists but is not marked executable — attempting launch anyway.")
            }
            if defaults.string(forKey: "MacStudioServerPython") != venvPython.path {
                defaults.set(venvPython.path, forKey: "MacStudioServerPython")
                pythonPathLogger.info("Using virtual environment Python at \(venvPython.path, privacy: .public)")
            }
            return venvPython
        }
        if let override = defaults.string(forKey: "MacStudioServerPython"),
           !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                let overrideURL = URL(fileURLWithPath: expanded)
                pythonPathLogger.info("Using custom Python override at \(overrideURL.path, privacy: .public)")
                return overrideURL
            }
            throw PythonEnvironmentError.overrideInvalid(expanded)
        }
        throw PythonEnvironmentError.virtualEnvironmentMissing(venvPython)
    }

    func pythonResolutionErrorMessage(for error: Error) -> String {
        guard let localized = error as? LocalizedError else {
            return error.localizedDescription
        }
        if let description = localized.errorDescription, let suggestion = localized.recoverySuggestion {
            return "\(description)\n\n\(suggestion)"
        }
        return localized.errorDescription ?? error.localizedDescription
    }

    func appendLaunchConfirmationToServerLog(pythonPath: String) {
        let logDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/AudioAnalysisCache", isDirectory: true)
        let logURL = logDirectory.appendingPathComponent("server.log")
        if !FileManager.default.fileExists(atPath: logDirectory.path) {
            try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: nil)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] MacStudioServerSimulator: Launching analyzer via \(pythonPath)\n"
        guard let data = line.data(using: .utf8) else { return }
        do {
            let fileHandle = try FileHandle(forWritingTo: logURL)
            defer { try? fileHandle.close() }
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
        } catch {
            pythonPathLogger.warning("Failed to append launch confirmation to server.log: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
