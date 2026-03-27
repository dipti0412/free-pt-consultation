from __future__ import annotations

from collections.abc import Callable

from data_ingestion.models import SourceRecord
from data_ingestion.sources.apple_health import normalize_apple_health_sample
from data_ingestion.sources.garmin import normalize_garmin_sample
from data_ingestion.sources.intake_forms import normalize_intake_form
from data_ingestion.sources.renpho import normalize_renpho_sample

Normalizer = Callable[[dict], SourceRecord]

_SOURCE_NORMALIZERS: dict[str, Normalizer] = {
    "apple_health": normalize_apple_health_sample,
    "garmin": normalize_garmin_sample,
    "renpho": normalize_renpho_sample,
    "intake_form": normalize_intake_form,
}


def normalize_from_source(source: str, raw: dict) -> SourceRecord:
    if source not in _SOURCE_NORMALIZERS:
        available = ", ".join(sorted(_SOURCE_NORMALIZERS))
        raise ValueError(f"Unsupported source '{source}'. Available: {available}")
    return _SOURCE_NORMALIZERS[source](raw)
