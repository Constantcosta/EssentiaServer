PYTHON ?= python3
DATASET ?=
TAG ?= adhoc
VALIDATION_THRESHOLDS ?= --max-mae bpm=4.0 \
	--max-mae danceability=0.12 \
	--max-mae energy=0.15 \
	--max-mae acousticness=0.10 \
	--max-mae valence=0.15 \
	--max-mae loudness=2.5

.PHONY: validate-calibration
validate-calibration:
	@if [ -z "$(DATASET)" ]; then \
		echo "Usage: make validate-calibration DATASET=path/to.parquet [TAG=label]"; \
		exit 1; \
	fi
	$(PYTHON) tools/validate_calibration.py --dataset $(DATASET) --tag $(TAG) $(VALIDATION_THRESHOLDS) --preview
