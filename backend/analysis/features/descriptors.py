"""Additional high-level descriptor extraction."""

from __future__ import annotations

import logging
from typing import Dict, Optional

import librosa
import numpy as np

from backend.analysis import settings
from backend.analysis.essentia_support import (
    HAS_ESSENTIA,
    disable_tonal_extractor_runtime,
    run_tonal_extractor,
    tonal_extractor_allowed,
)
from backend.analysis.features.common import safe_frame_length

logger = logging.getLogger(__name__)

ANALYSIS_FFT_SIZE = settings.ANALYSIS_FFT_SIZE
ENABLE_ESSENTIA_DESCRIPTORS = settings.ENABLE_ESSENTIA_DESCRIPTORS


def extract_additional_descriptors(
    y_signal,
    sr,
    hop_length,
    onset_env,
    percussive_power,
    harmonic_power,
    y_harmonic,
    y_percussive,
    stft_magnitude: Optional[np.ndarray] = None,
):
    """Compute additional high-level descriptors using Essentia when available."""
    features: Dict[str, Optional[float]] = {
        "dynamic_complexity": None,
        "tonal_strength": None,
        "spectral_complexity": None,
        "zero_crossing_rate": None,
        "spectral_flux": None,
        "percussive_energy_ratio": None,
        "harmonic_energy_ratio": None,
    }

    stft_mag = stft_magnitude
    if y_signal.size > 0:
        safe_frame_len = safe_frame_length(len(y_signal), ANALYSIS_FFT_SIZE)
        zcr = librosa.feature.zero_crossing_rate(
            y=y_signal,
            frame_length=safe_frame_len,
            hop_length=hop_length,
        )
        features["zero_crossing_rate"] = float(np.mean(zcr))
    else:
        features["zero_crossing_rate"] = 0.0
    if stft_mag is None and y_signal.size > 0:
        safe_n_fft = safe_frame_length(len(y_signal), ANALYSIS_FFT_SIZE)
        stft_mag = np.abs(
            librosa.stft(
                y_signal,
                n_fft=safe_n_fft,
                hop_length=hop_length,
                window="hann",
                center=True,
            )
        )

    if stft_mag is not None:
        if stft_mag.shape[1] > 1:
            spectral_diff = np.diff(stft_mag, axis=1)
            flux = np.sqrt((spectral_diff**2).sum(axis=0))
            features["spectral_flux"] = float(np.mean(flux))
        else:
            features["spectral_flux"] = 0.0
    else:
        features["spectral_flux"] = 0.0

    total_power = percussive_power + harmonic_power
    if total_power > 0:
        features["percussive_energy_ratio"] = float(percussive_power / total_power)
        features["harmonic_energy_ratio"] = float(harmonic_power / total_power)
    else:
        features["percussive_energy_ratio"] = 0.0
        features["harmonic_energy_ratio"] = 0.0

    audio32 = np.ascontiguousarray(y_signal.astype(np.float32)) if y_signal.size > 0 else None

    if HAS_ESSENTIA and audio32 is not None and ENABLE_ESSENTIA_DESCRIPTORS:
        try:
            from backend.analysis.essentia_support import es

            dyn = es.DynamicComplexity(frameSize=2048, sampleRate=sr)  # type: ignore[attr-defined]
            dc_value, _ = dyn(audio32)
            features["dynamic_complexity"] = float(dc_value)
        except Exception as exc:
            logger.warning("⚠️ Essentia DynamicComplexity failed: %s", exc)

        if tonal_extractor_allowed():
            try:
                tonal_key, tonal_scale, tonal_strength, tonal_confidence = run_tonal_extractor(audio32, sr)
                strength = tonal_strength if tonal_strength is not None else tonal_confidence
                features["tonal_strength"] = float(strength) if strength is not None else None
            except Exception as exc:
                disable_tonal_extractor_runtime(exc)

        try:
            from backend.analysis.essentia_support import es

            spectral_complexity_algo = es.SpectralComplexity()  # type: ignore[attr-defined]
            complexities = []
            if stft_mag is not None:
                for frame in stft_mag.T:
                    complexities.append(float(spectral_complexity_algo(np.asarray(frame, dtype=np.float32))))
            else:
                window = es.Windowing(type="hann")
                spectrum = es.Spectrum()
                for frame in es.FrameGenerator(audio32, frameSize=2048, hopSize=hop_length, startFromZero=True):
                    spec = spectrum(window(frame))
                    complexities.append(float(spectral_complexity_algo(spec)))
            if complexities:
                features["spectral_complexity"] = float(np.mean(complexities))
        except Exception as exc:
            logger.warning("⚠️ Essentia SpectralComplexity failed: %s", exc)

    if features["dynamic_complexity"] is None:
        safe_frame_len = safe_frame_length(len(y_signal), ANALYSIS_FFT_SIZE)
        rms = librosa.feature.rms(y=y_signal, frame_length=safe_frame_len, hop_length=hop_length)
        features["dynamic_complexity"] = float(np.std(rms)) if rms.size else 0.0
    if features["tonal_strength"] is None:
        if y_signal.size > 0:
            tonnetz = librosa.feature.tonnetz(y=y_signal, sr=sr)
            features["tonal_strength"] = float(np.mean(np.abs(tonnetz)))
        else:
            features["tonal_strength"] = 0.0
    if features["spectral_complexity"] is None:
        if y_signal.size > 0:
            spectral_bandwidth = librosa.feature.spectral_bandwidth(y=y_signal, sr=sr)
            features["spectral_complexity"] = float(np.mean(spectral_bandwidth))
        else:
            features["spectral_complexity"] = 0.0

    return features


__all__ = ["extract_additional_descriptors"]
