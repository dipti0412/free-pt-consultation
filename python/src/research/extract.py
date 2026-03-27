from __future__ import annotations

from pathlib import Path

from pypdf import PdfReader


def extract_text(pdf_path: str | Path) -> str:
    """Extract all text from a research paper PDF."""
    path = Path(pdf_path)
    reader = PdfReader(path)
    return "\n".join((page.extract_text() or "") for page in reader.pages)
