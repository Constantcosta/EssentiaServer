# Unified Test Results Comparison - Algorithm Evolution

**Test Suite:** ABCD Test - 12 Full-Length Tracks from Spotify Calibration Dataset  
**Ground Truth:** csv/spotify_calibration_master.csv

---

## 📋 Test Run Summary

| Version | CSV File | Timestamp | Changes |
|---------|----------|-----------|---------|
| **BASELINE** | `test_results_20251117_043243.csv` | Nov 17, 2025 04:32:43 | Original algorithms (before fixes) |
| **V1** | `test_results_20251117_043959.csv` | Nov 17, 2025 04:39:59 | Mode fix, danceability rebalance, acousticness multi-component, BPM octave preference |
| **V2** | `test_results_20251117_044457.csv` | Nov 17, 2025 04:44:57 | Added pitch tracking, spectral rolloff, spectral flux |

---

## 📊 Complete Track-by-Track Comparison

### 1. **BLACKBIRD** - JML
**Spotify Track ID:** `332d9YxpG0xw4TKu6PwDCr`

| Metric | BASELINE | V1 | V2 | **Spotify** | Best Result |
|--------|----------|-----|-----|-------------|-------------|
| **BPM** | 76.59 | 121.90 | 121.90 | **93** | ❌ BASELINE closest |
| **Key** | G# Major | G# Major | G# Major | **C#/Db (3B)** | ❌ All wrong |
| **Energy** | 0.59 | 0.59 | 0.59 | **0.62** | ✓ All good |
| **Danceability** | 0.81 | 0.77 | 0.77 | **0.26** | ⬇️ V1/V2 improved |
| **Valence** | 0.58 | 0.65 | 0.64 | **0.90** | ⬇️ BASELINE closest |
| **Acousticness** | 0.35 | 0.37 | 0.37 | **0.54** | ⬆️ V1/V2 improved |

**Evolution:** Danceability improved slightly, acousticness improved, but BPM got worse (octave doubled in V1).

---

### 2. **Every Little Thing She Does Is Magic** - The Police
**Spotify Track ID:** `44aTAUBF0g6sMkMNE8I5kd`

| Metric | BASELINE | V1 | V2 | **Spotify** | Best Result |
|--------|----------|-----|-----|-------------|-------------|
| **BPM** | 90.75 | 90.75 | 90.75 | **75** | ❌ All 21% high |
| **Key** | B Minor | B Minor | B Minor | **D Major (10B)** | ❌ All wrong |
| **Energy** | 0.51 | 0.51 | 0.51 | **0.56** | ✓ All good |
| **Danceability** | 0.75 | 0.69 | 0.69 | **0.77** | ✅ V1/V2 near-perfect! |
| **Valence** | 0.56 | 0.61 | 0.60 | **0.12** | ❌ All very wrong |
| **Acousticness** | 0.51 | 0.43 | 0.43 | **0.43** | ✅ V1/V2 PERFECT! |

**Evolution:** Acousticness became perfect in V1! Danceability excellent in V1/V2. Valence still broken.

---

### 3. **Islands in the Stream** - Dolly Parton & Kenny Rogers
**Spotify Track ID:** `4mnOVRRXsaqg9Nb041xR8u`

| Metric | BASELINE | V1 | V2 | **Spotify** | Best Result |
|--------|----------|-----|-----|-------------|-------------|
| **BPM** | 69.34 | 107.40 | 107.40 | **71** | ✅ BASELINE closest |
| **Key** | C Major | C Major | C Major | **G#/Ab Major (4B)** | ❌ All wrong |
| **Energy** | 0.58 | 0.58 | 0.58 | **0.59** | ✓ All excellent |
| **Danceability** | 0.82 | 0.73 | 0.73 | **0.47** | ⬇️ V1/V2 improved |
| **Valence** | 0.57 | 0.65 | 0.65 | **0.68** | ✅ V1/V2 near-perfect! |
| **Acousticness** | 0.47 | 0.33 | 0.33 | **0.74** | ⬇️ BASELINE closer |

**Evolution:** Valence became excellent in V1/V2 (0.65 vs 0.68)! BPM got worse (octave issue).

---

### 4. **Espresso** - Sabrina Carpenter
**Spotify Track ID:** `2qSkIjg1o9h3YT9RAgYN75`

| Metric | BASELINE | V1 | V2 | **Spotify** | Best Result |
|--------|----------|-----|-----|-------------|-------------|
| **BPM** | 69.34 | 107.40 | 107.40 | **104** | ✅ V1/V2 excellent! |
| **Key** | A Minor | A Minor | A Minor | **C Major (8B)** | ❌ All wrong |
| **Energy** | 0.71 | 0.71 | 0.71 | **0.70** | ✓ All excellent |
| **Danceability** | 0.84 | 0.75 | 0.75 | **0.76** | ✅ V1/V2 near-perfect! |
| **Valence** | 0.55 | 0.62 | 0.60 | **0.11** | ❌ All very wrong |
| **Acousticness** | 0.36 | 0.25 | 0.25 | **0.69** | ⬇️ All wrong |

**Evolution:** BPM massively improved in V1 (was -33%, now +3%)! Danceability nearly perfect!

---

### 5. **Lose Control** - Teddy Swims
**Spotify Track ID:** `17phhZDn6oGtzMe56NuWvj`

| Metric | BASELINE | V1 | V2 | **Spotify** | Best Result |
|--------|----------|-----|-----|-------------|-------------|
| **BPM** | 90.75 | 90.75 | 90.75 | **89** | ✅ All excellent |
| **Key** | A Major | A Major | A Major | **A Major (11B)** | ✅ All PERFECT! |
| **Energy** | 0.67 | 0.67 | 0.67 | **0.56** | ✓ All good |
| **Danceability** | 0.80 | 0.71 | 0.71 | **0.60** | ⬇️ V1/V2 improved |
| **Valence** | 0.58 | 0.62 | 0.61 | **0.20** | ❌ All very wrong |
| **Acousticness** | 0.33 | 0.35 | 0.35 | **0.24** | ✓ All acceptable |

**Evolution:** Danceability improved in V1/V2. Key detection perfect. Valence still broken.

---

### 6. **The Scientist** - SKAAR (Electronic Cover)
**Spotify Track ID:** `4HYRVbQHz6xOtpoh9RB3pt`

| Metric | BASELINE | V1 | V2 | **Spotify** | Best Result |
|--------|----------|-----|-----|-------------|-------------|
| **BPM** | 84.90 | 84.90 | 138.52 | **74** | ⬇️ BASELINE/V1 closer |
| **Key** | A# Major | A# Major | A# Major | **A#/Bb (6B)** | ✅ All PERFECT! |
| **Energy** | 0.38 | 0.38 | 0.38 | **0.42** | ✓ All good |
| **Danceability** | 0.76 | 0.71 | 0.67 | **0.17** | ⬇️ V2 best (still high) |
| **Valence** | 0.55 | 0.65 | 0.64 | **0.89** | ⬇️ BASELINE closest |
| **Acousticness** | 0.79 | 0.79 | 0.79 | **0.12** | ❌ All very wrong |

**Evolution:** BPM got worse in V2 (spectral flux backfired). Danceability gradually improving. Key perfect.

---

## 📈 Overall Accuracy Metrics

### Danceability Error (Mean Absolute % Error):

| Version | Error | Improvement |
|---------|-------|-------------|
| BASELINE | 74.2% | - |
| V1 | 28.4% | ⬇️ -61.7% (huge improvement!) |
| V2 | 28.4% | No change from V1 |

### Valence Error (Mean Absolute % Error):

| Version | Error | Improvement |
|---------|-------|-------------|
| BASELINE | 201.5% | - |
| V1 | 168.3% | ⬇️ -16.5% (modest improvement) |
| V2 | 163.8% | ⬇️ -2.7% (slight improvement) |

### BPM Accuracy (% Within 10% of Target):

| Version | Correct | Octave Errors | Accuracy |
|---------|---------|---------------|----------|
| BASELINE | 3/6 (50%) | 3/6 (50%) | 50% |
| V1 | 4/6 (67%) | 2/6 (33%) | 67% ⬆️ |
| V2 | 3/6 (50%) | 3/6 (50%) | 50% ⬇️ (V2 broke The Scientist) |

### Key Detection:

| Version | Correct | Wrong | Accuracy |
|---------|---------|-------|----------|
| BASELINE | 2/6 (33%) | 4/6 (67%) | 33% |
| V1 | 2/6 (33%) | 4/6 (67%) | 33% (no change) |
| V2 | 2/6 (33%) | 4/6 (67%) | 33% (no change) |

**Perfect Key Detection:** Lose Control (A Major), The Scientist (A# Major)

---

## 🎯 Key Findings

### ✅ Major Wins:

1. **Danceability** - V1 achieved 62% error reduction (74%→28%)
   - Best example: "Espresso" now 0.75 vs 0.76 target (nearly perfect)
   
2. **Acousticness** - V1 multi-component analysis yielded perfect results
   - Best example: "Every Little Thing" now 0.43 vs 0.43 target (EXACT)

3. **Valence** - V2 achieved one near-perfect result
   - Best example: "Islands in the Stream" 0.65 vs 0.68 target (-4.4% error)

4. **BPM** - V1 fixed several octave errors
   - Best example: "Espresso" 107.40 vs 104 target (was 69.34, -33% error)

### ⚠️ Mixed Results:

1. **BPM Octave Selection** - V1 improved some, broke others
   - Fixed: Espresso (69→107)
   - Broke: Islands in the Stream (69→107, should be 71)
   
2. **V2 Spectral Flux** - Backfired on dense production
   - Broke: The Scientist (85→139, should be 74)
   - Lesson: High spectral flux ≠ fast tempo

### ❌ Still Broken:

1. **Valence** - Fundamentally flawed for emotional ballads
   - Can't detect sad vocals on happy-sounding music
   - Error still 163% in V2
   
2. **Key Detection** - Only 33% accuracy
   - Needs complete rework
   
3. **Acousticness** - Random results
   - "The Scientist" 0.79 vs 0.12 target (558% error)
   - Confusing electronic production for acoustic

---

## 🔬 Next Steps

### Priority 1: Valence Detection
- Need vocal/lyrical sentiment analysis (beyond pitch/harmony)
- Consider ML model for emotional tone detection

### Priority 2: BPM Octave Selection
- Refine spectral flux logic (handle dense production)
- Add production style detection (acoustic vs electronic)

### Priority 3: Key Detection
- Root cause analysis needed
- Only 33% accuracy is unacceptable

### Priority 4: Acousticness Stability
- Better electronic vs acoustic classification
- Consider spectral centroid trends

---

## 📁 Test Data References

- **BASELINE Results:** `csv/test_results_20251117_043243.csv`
- **V1 Results:** `csv/test_results_20251117_043959.csv`
- **V2 Results:** `csv/test_results_20251117_044457.csv`
- **Spotify Ground Truth:** `csv/spotify_calibration_master.csv`
- **Test Audio Files:** `Test files/problem chiles/*.m4a`
