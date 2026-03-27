from __future__ import annotations

from data_ingestion.models import SourceRecord


def calculate_health_stats(record: SourceRecord) -> dict[str, float]:
    """Calculate simple health stats from a normalized health record."""
    steps = float(record.payload.get("steps") or 0)
    sleep_minutes = float(record.payload.get("sleep_minutes") or 0)
    workout_minutes = float(record.payload.get("workout_minutes") or 0)
    active_energy_kcal = float(record.payload.get("active_energy_kcal") or 0)
    resting_heart_rate = float(record.payload.get("resting_heart_rate") or 0)

    return {
        "activity_score": round(min(100.0, (steps / 10000.0) * 70 + (workout_minutes / 30.0) * 30), 2),
        "recovery_score": round(min(100.0, (sleep_minutes / 480.0) * 70 + max(0.0, (70.0 - resting_heart_rate)) * 0.43), 2),
        "daily_burn_kcal": round(active_energy_kcal, 2),
    }
