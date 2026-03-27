from __future__ import annotations


def summarize_research_text(text: str, max_chars: int = 1000) -> str:
    """Tiny placeholder summarizer for downstream LLM workflows."""
    compact = " ".join(text.split())
    return compact[:max_chars]
