from data_ingestion.router import normalize_from_source


def test_normalize_garmin_source() -> None:
    record = normalize_from_source(
        "garmin", {"steps": 1000, "restingHeartRate": 60, "sleepMinutes": 400}
    )

    assert record.source == "garmin"
    assert record.payload["steps"] == 1000
