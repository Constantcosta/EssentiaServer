//
//  RepertoireReferenceParsers.swift
//  MacStudioServerSimulator
//
//  CSV parsing for BPM and truth reference sheets.
//

import Foundation

struct BpmReferenceRow {
    let songTitle: String
    let artist: String
    let googleBpm: Double
    let songBpm: Double?
    let deezerBpm: Double?
    let deezerApiBpm: Double?
}

enum BpmReferenceParser {
    static func parse(text: String) throws -> [BpmReferenceRow] {
        var lines = text.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return [] }
        let header = parseRow(lines.removeFirst())
        guard let titleIdx = header.firstIndex(of: "Song Title"),
              let artistIdx = header.firstIndex(of: "Artist"),
              let googleIdx = header.firstIndex(of: "Google BPM") else {
            throw NSError(domain: "csv", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing required columns (Song Title, Artist, Google BPM)"])
        }
        let songBpmIdx = header.firstIndex(of: "SongBPM BPM")
        let deezerBpmIdx = header.firstIndex(of: "Deezer BPM")
        let deezerApiBpmIdx = header.firstIndex(of: "Deezer API BPM")
        
        var result: [BpmReferenceRow] = []
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let cols = parseRow(line)
            guard cols.count > max(titleIdx, artistIdx, googleIdx) else { continue }
            let title = cols[titleIdx]
            let artist = cols[artistIdx]
            guard let google = Double(cols[googleIdx]) else { continue }
            let songBpm: Double?
            if let idx = songBpmIdx, idx < cols.count {
                songBpm = Double(cols[idx])
            } else {
                songBpm = nil
            }
            let deezerBpm: Double?
            if let idx = deezerBpmIdx, idx < cols.count {
                deezerBpm = Double(cols[idx])
            } else {
                deezerBpm = nil
            }
            let deezerApiBpm: Double?
            if let idx = deezerApiBpmIdx, idx < cols.count {
                deezerApiBpm = Double(cols[idx])
            } else {
                deezerApiBpm = nil
            }
            result.append(
                BpmReferenceRow(
                    songTitle: title,
                    artist: artist,
                    googleBpm: google,
                    songBpm: songBpm,
                    deezerBpm: deezerBpm,
                    deezerApiBpm: deezerApiBpm
                )
            )
        }
        return result
    }
    
    private static func parseRow(_ row: String) -> [String] {
        var columns: [String] = []
        var current = ""
        var insideQuotes = false
        for char in row {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
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

struct TruthReferenceRow {
    let song: String
    let artist: String
    let bpm: Double
    let key: String
    let notes: String?
}

enum TruthReferenceParser {
    static func parse(text: String) throws -> [TruthReferenceRow] {
        var lines = text.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return [] }
        let header = parseRow(lines.removeFirst())
        guard let songIdx = header.firstIndex(of: "Song"),
              let artistIdx = header.firstIndex(of: "Artist"),
              let bpmIdx = header.firstIndex(of: "BPM"),
              let keyIdx = header.firstIndex(of: "Key") else {
            throw NSError(domain: "csv", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing required columns (Song, Artist, BPM, Key)"])
        }
        let notesIdx = header.firstIndex(of: "Notes") ?? header.firstIndex(of: "Comment")
        
        var result: [TruthReferenceRow] = []
        for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let cols = parseRow(line)
            guard cols.count > max(songIdx, artistIdx, bpmIdx, keyIdx) else { continue }
            guard let bpm = Double(cols[bpmIdx]) else { continue }
            let song = cols[songIdx]
            let artist = cols[artistIdx]
            let key = cols[keyIdx]
            let notes: String?
            if let idx = notesIdx, idx < cols.count {
                let value = cols[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                notes = value.isEmpty ? nil : value
            } else {
                notes = nil
            }
            result.append(
                TruthReferenceRow(
                    song: song,
                    artist: artist,
                    bpm: bpm,
                    key: key,
                    notes: notes
                )
            )
        }
        return result
    }
    
    private static func parseRow(_ row: String) -> [String] {
        var columns: [String] = []
        var current = ""
        var insideQuotes = false
        for char in row {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
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
