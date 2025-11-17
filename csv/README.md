# Test Results CSV Export

## Overview
All test runs automatically export results to timestamped CSV files in this directory.

## CSV Columns
- **test_type**: Which test was run (Test A, B, C, D, or Batch 1/2)
- **song_title**: Name of the song analyzed
- **artist**: Artist name
- **file_type**: `preview` (30-second clips) or `full` (full-length songs)
- **success**: `True` if analysis completed, `False` if failed
- **duration_s**: Time taken to analyze this song (in seconds)
- **bpm**: Beats per minute detected
- **key**: Musical key detected (e.g., "C Major", "A Minor")
- **energy**: Energy level (0-1)
- **danceability**: Danceability score (0-1)
- **valence**: Musical positiveness (0-1)
- **acousticness**: Acoustic vs electric (0-1)
- **instrumentalness**: Vocal vs instrumental (0-1)
- **liveness**: Live performance detection (0-1)
- **speechiness**: Speech vs music (0-1)
- **error**: Error message if analysis failed

## Usage

### Automatic Export (via run_test.sh)
```bash
./run_test.sh a  # Creates csv/test_results_TIMESTAMP.csv
./run_test.sh b
./run_test.sh c
./run_test.sh d
```

### Manual Export
```bash
# Auto-generate filename
.venv/bin/python tools/test_analysis_pipeline.py --preview-batch --csv-auto

# Specify filename
.venv/bin/python tools/test_analysis_pipeline.py --full-batch --csv my_results.csv
```

## Example Analysis

Open in Excel, Numbers, Google Sheets, or use Python:

```python
import pandas as pd

# Load results
df = pd.read_csv('csv/test_results_20251117_005038.csv')

# Get average BPM by file type
print(df.groupby('file_type')['bpm'].mean())

# Find high-energy songs
high_energy = df[df['energy'] > 0.6]
print(high_energy[['song_title', 'energy', 'bpm']])
```
