import Foundation

struct AnalysisRow {
    let rawSong: String
    let artist: String
    let fileType: String
    let bpm: Int?
    let key: String?
}

func parseCSVRow(_ row: String) -> [String] {
    var columns: [String] = []
    var current = ""
    var insideQuotes = false
    for char in row {
        if char == "\"" {
            insideQuotes.toggle()
            continue
        }
        if char == "," && !insideQuotes {
            columns.append(current)
            current = ""
        } else {
            current.append(char)
        }
    }
    columns.append(current)
    return columns
}

func loadAnalysisRows(from url: URL) throws -> [AnalysisRow] {
    let csvString = try String(contentsOf: url, encoding: .utf8)
    let rows = csvString.components(separatedBy: .newlines).filter { !$0.isEmpty }
    guard rows.count > 1 else { return [] }
    var results: [AnalysisRow] = []
    for row in rows.dropFirst() {
        let columns = parseCSVRow(row)
        guard columns.count >= 8 else { continue }
        let rawSong = columns[1].replacingOccurrences(of: "\"", with: "")
        let artist = columns[2].replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespaces)
        let fileType = columns[3].trimmingCharacters(in: .whitespaces)
        let bpmValue: Int? = {
            if let bpmDouble = Double(columns[6]) {
                return Int(round(bpmDouble))
            }
            return nil
        }()
        let keyValue = columns[7].trimmingCharacters(in: .whitespaces)
        let key = keyValue.isEmpty ? nil : keyValue
        results.append(
            AnalysisRow(
                rawSong: rawSong,
                artist: artist,
                fileType: fileType,
                bpm: bpmValue,
                key: key
            )
        )
    }
    return results
}

func latestAnalysisCSV(in directory: URL) throws -> URL {
    let fileManager = FileManager.default
    let contents = try fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
    )
    let candidates = contents.filter { url in
        url.lastPathComponent.hasPrefix("test_results_") && url.pathExtension == "csv"
    }
    guard !candidates.isEmpty else {
        throw NSError(domain: "SpotifyParsing", code: 1, userInfo: [NSLocalizedDescriptionKey: "No test_results_*.csv files found in \(directory.path)"])
    }
    let sorted = try candidates.sorted { lhs, rhs in
        let lhsDate = try lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
        let rhsDate = try rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
        return lhsDate < rhsDate
    }
    return sorted.last!
}

struct Arguments {
    let csvPath: URL
    let repoRoot: URL
}

func parseArguments() throws -> Arguments {
    let fm = FileManager.default
    let repoRoot = URL(fileURLWithPath: fm.currentDirectoryPath)
    let csvDir = repoRoot.appendingPathComponent("csv", isDirectory: true)
    var specifiedPath: URL?
    var index = 1
    let args = CommandLine.arguments
    while index < args.count {
        let arg = args[index]
        if arg == "--file" || arg == "-f" {
            let nextIndex = index + 1
            guard nextIndex < args.count else {
                throw NSError(domain: "SpotifyParsing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing value for \(arg)"])
            }
            let provided = args[nextIndex]
            let url = URL(fileURLWithPath: provided, relativeTo: repoRoot).standardized
            specifiedPath = url
            index = nextIndex + 1
            continue
        }
        index += 1
    }
    let csvURL: URL
    if let specifiedPath {
        csvURL = specifiedPath
    } else {
        csvURL = try latestAnalysisCSV(in: csvDir)
    }
    return Arguments(csvPath: csvURL, repoRoot: repoRoot)
}

func resolveSpotifyData(base repoRoot: URL) -> SpotifyReferenceData {
    let dataDir = repoRoot.appendingPathComponent("MacStudioServerSimulator/MacStudioServerSimulator", isDirectory: true)
    let resolver: (String, String) -> URL? = { filename, ext in
        let candidate = dataDir.appendingPathComponent("\(filename).\(ext)")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }
    return SpotifyReferenceData(resourceResolver: resolver)
}

func run() throws {
    let arguments = try parseArguments()
    print("🔍 Using analysis CSV: \(arguments.csvPath.path)")
    let analysisRows = try loadAnalysisRows(from: arguments.csvPath)
    guard !analysisRows.isEmpty else {
        print("⚠️ No analysis rows found in \(arguments.csvPath.lastPathComponent)")
        return
    }
    let spotifyData = resolveSpotifyData(base: arguments.repoRoot)
    let previewRows = analysisRows.filter { $0.fileType.lowercased() == "preview" }
    var matched: [(AnalysisRow, SpotifyTrack)] = []
    var missing: [AnalysisRow] = []
    for row in previewRows {
        let canonicalTitle = SongTitleNormalizer.clean(row.rawSong)
        let track = spotifyData.findTrack(song: canonicalTitle, artist: row.artist)
        if let track {
            matched.append((row, track))
            print("✅ \(row.rawSong) → \(canonicalTitle) → Spotify: \(track.song) by \(track.artist)")
        } else {
            missing.append(row)
            print("⚠️ \(row.rawSong) → \(canonicalTitle) (no Spotify match)")
        }
    }
    print("\nSummary:")
    print("  Preview rows analyzed: \(previewRows.count)")
    print("  Matched Spotify references: \(matched.count)")
    print("  Missing matches: \(missing.count)")
    if !missing.isEmpty {
        print("\nMissing entries:")
        for row in missing {
            print("  • \(row.rawSong) (artist: \(row.artist))")
        }
    }
}

@main
struct SpotifyParsingTestRunner {
    static func main() {
        do {
            try run()
        } catch {
            fputs("❌ Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
