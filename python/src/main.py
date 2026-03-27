from __future__ import annotations

from data_ingestion.router import normalize_from_source
from research.extract import extract_text
from research.summarize import summarize_research_text


def demo() -> None:
    garmin_record = normalize_from_source(
        "garmin",
        {"steps": 9300, "restingHeartRate": 58, "sleepMinutes": 432},
    )
    print("Sample normalized Garmin record:")
    print(garmin_record.model_dump_json(indent=2))

    print("\nResearch extraction pipeline example:")
    print("text = extract_text('paper.pdf')")
    print("summary = summarize_research_text(text)")


if __name__ == "__main__":
    demo()
