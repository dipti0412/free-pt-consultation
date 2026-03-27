from __future__ import annotations

from datetime import datetime, timezone

from data_ingestion.models import SourceRecord


def normalize_apple_health_sample(raw: dict) -> SourceRecord:
    """Normalize an Apple Health payload into a shared source record shape."""
    workout_minutes = raw.get("workoutMinutes")
    stand_minutes = raw.get("standMinutes")
    active_energy_kcal = raw.get("activeEnergyKcal")
    return SourceRecord(
        source="apple_health",
        captured_at=datetime.now(timezone.utc),
        payload={
            "steps": raw.get("stepCount"),
            "resting_heart_rate": raw.get("restingHeartRate"),
            "sleep_minutes": raw.get("sleepMinutes"),
            "workout_minutes": workout_minutes,
            "stand_minutes": stand_minutes,
            "active_energy_kcal": active_energy_kcal,
        },
    )
