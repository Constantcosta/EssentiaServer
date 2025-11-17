## Key Detection Handover (Agent 1)

### Current State
- Analyzer now blends Essentia (standard + EDM) with a chroma fallback that performs sliding-window voting and re-correlates against Krumhansl templates.
- `_select_best_key_candidate` implements tonic/dominant correction, relative major/minor detection, and stronger mode inference (librosa chroma thirds + vote weights + Essentia mode confidence).
- `detect_global_key` resamples audio above `KEY_ANALYSIS_SAMPLE_RATE` (22.05 kHz default) before running librosa/Essentia, adopts Essentia’s root/mode when it disagrees by ±5/±7/±3 semitones, and raises the final confidence only when votes and Essentia align.
- Window consensus now keeps per-root support ratios plus major/minor vote histograms; runner overrides trigger whenever the dominant sliding-window key outweighs the fallback despite close chroma scores, and mode flips rely on aggregated window votes instead of a single third-based bias.
- Essentia’s standard and EDM extractors both feed into the vote stack; high-scoring EDM predictions can now override tonic picks when percussive chroma + window weights back them, and every Essentia candidate is recorded inside `key_details.scores` for calibration.
- Chroma peaks are no longer ignored: if the summed chroma bins and window weights both point to a different tonic (±5/±7/±9 semitones), the detector snaps to that root and re-derives mode confidence before calibration touches it.
- Calibration sweep as of `calibration_run_20251113_160849.csv` hits 23/43 exact matches (~53.5%), up from ~16/42 (~38%) previously; remaining misses are mostly +5 or +7 semitone dominant offsets and mode flips.

### Outstanding Issues
- Dominant/relative errors persist for songs such as “Billie Jean”, “Big Girls Don’t Cry”, “Every Little Thing She Does Is Magic”.
- 12 mode mismatches remain (e.g., BLACKBIRD reported as major). Current third-based heuristic needs better temporal context.
- Builder still fails because Teddy Swims – “You’re Still The One” is missing from the analyzer export; no fresh calibration dataset yet.

### Next Steps
1. Expand the calibration run with the full 55-song deck (include Teddy Swims) to generate a dataset for quantitative tracking.
2. Capture Essentia’s ranked list per track (already in `vote_meta['raw_scores']`) and log the root gaps when overrides fire; confirm whether remaining +7 cases lack sufficient Essentia confidence or votes.
3. Consider mode refinement that averages thirds across the sliding windows (not just the global profile) and uses chunk consensus, so tracks with mixed tonality stop flipping.
4. Once accuracy improves, rerun `tools/compare_calibration_subset.py` or the validation script to document before/after MAE for key predictions.
