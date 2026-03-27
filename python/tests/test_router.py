from data_ingestion.health_stats import calculate_health_stats
from data_ingestion.router import normalize_from_source


def test_normalize_garmin_source() -> None:
    record = normalize_from_source(
        "garmin", {"steps": 1000, "restingHeartRate": 60, "sleepMinutes": 400}
    )

    assert record.source == "garmin"
    assert record.payload["steps"] == 1000


def test_normalize_apple_health_source_and_calculate_stats() -> None:
    record = normalize_from_source(
        "apple_health",
        {
            "stepCount": 8400,
            "restingHeartRate": 56,
            "sleepMinutes": 420,
            "workoutMinutes": 40,
            "standMinutes": 760,
            "activeEnergyKcal": 550,
        },
    )

    assert record.source == "apple_health"
    assert record.payload["steps"] == 8400
    assert record.payload["workout_minutes"] == 40

    stats = calculate_health_stats(record)
    assert stats["activity_score"] > 0
    assert stats["recovery_score"] > 0
    assert stats["daily_burn_kcal"] == 550
