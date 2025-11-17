# Adding Spotify Comparison to MacStudioServerSimulator

## 📋 Overview
This adds Spotify reference comparison to the MacStudioServerSimulator's ABCD Test tab, showing side-by-side validation of your analysis vs Spotify's ground truth data.

## 📁 New Files to Add to Xcode

### Swift Source Files:
1. **SpotifyReferenceData.swift** - CSV parser and data manager
2. **AnalysisComparison.swift** - BPM and key comparison logic
3. **TestComparisonView.swift** - SwiftUI comparison UI

### CSV Resource Files:
4. **test_12_preview.csv** - Spotify data for 12 preview tracks
5. **test_12_fullsong.csv** - Spotify data for 12 full-length tracks

### Modified Files:
- **ABCDTestRunner.swift** - Now captures individual song BPM/Key
- **ABCDResultsDashboard.swift** - Added comparison section

---

## 🛠️ Installation Steps

### Step 1: Open Xcode Project
```bash
open MacStudioServerSimulator.xcworkspace
```
(or `MacStudioServerSimulator.xcodeproj` if no workspace)

### Step 2: Add Swift Files

1. In Project Navigator, right-click on `MacStudioServerSimulator` folder
2. Choose **"Add Files to 'MacStudioServerSimulator'..."**
3. Navigate to:
   ```
   /Users/costasconstantinou/Documents/GitHub/EssentiaServer/MacStudioServerSimulator/MacStudioServerSimulator/
   ```
4. Select these 3 files (hold ⌘ to multi-select):
   - `SpotifyReferenceData.swift`
   - `AnalysisComparison.swift`
   - `TestComparisonView.swift`

5. **Important settings:**
   - ⬜ **Uncheck** "Copy items if needed" (files already in place)
   - ◉ Select "Create groups"
   - ✅ **Check** "MacStudioServerSimulator" target
   
6. Click **"Add"**

### Step 3: Add CSV Resource Files

1. Right-click on `MacStudioServerSimulator` folder again
2. Choose **"Add Files to 'MacStudioServerSimulator'..."**
3. Select both CSV files:
   - `test_12_preview.csv`
   - `test_12_fullsong.csv`

4. **Important settings:**
   - ⬜ **Uncheck** "Copy items if needed"
   - ◉ Select "Create groups"
   - ✅ **Check** "MacStudioServerSimulator" target
   
5. Click **"Add"**

### Step 4: Verify Bundle Resources

1. Select the **MacStudioServerSimulator** target (blue app icon)
2. Go to **"Build Phases"** tab
3. Expand **"Copy Bundle Resources"**
4. Verify both CSV files are listed:
   - `test_12_preview.csv` ✅
   - `test_12_fullsong.csv` ✅
5. If missing, click **+** and add them

### Step 5: Build and Test

1. **Clean build folder**: Product → Clean Build Folder (⇧⌘K)
2. **Build**: Product → Build (⌘B)
3. **Run**: Product → Run (⌘R)

---

## ✅ What Was Changed

### 1. Data Layer
**SpotifyReferenceData.swift**
- Loads both CSV files on app launch
- Creates lookup table by song + artist (normalized)
- Provides 24 reference tracks total (12 preview + 12 fullsong)

### 2. Comparison Logic
**AnalysisComparison.swift**
- **BPM matching**: ±3 tolerance + octave detection (half/double)
- **Key matching**: Enharmonic equivalents (C♯ = D♭) + mode awareness
- Color-coded results: 🟢 Green = match, 🔴 Red = mismatch

### 3. UI Component
**TestComparisonView.swift**
- Compact table layout optimized for the right panel
- Shows: Song | BPM (Ours · Spotify) | Key (Ours · Spotify) | Status
- Match statistics at top
- Scrollable up to 300px height

### 4. Test Runner Updates
**ABCDTestRunner.swift**
- Added `analysisResults: [AnalysisResult]` field
- Parses individual song BPM/Key from test output
- New `parseSongResult()` method extracts data from each line

### 5. Dashboard Integration
**ABCDResultsDashboard.swift**
- Added `TestComparisonView` below Individual Test Results
- Appears automatically when tests have results

---

## 📊 How It Works

### Data Flow:
```
1. User runs Test A/B/C/D
2. run_test.sh outputs analysis results
3. ABCDTestRunner parses each song's BPM and Key
4. TestComparisonView finds Spotify reference
5. ComparisonEngine matches with tolerance
6. UI displays color-coded comparison
```

### Output Parsing:
The runner looks for lines like:
```
  1. Espresso                    | BPM:    104 | Key:    C | Energy:  0.76
  2. The Scientist               | BPM:     74 | Key:   Bb | Energy:  0.17
```

### Matching Logic:
```swift
BPM matches if:
- Within ±3 BPM (e.g., 102-106 matches 104)
- OR half/double (e.g., 52 or 208 matches 104)

Key matches if:
- Exact match (C = C)
- OR enharmonic (C♯ = D♭, F♯ = G♭, etc.)
- AND same mode (major/minor must match)
```

---

## 🎯 Where to See It

After building and running:

1. Click **"Tests"** tab (checklist icon)
2. Run any test (A, B, C, or D)
3. Watch the right panel:
   - Overall Summary
   - Performance Comparison
   - Individual Test Results
   - **→ Spotify Reference Comparison** ⭐ (NEW!)

The comparison section will show:
- Header with match statistics (e.g., "22/24 matches (92%)")
- Table with each song's results
- Green rows = perfect matches
- Red rows = discrepancies

---

## 🐛 Troubleshooting

### "Cannot find 'SpotifyReferenceData' in scope"
- Verify all 3 Swift files are added to the target
- Check Target Membership in File Inspector
- Clean and rebuild (⇧⌘K)

### "Cannot find test_12_preview.csv"
- Check Build Phases → Copy Bundle Resources
- Both CSV files must be listed
- If missing, add them with the + button

### No comparison data showing
- Run at least one test first
- Check console for Spotify data loading:
  ```
  📊 Loaded 24 Spotify reference tracks
  ```
- Verify test output includes BPM and Key data

### All comparisons show "unavailable"
- Song/artist names might not match between test and CSV
- Check test output format matches expected pattern
- Names are normalized (lowercase, special chars removed)

---

## 🎉 Success!

When everything works, you'll see:
- ✅ Comparison table with 6-12 songs per test
- 🟢 Green matches for accurate results
- 🔴 Red highlights for discrepancies
- 📊 Accuracy percentage at the top

This helps you:
- Validate analysis accuracy
- Identify systematic errors
- Debug problem tracks
- Track improvements over time

Enjoy! 🎵📊
