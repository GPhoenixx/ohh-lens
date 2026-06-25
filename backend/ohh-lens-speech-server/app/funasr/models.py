from dataclasses import dataclass


@dataclass
class StreamingResult:
    text: str
    is_final: bool
    start_ms: int = 0
    end_ms: int = 0
