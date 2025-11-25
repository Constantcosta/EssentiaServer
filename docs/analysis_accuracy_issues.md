# Analysis Accuracy Issues - BASELINE Results (Before Improvements)

**Test Run:** Initial analysis (csv/test_results_20251117_043243.csv)  
**Date:** November 17, 2025  
**Algorithm Version:** BASELINE (before fixes)  
**Test Set:** 12 full-length tracks from Spotify calibration dataset

---

## 📊 Test Results vs Spotify Ground Truth

### BATCH 1 - Tracks 1-6

#### 1. **BLACKBIRD** - JML
**Spotify Track ID:** `332d9YxpG0xw4TKu6PwDCr`  
**File:** `Test files/problem chiles/BLACKBIRD.m4a`

| Metric | Our BASELINE | Spotify Reference | Error | Notes |
|--------|--------------|-------------------|-------|-------|
| BPM | 76.59 | **93** | -17.7% | Major tempo detection failure |
| Key | G# Major | **C#/Db (3B)** | Wrong | Off by 5 semitones |
| Energy | 0.59 | 0.62 | -4.8% | Acceptable |
| Danceability | 0.81 | 0.26 | **+212%** | Massively overestimated |
| Valence | 0.58 | 0.90 | -35.6% | Underestimated happiness |
| Acousticness | 0.35 | 0.54 | -35.2% | Underestimated |

---

#### 2. **Every Little Thing She Does Is Magic** - The Police
**Spotify Track ID:** `44aTAUBF0g6sMkMNE8I5kd`  
**Album:** Ghost In The Machine (Remastered 2003)

| Metric | Our BASELINE | Spotify Reference | Error | Notes |
|--------|--------------|-------------------|-------|-------|
| BPM | 90.75 | **75** | +21% | Likely doubled tempo |
| Key | B Minor | **D Major (10B)** | Wrong | Relative minor confusion |
| Energy | 0.51 | 0.56 | -8.9% | Acceptable |
| Danceability | 0.75 | 0.77 | -2.6% | Good! |
| Valence | 0.56 | 0.12 | **+367%** | Massive error - not a happy song |
| Acousticness | 0.51 | 0.43 | +18.6% | Acceptable |

---

#### 3. **Islands in the Stream** - Dolly Parton & Kenny Rogers
**Spotify Track ID:** `4mnOVRRXsaqg9Nb041xR8u`  
**Key in Camelot:** 4B

| Metric | Our BASELINE | Spotify Reference | Error | Notes |
|--------|--------------|-------------------|-------|-------|
| BPM | 69.34 | **71** | -2.3% | Good! |
| Key | C Major | **G#/Ab Major (4B)** | Wrong | Off by 8 semitones |
| Energy | 0.58 | 0.59 | -1.7% | Excellent! |
| Danceability | 0.82 | 0.47 | **+74%** | Overestimated |
| Valence | 0.57 | 0.68 | -16.2% | Acceptable |
| Acousticness | 0.47 | 0.74 | -36.5% | Missed acoustic nature |

---

#### 4. **Espresso** - Sabrina Carpenter
**Spotify Track ID:** `2qSkIjg1o9h3YT9RAgYN75`  
**Album:** Espresso (2024)  
**Key in Camelot:** 8B

| Metric | Our BASELINE | Spotify Reference | Error | Notes |
|--------|--------------|-------------------|-------|-------|
| BPM | 69.34 | **104** | -33.3% | Halved tempo detection |
| Key | A Minor | **C Major (8B)** | Wrong | Relative minor error |
| Energy | 0.71 | 0.70 | +1.4% | Excellent! |
| Danceability | 0.84 | 0.76 | +10.5% | Acceptable |
| Valence | 0.55 | 0.11 | **+400%** | Massive error |
| Acousticness | 0.36 | 0.69 | -47.8% | Major error |

---

#### 5. **Lose Control** - Teddy Swims
**Spotify Track ID:** `17phhZDn6oGtzMe56NuWvj`  
**Album:** I've Tried Everything But Therapy (Part 1)  
**Key in Camelot:** 11B

| Metric | Our BASELINE | Spotify Reference | Error | Notes |
|--------|--------------|-------------------|-------|-------|
| BPM | 90.75 | **89** | +1.9% | Excellent! |
| Key | A Major | **A Major (11B)** | ✓ | Perfect! |
| Energy | 0.67 | 0.56 | +19.6% | Overestimated |
| Danceability | 0.80 | 0.60 | +33.3% | Overestimated |
| Valence | 0.58 | 0.20 | **+190%** | Major error - emotional song |
| Acousticness | 0.33 | 0.24 | +37.5% | Acceptable |

---

#### 6. **The Scientist** - SKAAR (Cover Version)
**Spotify Track ID:** `4HYRVbQHz6xOtpoh9RB3pt`  
**Album:** The Scientist (2020) - Electronic/Pop Cover  
**Key in Camelot:** 6B  
**Note:** This is NOT the Coldplay original - it's an electronic cover

| Metric | Our BASELINE | Spotify Reference | Error | Notes |
|--------|--------------|-------------------|-------|-------|
| BPM | 84.90 | **74** | +14.7% | Tempo detection issue |
| Key | A# Major | **A#/Bb (6B)** | ✓ | Correct! |
| Energy | 0.38 | 0.42 | -9.5% | Good! |
| Danceability | 0.76 | 0.17 | **+347%** | Massive overestimation |
| Valence | 0.55 | 0.89 | -38.2% | Wrong emotional reading |
| Acousticness | 0.79 | 0.12 | **+558%** | Wrong - this is electronic |

---

### BATCH 2 - Tracks 7-12

#### 7. **Walking in Memphis** - Marc Cohn
| Metric | Our BASELINE | Spotify Reference | Error |
|--------|--------------|-------------------|-------|
| BPM | 62.99 | TBD | - |
| Key | C Major | TBD | - |
| Danceability | 0.75 | TBD | - |

#### 8. **We Are The Champions** - Queen (Remastered 2011)
| Metric | Our BASELINE | Spotify Reference | Error |
|--------|--------------|-------------------|-------|
| BPM | 99.24 | TBD | - |
| Key | C Minor | TBD | - |
| Danceability | 0.78 | TBD | - |

#### 9. **What's My Age Again?** - blink-182
| Metric | Our BASELINE | Spotify Reference | Error |
|--------|--------------|-------------------|-------|
| BPM | 90.75 | TBD | - |
| Key | F# Major | TBD | - |
| Danceability | 0.76 | TBD | - |

#### 10. **You Know You Like It** - DJ Snake & AlunaGeorge
| Metric | Our BASELINE | Spotify Reference | Error |
|--------|--------------|-------------------|-------|
| BPM | 78.85 | TBD | - |
| Key | F Minor | TBD | - |
| Danceability | 0.83 | TBD | - |

#### 11. **You'll Think Of Me** - Keith Urban
| Metric | Our BASELINE | Spotify Reference | Error |
|--------|--------------|-------------------|-------|
| BPM | 72.65 | TBD | - |
| Key | A Minor | TBD | - |
| Danceability | 0.91 | TBD | - |

#### 12. **You're the Voice** - John Farnham
| Metric | Our BASELINE | Spotify Reference | Error |
|--------|--------------|-------------------|-------|
| BPM | 94.71 | TBD | - |
| Key | F Major | TBD | - |
| Danceability | 0.78 | TBD | - |

---

## 🎯 CRITICAL ISSUES IDENTIFIED

### 🔴 **MAJOR PROBLEMS:**

1. **Valence (Happiness) Detection - COMPLETELY BROKEN**
   - Consistently reads sad/emotional songs as happy
   - "Lose Control" (sad breakup song): 0.58 vs 0.20 actual
   - "The Scientist" (melancholic): 0.55 vs 0.89 actual (backwards!)
   - "Espresso" (light pop): 0.55 vs 0.11 actual
   - **Algorithm appears to be inverted or using wrong features**

2. **Danceability - MASSIVELY OVERESTIMATED**
   - Every song rated 0.75-0.90 (too high)
   - "BLACKBIRD" (acoustic ballad): 0.81 vs 0.26 actual
   - "The Scientist" (slow emotional): 0.76 vs 0.17 actual
   - **Likely confusing beat strength with danceability**

3. **Tempo Detection - OCTAVE ERRORS**
   - Frequently doubles or halves BPM
   - "Espresso": 69 vs 104 (halved)
   - "Every Little Thing": 91 vs 75 (doubled?)
   - **Need harmonic BPM selection algorithm**

4. **Key Detection - 50% FAILURE RATE**
   - Only 2/6 correct
   - Confuses relative major/minor
   - Large semitone errors
   - **Key profile matching needs work**

5. **Acousticness - INCONSISTENT**
   - "The Scientist" (electronic): 0.79 vs 0.12 (inverted!)
   - "Islands in the Stream" (acoustic): 0.47 vs 0.74 (missed)
   - **Feature extraction not capturing acoustic signature**

### ✅ **WHAT WORKS WELL:**

1. **Energy** - Generally accurate (±10%)
2. **Some BPM detections** - When not octave-confused
3. **Processing speed** - 12-18s per track is acceptable

---

## ROOT CAUSE ANALYSIS

### Algorithm Issues:

1. **Valence Algorithm:**
   - Likely using spectral features that correlate with production quality, not emotion
   - May be measuring "brightness" instead of "happiness"
   - Major/minor key not being weighted properly
   - **FIX: Use harmonic/melodic features, mode detection, pitch contour**

2. **Danceability Algorithm:**
   - Overweighting beat strength and rhythm regularity
   - Not considering tempo appropriateness for dancing
   - **FIX: Add tempo-based penalty, groove detection, syncopation analysis**

3. **Tempo Algorithm:**
   - Octave selection logic failing
   - Not using musical context (genre, energy) to choose correct octave
   - **FIX: Implement multi-octave analysis with intelligent selection**

4. **Key Detection:**
   - Key profile templates may be poorly calibrated
   - Major/minor confusion suggests mode detection issue
   - **FIX: Use better key profiles, add harmonic context, chroma normalization**

5. **Acousticness:**
   - Not properly distinguishing organic vs electronic production
   - May be confused by reverb/production effects
   - **FIX: Better MFCC analysis, spectral flux, attack time analysis**

---

## RECOMMENDED FIXES (Priority Order)

### 🔥 **URGENT - Critical Accuracy Issues:**

1. **Fix Valence Detection**
   - Implement mode (major/minor) detection
   - Use harmonic complexity features
   - Add melodic contour analysis
   - Weight minor keys towards lower valence
   - Use pitch range and dynamics

2. **Fix Danceability**
   - Add tempo-based modulation (penalize very slow/fast)
   - Implement groove detection (not just beat strength)
   - Use onset regularity vs strength
   - Add genre-aware thresholds

3. **Fix Tempo Octave Selection**
   - Implement harmonic BPM analysis
   - Use energy/spectral content to choose correct octave
   - Add musical range validation (40-200 BPM typical)
   - Prefer middle octaves when ambiguous

### ⚠️ **HIGH PRIORITY:**

4. **Improve Key Detection**
   - Update key profile templates
   - Better chroma normalization
   - Add harmonic progression analysis
   - Implement major/minor disambiguation

5. **Fix Acousticness**
   - Better organic vs synthetic timbre detection
   - Use attack time analysis (acoustic instruments have different attack)
   - Spectral flux patterns
   - MFCC variance analysis

---

## NEXT STEPS

1. Review `backend/analysis/pipeline_core.py` valence calculation
2. Review `backend/analysis/pipeline_core.py` danceability calculation
3. Review tempo/BPM selection logic
4. Update key profile matching algorithm
5. Implement improved acousticness detection
6. Re-run tests and compare
