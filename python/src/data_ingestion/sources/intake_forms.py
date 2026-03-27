from __future__ import annotations

from datetime import datetime, UTC

from data_ingestion.models import SourceRecord


def normalize_intake_form(raw: dict) -> SourceRecord:
    """Normalize intake form responses to the shared source record shape."""
    return SourceRecord(
        source="intake_form",
        captured_at=datetime.now(UTC),
        payload={
            "goal": raw.get("goal"),
            "injuries": raw.get("injuries", []),
            "dietary_preferences": raw.get("dietaryPreferences", []),
        },
    )
