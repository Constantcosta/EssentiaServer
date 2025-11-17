## Analyzer Configuration Reference

This guide maps every environment variable consumed by `backend/analysis/settings.py` to the behavior it controls so operators can tune sweeps without trawling code. Unless noted otherwise, values are read at process start (app relaunch required after edits).

### Core DSP Knobs

| Env Var | Default | Effect / Guidance |
| --- | --- | --- |
| `ANALYSIS_SAMPLE_RATE` | `12000` | Global resample target (Hz). Lower values reduce CPU but shave HF content; keep ≥12 kHz for modern pop. |
| `ANALYSIS_FFT_SIZE` | `1024` | Frame size for STFT/RMS measurements. Use 2048 when you need tighter low-end tempo tracking, but expect 2× FFT cost. |
| `ANALYSIS_HOP_LENGTH` | `512` | Hop length shared across onset/env calculations so timings line up. Smaller hops increase latency + memory. |
| `ANALYSIS_RESAMPLE_TYPE` | `kaiser_fast` | librosa resampler kernel (`kaiser_fast`, `kaiser_best`, etc.). Only change when debugging aliasing artifacts. |
| `MAX_ANALYSIS_SECONDS` | unset | Hard cap on analysis duration (seconds) once resampled. Leave unset for full‑track sweeps; set to `90` for smoke tests. |
| `TEMPO_WINDOW_SECONDS` | `60` | Loudest-window duration for tempo embedding. Raise to `90` for ballads with long intros. |
| `KEY_ANALYSIS_SAMPLE_RATE` | `22050` | Downsample target specifically for key detection. Dropping below 22 kHz trades HF clarity for speed. |

### Chunk Analysis & Consensus

| Env Var | Default | Effect / Guidance |
| --- | --- | --- |
| `CHUNK_ANALYSIS_ENABLED` | derived | Master switch. Auto‑enabled when `CHUNK_ANALYSIS_SECONDS > 0` **and** `MAX_CHUNK_BATCHES > 0`. |
| `CHUNK_ANALYSIS_SECONDS` | `15` | Target window length per chunk before tempo adjustments. |
| `CHUNK_OVERLAP_SECONDS` | `5` | Overlap between adjacent chunks. Increase for smoother modulation tracking (at a CPU cost). |
| `MIN_CHUNK_DURATION_SECONDS` | `5` | Guardrail so ultra-fast BPMs still get a meaningful slice. |
| `CHUNK_BEAT_TARGET` | `8` | Beat-count the chunker tries to hit; the code back-calculates window seconds from the BPM hint. |
| `MAX_CHUNK_BATCHES` | `16` | Upper bound on analyzed windows per track. Lower it to protect CI smoke runs. |
| `CHUNK_ANALYSIS_SECONDS` + `CHUNK_BEAT_TARGET` | — | Combined to derive adaptive windows; keep them paired so choruses stay weighted correctly. |

Operational controls:
- API clients can skip the extra work with header `X-Skip-Chunk-Analysis: 1` (backend falls back to single-pass analysis and still records `chunk_analysis={"skipped": True}`).
- Calibration/QA clients can bypass the SQLite cache with header `X-Force-Reanalyze: 1` (or JSON `force_reanalyze=true`) to ensure fresh DSP runs while still writing the new result back to cache.
- Use `X-Cache-Namespace: <tag>` to isolate cache reads/writes per workflow. All `/cache*` endpoints honor `?namespace=<tag>` (pass `namespace=calibration` to inspect or clear the calibration sandbox without touching production data).
- The consensus step now surfaces `key_dispersion_semitones`, `key_modulating`, `bpm_weighted_std`, and per-feature weighted variances in the API/exports so calibration dashboards can filter unstable songs.

### Feature Toggles

| Env Var | Default | Notes |
| --- | --- | --- |
| `ENABLE_TONAL_EXTRACTOR` | `false` | Enables Essentia tonal extractor blocks when installed. Useful for classical/jazz sweeps; adds ~150 ms per track. |
| `ENABLE_ESSENTIA_DANCEABILITY` | `false` | Switches danceability inference to Essentia’s high-level model. Keep off unless we ship matching calibration weights. |
| `ENABLE_ESSENTIA_DESCRIPTORS` | `false` | Turns on Essentia descriptor bundle (dynamic complexity, tonal strength, etc.) inside `extract_additional_descriptors`. |

### Worker / Process Pool

| Env Var | Default | Effect / Guidance |
| --- | --- | --- |
| `ANALYSIS_WORKERS` | `2` | Number of forked analyzer workers. Set to `0` to run inline (easiest for debugging stack traces). |

When tweaking these knobs for calibration sweeps:
1. Edit/export the variables inside the Mac app’s `.env` or your shell profile.
2. Restart the macOS control panel (or the Flask/uvicorn host) so settings propagate.
3. Document the tuple you used (`analysis-config.md` + calibration run notes) so future agents can reproduce results. 
