from typing import Protocol

from app.funasr.models import StreamingResult


class StreamingAdapter(Protocol):
    def begin(self, session_id: str) -> None: ...
    def push_audio(
        self, session_id: str, chunk: bytes, is_final: bool
    ) -> list[StreamingResult]: ...
    def end(self, session_id: str) -> None: ...
    def ready(self) -> bool: ...


class FakeStreamingAdapter:
    def begin(self, session_id: str) -> None:
        return None

    def push_audio(
        self, session_id: str, chunk: bytes, is_final: bool
    ) -> list[StreamingResult]:
        if is_final:
            return [StreamingResult(text="final text", is_final=True)]
        return [StreamingResult(text="partial text", is_final=False)]

    def end(self, session_id: str) -> None:
        return None

    def ready(self) -> bool:
        return True
