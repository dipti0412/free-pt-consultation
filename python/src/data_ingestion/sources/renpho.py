from __future__ import annotations

from datetime import datetime, UTC

from data_ingestion.models import SourceRecord


def normalize_renpho_sample(raw: dict) -> SourceRecord:
    """Normalize a Renpho smart-scale payload into a shared source record shape."""
    return SourceRecord(
        source="renpho",
        captured_at=datetime.now(UTC),
        payload={
            "weight_kg": raw.get("weightKg"),
            "body_fat_percent": raw.get("bodyFatPercent"),
            "muscle_mass_kg": raw.get("muscleMassKg"),
        },
    )
