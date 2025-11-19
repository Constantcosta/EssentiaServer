#!/usr/bin/env python3
"""
Analyze Test C results to identify accuracy issues.
Reads from the most recent CSV file in the csv/ directory.
"""
import sys
from pathlib import Path

# Add tools directory to path for key_utils
sys.path.insert(0, str(Path(__file__).parent / "tools"))
from key_utils import keys_match_fuzzy

# Expected Spotify values for the 12 preview files (from handover docs and Spotify data)
EXPECTED_VALUES = {
    # Batch 1 (first 6 songs)
    "Cyrus_Prisoner__feat__Dua_Lipa_": {"bpm": 128, "key": "D# Minor"},  # Was D#/Eb minor in Spotify
    "Green_Forget_You": {"bpm": 127, "key": "C"},  # Actual Spotify value
    "___Song_Fomerly_Known_As_": {"bpm": 115, "key": "B"},  # Actual Spotify value (was C# Major in earlier)
    "Smith___Broods_1000x": {"bpm": 112, "key": "G# Major"},  # Was G#/Ab
    "Girls_2_Become_1": {"bpm": 144, "key": "F# Major"},  # Was F#/Gb - this had octave error at 95 BPM
    "20_3am": {"bpm": 108, "key": "G# Major"},  # Was G#/Ab - Matchbox Twenty
    
    # Batch 2 (songs 7-12)
    "Veronicas_4ever_": {"bpm": 144, "key": "F Minor"},  # From cache export: 143.555 BPM
    "Parton_9_to_5": {"bpm": 107, "key": "F# Major"},  # Dolly Parton
    "Carlton_A_Thousand_Miles": {"bpm": 149, "key": "F# Major"},  # Vanessa Carlton
    "Perri_A_Thousand_Years": {"bpm": 132, "key": "A# Major"},  # Christina Perri (B♭ Major)
    "A_Whole_New_World": {"bpm": 114, "key": "A Major"},  # ZAYN
    "About_Damn_Time_": {"bpm": 111, "key": "D# Minor"},  # Lizzo (D#/Eb)
}

# Actual Test C results from latest run (after chroma peak fix for preview clips)
ACTUAL_VALUES = {
    # Batch 1
    "Cyrus_Prisoner__feat__Dua_Lipa_": {"bpm": 126.43, "key": "D# Minor"},
    "Green_Forget_You": {"bpm": 126.43, "key": "C Major"},  # FIXED! Was G Major, now C Major
    "___Song_Fomerly_Known_As_": {"bpm": 117.78, "key": "F# Minor"},
    "Smith___Broods_1000x": {"bpm": 114.02, "key": "G# Major"},
    "Girls_2_Become_1": {"bpm": 143.55, "key": "F# Major"},  # FIXED! Was 137.00, now 143.55 (calibration bypass)
    "20_3am": {"bpm": 110.57, "key": "G# Major"},  # FIXED! Was 189.87, now 110.57
    
    # Batch 2
    "Veronicas_4ever_": {"bpm": 143.55, "key": "F Minor"},  # FIXED! Was 137.00, now 143.55 (calibration bypass)
    "Parton_9_to_5": {"bpm": 107.40, "key": "F# Major"},
    "Carlton_A_Thousand_Miles": {"bpm": 148.75, "key": "B Major"},  # Changed from F# to B (fifth-related)
    "Perri_A_Thousand_Years": {"bpm": 131.44, "key": "A# Major"},  # FIXED! Was 164.49, now 131.44
    "A_Whole_New_World": {"bpm": 114.02, "key": "A Major"},
    "About_Damn_Time_": {"bpm": 110.57, "key": "D# Minor"},
}

def compare_bpm(expected: float, actual: float, tolerance: float = 3.0) -> tuple[bool, str]:
    """Compare BPM with tolerance, checking for octave errors."""
    diff = abs(expected - actual)
    
    # Check if within tolerance
    if diff <= tolerance:
        return True, "exact"
    
    # Check for octave errors (2x or 0.5x)
    half_speed = abs(expected - actual * 2)
    double_speed = abs(expected - actual / 2)
    
    if half_speed <= tolerance:
        return False, f"half_speed (actual: {actual:.1f}, should be ~{expected})"
    elif double_speed <= tolerance:
        return False, f"double_speed (actual: {actual:.1f}, should be ~{expected})"
    else:
        return False, f"off (actual: {actual:.1f}, expected: {expected}, diff: {diff:.1f})"

def compare_key(expected: str, actual: str) -> tuple[bool, str]:
    """Compare keys with enharmonic matching using key_utils."""
    match, reason = keys_match_fuzzy(actual, expected)
    
    if match:
        return True, reason
    
    # For non-matches, provide more context
    return False, f"{reason} (actual: {actual}, expected: {expected})"

def analyze_accuracy():
    """Analyze accuracy of Test C results by reading the latest CSV file."""
    import pandas as pd
    from pathlib import Path
    
    # Find the most recent test results CSV
    csv_dir = Path(__file__).parent / "csv"
    csv_files = sorted(csv_dir.glob("test_results_*.csv"), key=lambda p: p.stat().st_mtime, reverse=True)
    
    if not csv_files:
        print("❌ No test results CSV files found!")
        return
    
    latest_csv = csv_files[0]
    print(f"Reading results from: {latest_csv.name}")
    print()
    
    # Read the CSV
    df = pd.read_csv(latest_csv)
    
    # Extract actual values from CSV
    actual_values = {}
    for _, row in df.iterrows():
        song_name = row['song_title']
        actual_values[song_name] = {
            'bpm': float(row['bpm']),
            'key': str(row['key'])
        }
    
    bpm_correct = 0
    key_correct = 0
    total = len(EXPECTED_VALUES)
    
    print("=" * 100)
    print("TEST C ACCURACY ANALYSIS - 12 Preview Files")
    print("=" * 100)
    print()
    
    issues = []
    
    for song_name in EXPECTED_VALUES:
        expected = EXPECTED_VALUES[song_name]
        
        if song_name not in actual_values:
            print(f"⚠️  {song_name} - NOT FOUND in results!")
            continue
            
        actual = actual_values[song_name]
        
        # Compare BPM
        bpm_match, bpm_reason = compare_bpm(expected["bpm"], actual["bpm"])
        if bpm_match:
            bpm_correct += 1
            bpm_status = "✅"
        else:
            bpm_status = "❌"
            issues.append({
                "song": song_name,
                "type": "BPM",
                "expected": expected["bpm"],
                "actual": actual["bpm"],
                "reason": bpm_reason
            })
        
        # Compare Key
        key_match, key_reason = compare_key(expected["key"], actual["key"])
        if key_match:
            key_correct += 1
            key_status = "✅"
        else:
            key_status = "❌"
            issues.append({
                "song": song_name,
                "type": "Key",
                "expected": expected["key"],
                "actual": actual["key"],
                "reason": key_reason
            })
        
        # Print song result
        print(f"{song_name[:40]:40} | BPM: {bpm_status} {actual['bpm']:6.1f} (exp: {expected['bpm']:3}) | Key: {key_status} {actual['key']:10} (exp: {expected['key']:10})")
        if not bpm_match:
            print(f"                                           └─ BPM: {bpm_reason}")
        if not key_match:
            print(f"                                           └─ Key: {key_reason}")
    
    print()
    print("=" * 100)
    print("SUMMARY")
    print("=" * 100)
    print(f"BPM Accuracy:  {bpm_correct}/{total} ({bpm_correct/total*100:.1f}%)")
    print(f"Key Accuracy:  {key_correct}/{total} ({key_correct/total*100:.1f}%)")
    print(f"Overall:       {bpm_correct + key_correct}/{total * 2} ({(bpm_correct + key_correct)/(total * 2)*100:.1f}%)")
    print()
    
    # Group issues by type
    octave_errors = [i for i in issues if "speed" in i.get("reason", "")]
    key_errors = [i for i in issues if i["type"] == "Key"]
    other_bpm = [i for i in issues if i["type"] == "BPM" and "speed" not in i.get("reason", "")]
    
    if octave_errors:
        print("OCTAVE ERRORS (Priority 1):")
        for issue in octave_errors:
            print(f"  • {issue['song'][:35]:35} - {issue['reason']}")
        print()
    
    if other_bpm:
        print("OTHER BPM ERRORS (Priority 2):")
        for issue in other_bpm:
            print(f"  • {issue['song'][:35]:35} - {issue['reason']}")
        print()
    
    if key_errors:
        print("KEY ERRORS (Priority 3):")
        for issue in key_errors:
            print(f"  • {issue['song'][:35]:35} - {issue['reason']}")
        print()
    
    print("=" * 100)
    print()
    
    # Calculate if we've hit 100% target
    if bpm_correct == total and key_correct == total:
        print("🎉 100% ACCURACY ACHIEVED! 🎉")
    else:
        print(f"Target: 100% (24/24 correct)")
        print(f"Current: {(bpm_correct + key_correct)/(total * 2)*100:.1f}% ({bpm_correct + key_correct}/24 correct)")
        print(f"Remaining: {24 - (bpm_correct + key_correct)} issues to fix")

if __name__ == "__main__":
    analyze_accuracy()
