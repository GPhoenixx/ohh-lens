import re
from dataclasses import dataclass, field
from typing import Protocol

from app.funasr.models import StreamingResult


class StreamingAdapter(Protocol):
    def load(self) -> None: ...
    def begin(self, session_id: str, language: str = "auto") -> None: ...
    def push_audio(
        self, session_id: str, chunk: bytes, is_final: bool
    ) -> list[StreamingResult]: ...
    def end(self, session_id: str) -> None: ...
    def ready(self) -> bool: ...


class FakeStreamingAdapter:
    def load(self) -> None:
        return None

    def begin(self, session_id: str, language: str = "auto") -> None:
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


class FunASRStreamingAdapter:
    def __init__(self, model_name: str, device: str) -> None:
        self.model_name = model_name
        self.device = device
        self._model = None
        self._sessions: dict[str, StreamingSessionState] = {}

    def load(self) -> None:
        if not self.model_name:
            raise ValueError("FUNASR_MODEL_NAME is required")
        if not self.device:
            raise ValueError("FUNASR_DEVICE is required")

        from funasr import AutoModel

        self._model = AutoModel(model=self.model_name, device=self.device)

    def begin(self, session_id: str, language: str = "auto") -> None:
        self._sessions[session_id] = StreamingSessionState(language=language)

    def push_audio(
        self, session_id: str, chunk: bytes, is_final: bool
    ) -> list[StreamingResult]:
        if self._model is None:
            raise RuntimeError("FunASR adapter is not loaded")

        if not chunk and not is_final:
            return []

        import numpy as np

        audio = np.frombuffer(chunk, dtype=np.int16).astype(np.float32) / 32768.0
        session = self._sessions.setdefault(session_id, StreamingSessionState())

        raw_result = self._model.generate(
            input=audio,
            cache=session.cache,
            is_final=is_final,
            language=session.language,
            use_itn=True,
        )
        return self._coerce_results(raw_result)

    def end(self, session_id: str) -> None:
        self._sessions.pop(session_id, None)

    def ready(self) -> bool:
        return self._model is not None

    def _coerce_results(self, raw_result: object) -> list[StreamingResult]:
        if raw_result is None:
            return []

        if isinstance(raw_result, dict):
            items = [raw_result]
        elif isinstance(raw_result, list):
            items = [item for item in raw_result if isinstance(item, dict)]
        else:
            return []

        results: list[StreamingResult] = []
        for item in items:
            text = self._clean_text(item.get("text", ""))
            if not text:
                continue
            results.append(
                StreamingResult(
                    text=text,
                    is_final=bool(item.get("is_final", False)),
                    start_ms=int(item.get("start_ms", 0) or 0),
                    end_ms=int(item.get("end_ms", 0) or 0),
                )
            )
        return results

    @staticmethod
    def _clean_text(value: object) -> str:
        text = re.sub(r"<\|[^|]*\|>", "", str(value))
        return text.strip()


@dataclass
class StreamingSessionState:
    language: str = "auto"
    cache: dict[str, object] = field(default_factory=dict)
