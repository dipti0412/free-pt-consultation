from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field


class SourceRecord(BaseModel):
    source: str = Field(description="Source system identifier")
    captured_at: datetime
    payload: dict[str, Any]
