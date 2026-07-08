from importlib.util import find_spec
import logging
import re
import unicodedata
from dataclasses import dataclass, field
from typing import Protocol

from app.funasr.models import StreamingResult


logger = logging.getLogger(__name__)
PARTIAL_FILLER_WORDS = {
    "ah",
    "er",
    "erm",
    "hmm",
    "mm",
    "oh",
    "uh",
    "um",
    "yeah",
}


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
    def __init__(
        self,
        model_name: str,
        device: str,
        hub: str = "hf",
        vad_model_name: str = "fsmn-vad",
        vad_chunk_ms: int = 200,
        sample_rate: int = 16000,
        asr_chunk_size: list[int] | None = None,
        encoder_chunk_look_back: int = 4,
        decoder_chunk_look_back: int = 1,
        min_audio_rms: float = 0.0,
    ) -> None:
        self.model_name = model_name
        self.device = device
        self.hub = hub
        self.vad_model_name = vad_model_name
        self.vad_chunk_ms = vad_chunk_ms
        self.sample_rate = sample_rate
        self.asr_chunk_size = asr_chunk_size or [0, 10, 5]
        self.encoder_chunk_look_back = encoder_chunk_look_back
        self.decoder_chunk_look_back = decoder_chunk_look_back
        self.min_audio_rms = min_audio_rms
        self._model = None
        self._vad_model = None
        self._sessions: dict[str, StreamingSessionState] = {}

    def load(self) -> None:
        if not self.model_name:
            raise ValueError("FUNASR_MODEL_NAME is required")
        if not self.device:
            raise ValueError("FUNASR_DEVICE is required")
        if self.vad_chunk_ms <= 0:
            raise ValueError("FUNASR_VAD_CHUNK_MS must be positive")
        if self.min_audio_rms < 0:
            raise ValueError("FUNASR_MIN_AUDIO_RMS must be non-negative")
        self._validate_optional_runtime_dependencies()

        from funasr import AutoModel

        model_kwargs = {
            "model": self.model_name,
            "device": self.device,
        }
        if self.hub:
            model_kwargs["hub"] = self.hub
        if self._requires_trust_remote_code():
            model_kwargs["trust_remote_code"] = True
        logger.info(
            "Loading FunASR ASR model model=%s hub=%s device=%s",
            self.model_name,
            self.hub or "default",
            self.device,
        )

        self._model = AutoModel(**model_kwargs)
        if self.vad_model_name:
            vad_model_kwargs = {
                "model": self.vad_model_name,
                "device": self.device,
            }
            if self.hub:
                vad_model_kwargs["hub"] = self.hub
            logger.info(
                "Loading FunASR VAD model model=%s hub=%s device=%s",
                self.vad_model_name,
                self.hub or "default",
                self.device,
            )
            self._vad_model = AutoModel(**vad_model_kwargs)

    def _validate_optional_runtime_dependencies(self) -> None:
        if self._is_qwen_asr_model() and find_spec("qwen_asr") is None:
            raise ImportError(
                f"{self.model_name} requires the qwen-asr package. "
                "Install with: pip install qwen-asr"
            )

    def _is_qwen_asr_model(self) -> bool:
        normalized_model_name = self.model_name.lower()
        return "qwen" in normalized_model_name and "asr" in normalized_model_name

    def _requires_trust_remote_code(self) -> bool:
        normalized_model_name = self.model_name.lower()
        return "fun-asr" in normalized_model_name

    def _requires_torch_audio_input(self) -> bool:
        normalized_model_name = self.model_name.lower()
        return "fun-asr" in normalized_model_name

    def begin(self, session_id: str, language: str = "auto") -> None:
        self._sessions[session_id] = StreamingSessionState(language=language)

    def push_audio(
        self, session_id: str, chunk: bytes, is_final: bool
    ) -> list[StreamingResult]:
        if self._model is None:
            raise RuntimeError("FunASR adapter is not loaded")

        import numpy as np

        session = self._sessions.setdefault(session_id, StreamingSessionState())
        empty_audio = np.array([], dtype=np.float32)

        if not chunk:
            if not is_final or not session.asr_started:
                return []
            return self._generate_asr_results(
                session_id,
                empty_audio,
                session,
                is_final=True,
            )

        audio = np.frombuffer(chunk, dtype=np.int16).astype(np.float32) / 32768.0

        # TODO: Uncomment this when we want to filter minimum audio RMS
        # if self._audio_rms(audio) < self.min_audio_rms:
        #     if is_final and session.asr_started:
        #         return self._generate_asr_results(
        #             session_id,
        #             empty_audio,
        #             session,
        #             is_final=True,
        #         )
        #     print("Skipping audio because it's too quiet")
            
            
        #     return []

        if self._vad_model is not None and not self._chunk_contains_speech(
            audio,
            session,
            is_final,
        ):
            if is_final and session.asr_started:
                return self._generate_asr_results(
                    session_id,
                    empty_audio,
                    session,
                    is_final=True,
                )
            return []

        return self._generate_asr_results(session_id, audio, session, is_final=is_final)

    def _generate_asr_results(
        self,
        session_id: str,
        audio: "np.ndarray",
        session: "StreamingSessionState",
        is_final: bool,
    ) -> list[StreamingResult]:
        if self._requires_torch_audio_input():
            import torch

            model_input: object = torch.from_numpy(audio)
        else:
            model_input = audio

        raw_result = self._model.generate(
            input=model_input,
            cache=session.cache,
            is_final=is_final,
            language=session.language,
            use_itn=True,
            chunk_size=self.asr_chunk_size,
            encoder_chunk_look_back=self.encoder_chunk_look_back,
            decoder_chunk_look_back=self.decoder_chunk_look_back,
        )
        session.asr_started = True
        return self._coerce_results(raw_result)

    @staticmethod
    def _audio_rms(audio: "np.ndarray") -> float:
        if len(audio) == 0:
            return 0.0
        import numpy as np

        return float(np.sqrt(np.mean(audio * audio)))

    def _chunk_contains_speech(
        self,
        audio: "np.ndarray",
        session: "StreamingSessionState",
        is_final: bool,
    ) -> bool:
        speech_detected = session.speech_active
        frames = list(self._iter_vad_frames(audio))

        for index, frame in enumerate(frames):
            raw_result = self._vad_model.generate(
                input=frame,
                cache=session.vad_cache,
                is_final=is_final and index == len(frames) - 1,
                chunk_size=self.vad_chunk_ms,
            )
            if self._apply_vad_result(raw_result, session):
                speech_detected = True
            if session.speech_active:
                speech_detected = True

        return speech_detected

    def _iter_vad_frames(self, audio: "np.ndarray"):
        frame_samples = max(1, int(self.vad_chunk_ms * self.sample_rate / 1000))
        for start in range(0, len(audio), frame_samples):
            yield audio[start : start + frame_samples]

    @staticmethod
    def _apply_vad_result(
        raw_result: object,
        session: "StreamingSessionState",
    ) -> bool:
        if isinstance(raw_result, dict):
            items = [raw_result]
        elif isinstance(raw_result, list):
            items = [item for item in raw_result if isinstance(item, dict)]
        else:
            return False

        speech_detected = False
        for item in items:
            value = item.get("value", [])
            if not isinstance(value, list):
                continue
            for segment in value:
                if not isinstance(segment, (list, tuple)) or len(segment) < 2:
                    continue
                start_ms = int(segment[0])
                end_ms = int(segment[1])
                speech_detected = True
                if start_ms >= 0 and end_ms == -1:
                    session.speech_active = True
                elif start_ms == -1 and end_ms >= 0:
                    session.speech_active = False
                elif start_ms >= 0 and end_ms >= 0:
                    session.speech_active = False
        return speech_detected

    def end(self, session_id: str) -> None:
        self._sessions.pop(session_id, None)

    def ready(self) -> bool:
        if self._model is None:
            return False
        if self.vad_model_name and self._vad_model is None:
            return False
        return True

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
            is_final = bool(item.get("is_final", False))
            if not text or self._is_suppressed_partial(text, is_final):
                continue
            results.append(
                StreamingResult(
                    text=text,
                    is_final=is_final,
                    start_ms=int(item.get("start_ms", 0) or 0),
                    end_ms=int(item.get("end_ms", 0) or 0),
                )
            )
        return results

    @staticmethod
    def _is_suppressed_partial(text: str, is_final: bool) -> bool:
        if is_final:
            return False

        words = text.split()
        return bool(words) and all(word in PARTIAL_FILLER_WORDS for word in words)

    @staticmethod
    def _clean_text(value: object) -> str:
        text = re.sub(r"<\|[^|]*\|>", "", str(value))
        keep = {"'", "+", "-"}
        text = "".join(
            character
            for character in text
            if (
                character in keep
                or not unicodedata.category(character).startswith(("P", "S"))
            )
        )
        return " ".join(text.split()).lower()

@dataclass
class StreamingSessionState:
    language: str = "auto"
    cache: dict[str, object] = field(default_factory=dict)
    vad_cache: dict[str, object] = field(default_factory=dict)
    speech_active: bool = False
    asr_started: bool = False
