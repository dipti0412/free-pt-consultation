from __future__ import annotations

from datetime import datetime, timezone

from data_ingestion.models import SourceRecord


def normalize_garmin_sample(raw: dict) -> SourceRecord:
    """Normalize a Garmin payload into a shared source record shape."""
    return SourceRecord(
        source="garmin",
        captured_at=datetime.now(timezone.utc),
        payload={
            "steps": raw.get("steps"),
            "resting_heart_rate": raw.get("restingHeartRate"),
            "sleep_minutes": raw.get("sleepMinutes"),
        },
    )
