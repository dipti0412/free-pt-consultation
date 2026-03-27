from __future__ import annotations

from data_ingestion.health_stats import calculate_health_stats
from data_ingestion.router import normalize_from_source
from research.extract import extract_text
from research.summarize import summarize_research_text


def demo() -> None:
    apple_health_record = normalize_from_source(
        "apple_health",
        {
            "stepCount": 9300,
            "restingHeartRate": 58,
            "sleepMinutes": 432,
            "workoutMinutes": 51,
            "standMinutes": 780,
            "activeEnergyKcal": 640,
        },
    )
    print("Sample normalized Apple Health record:")
    print(apple_health_record.model_dump_json(indent=2))
    print("\nCalculated health stats:")
    print(calculate_health_stats(apple_health_record))

    print("\nResearch extraction pipeline example:")
    print("text = extract_text('paper.pdf')")
    print("summary = summarize_research_text(text)")


if __name__ == "__main__":
    demo()
