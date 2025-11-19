//
//  TestCExpectedReference.swift
//  MacStudioServerSimulator
//
//  Canonical expected BPM/key values for Test C (12 preview files),
//  aligned with the Python analysis script analyze_test_c_accuracy.py.
//

import Foundation

struct TestCExpectedTrack {
    let bpm: Int
    let key: String
}

/// Expected reference values for Test C comparisons.
/// Keys are the normalized display titles produced by SongTitleNormalizer.clean(_:).
struct TestCExpectedReference {
    static let shared = TestCExpectedReference()
    
    private let expectations: [String: TestCExpectedTrack]
    
    private init() {
        expectations = [
            // Batch 1
            "Prisoner (feat. Dua Lipa)": TestCExpectedTrack(bpm: 128, key: "D# Minor"),
            "Forget You": TestCExpectedTrack(bpm: 127, key: "C"),
            "! (The Song Formerly Known As)": TestCExpectedTrack(bpm: 115, key: "B"),
            "1000x": TestCExpectedTrack(bpm: 112, key: "G# Major"),
            "2 Become 1": TestCExpectedTrack(bpm: 144, key: "F# Major"),
            "3AM": TestCExpectedTrack(bpm: 108, key: "G# Major"),
            
            // Batch 2
            "4ever": TestCExpectedTrack(bpm: 144, key: "F Minor"),
            "9 to 5": TestCExpectedTrack(bpm: 107, key: "F# Major"),
            "A Thousand Miles": TestCExpectedTrack(bpm: 149, key: "F# Major"),
            "A Thousand Years": TestCExpectedTrack(bpm: 132, key: "A# Major"),
            "A Whole New World (End Title)": TestCExpectedTrack(bpm: 114, key: "A Major"),
            "About Damn Time": TestCExpectedTrack(bpm: 111, key: "D# Minor"),
        ]
    }
    
    /// Lookup expected BPM/key for a given normalized song title.
    func expected(forSongTitle title: String) -> TestCExpectedTrack? {
        return expectations[title]
    }
}

