from pathlib import Path
from typing import Protocol

from app.funasr.models import StreamingResult


class StreamingAdapter(Protocol):
    def load(self) -> None: ...
    def begin(self, session_id: str) -> None: ...
    def push_audio(
        self, session_id: str, chunk: bytes, is_final: bool
    ) -> list[StreamingResult]: ...
    def end(self, session_id: str) -> None: ...
    def ready(self) -> bool: ...


class FakeStreamingAdapter:
    def load(self) -> None:
        return None

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


class FunASRStreamingAdapter:
    def __init__(self, model_path: str) -> None:
        self.model_path = model_path
        self._model = None
        self._caches: dict[str, object] = {}

    def load(self) -> None:
        if not self.model_path:
            raise ValueError("FUNASR_MODEL_PATH is required")

        model_path = Path(self.model_path)
        if not model_path.exists():
            raise FileNotFoundError(f"FunASR model path does not exist: {self.model_path}")

        from funasr import AutoModel

        self._model = AutoModel(model=str(model_path))

    def begin(self, session_id: str) -> None:
        self._caches[session_id] = {}

    def push_audio(
        self, session_id: str, chunk: bytes, is_final: bool
    ) -> list[StreamingResult]:
        if self._model is None:
            raise RuntimeError("FunASR adapter is not loaded")

        if not chunk and not is_final:
            return []

        import numpy as np

        audio = np.frombuffer(chunk, dtype=np.int16)
        raw_result = self._model.generate(
            input=audio,
            cache=self._caches.setdefault(session_id, {}),
            is_final=is_final,
        )
        return self._coerce_results(raw_result)

    def end(self, session_id: str) -> None:
        self._caches.pop(session_id, None)

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
            text = str(item.get("text", "")).strip()
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
