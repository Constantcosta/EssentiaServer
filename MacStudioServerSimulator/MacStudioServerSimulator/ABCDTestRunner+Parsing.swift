//
//  ABCDTestRunner+Parsing.swift
//  MacStudioServerSimulator
//
//  Output parsing helpers for ABCD tests.
//

import Foundation

@MainActor
extension ABCDTestRunner {
    func stripANSICodes(from text: String) -> String {
        let pattern = "\u{001B}\\[[0-9;]*m"
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
    
    func extractAnalysisResults(from output: String) -> [AnalysisResult] {
        let cleanOutput = stripANSICodes(from: output).replacingOccurrences(of: "\r", with: "\n")
        guard let regex = try? NSRegularExpression(
            pattern: #"\s*\d+\.\s+(.+?)\s+\|\s+BPM:\s*([\d.]+|N/A)\s+\|\s+Key:\s*([^|]+?)\s+\|"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let range = NSRange(cleanOutput.startIndex..<cleanOutput.endIndex, in: cleanOutput)
        var results: [AnalysisResult] = []
        regex.enumerateMatches(in: cleanOutput, options: [], range: range) { match, _, _ in
            guard let match = match,
                  let songRange = Range(match.range(at: 1), in: cleanOutput),
                  let bpmRange = Range(match.range(at: 2), in: cleanOutput),
                  let keyRange = Range(match.range(at: 3), in: cleanOutput) else { return }
            let rawSong = String(cleanOutput[songRange]).trimmingCharacters(in: .whitespaces)
            let song = cleanSongTitle(rawSong)
            let bpmString = String(cleanOutput[bpmRange]).trimmingCharacters(in: .whitespaces)
            let keyString = String(cleanOutput[keyRange]).trimmingCharacters(in: .whitespaces)
            let bpmValue: Int? = {
                if let bpmDouble = Double(bpmString) {
                    return Int(round(bpmDouble))
                }
                return nil
            }()
            let keyValue = keyString.isEmpty || keyString == "N/A" ? nil : keyString
            let result = AnalysisResult(
                song: song,
                artist: "Unknown",
                bpm: bpmValue,
                key: keyValue,
                success: true,
                duration: 0
            )
            results.append(result)
        }
        return results
    }
    
    func loadAnalysisResults(fromCSV csvPath: String) -> [AnalysisResult] {
        var resolvedPath = csvPath
        if !resolvedPath.hasPrefix("/") {
            resolvedPath = (projectPath as NSString).appendingPathComponent(csvPath)
        }
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            return []
        }
        guard let csvString = try? String(contentsOfFile: resolvedPath, encoding: .utf8) else {
            return []
        }
        let rows = csvString.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard rows.count > 1 else {
            return []
        }
        var results: [AnalysisResult] = []
        for row in rows.dropFirst() {
            let columns = parseCSVRow(row)
            guard columns.count >= 10 else { continue }
            let rawSong = columns[1].replacingOccurrences(of: "\"", with: "")
            let song = cleanSongTitle(rawSong)
            let artist = columns[2].replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
            let successValue = columns[4].lowercased()
            let success = successValue == "true" || successValue == "1" || successValue == "yes"
            let duration = Double(columns[5]) ?? 0
            let bpmValue: Int? = {
                if let bpmDouble = Double(columns[6]) {
                    return Int(round(bpmDouble))
                }
                return nil
            }()
            let keyValue = columns[7].trimmingCharacters(in: .whitespaces)
            let key = keyValue.isEmpty ? nil : keyValue
            let result = AnalysisResult(
                song: song,
                artist: artist,
                bpm: bpmValue,
                key: key,
                success: success,
                duration: duration
            )
            results.append(result)
        }
        return results
    }
    
    func cleanSongTitle(_ raw: String) -> String {
        SongTitleNormalizer.clean(raw)
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
}

