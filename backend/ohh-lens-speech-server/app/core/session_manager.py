from dataclasses import dataclass
import logging

from app.core.live_translation import LiveTranslationAssembler, TranslatorProtocol
from app.core.protocol import StartMessage, event_payload
from app.audio.buffer import PCMChunkBuffer
from app.funasr.adapter import StreamingAdapter


logger = logging.getLogger(__name__)


@dataclass
class LiveSessionState:
    start: StartMessage
    buffer: PCMChunkBuffer
    active_segment_index: int = 1
    translation: LiveTranslationAssembler | None = None

    @property
    def active_segment_id(self) -> str:
        return f"{self.start.session_id}-{self.active_segment_index}"


class SessionManager:
    def __init__(
        self,
        adapter: StreamingAdapter,
        chunk_bytes: int = 19200,
        translator: TranslatorProtocol | None = None,
        translation_seconds_cap: float = 6.0,
        translation_min_sentence_words: int = 8,
        translation_context_pair_count: int = 2,
    ) -> None:
        self.adapter = adapter
        self.chunk_bytes = chunk_bytes
        self.translator = translator
        self.translation_seconds_cap = translation_seconds_cap
        self.translation_min_sentence_words = translation_min_sentence_words
        self.translation_context_pair_count = translation_context_pair_count
        self.sessions: dict[str, LiveSessionState] = {}

    def start_session(self, session_id: str, start_message: StartMessage) -> dict:
        if session_id in self.sessions:
            raise ValueError(f"session is already active: {session_id}")
        translation = None
        if (
            self.translator is not None
            and start_message.language == "en"
            and start_message.target_language == "vi"
        ):
            translation = LiveTranslationAssembler(
                translator=self.translator,
                seconds_cap=self.translation_seconds_cap,
                min_sentence_words=self.translation_min_sentence_words,
                context_pair_count=self.translation_context_pair_count,
            )
        self.sessions[session_id] = LiveSessionState(
            start=start_message,
            buffer=PCMChunkBuffer(chunk_bytes=self.chunk_bytes),
            translation=translation,
        )
        self.adapter.begin(session_id, language=start_message.language)
        return event_payload("ready", session_id)

    def push_audio(self, session_id: str, audio: bytes) -> list[dict]:
        state = self.sessions[session_id]
        state.buffer.append(audio)
        events: list[dict] = []
        for chunk in state.buffer.pop_ready_chunks():
            for result in self.adapter.push_audio(session_id, chunk, is_final=False):
                segment_id = state.active_segment_id
                event_type = "final" if result.is_final else "partial"
                print(f"event_type: {event_type}, result: {result.text}")
                events.append(
                    self._transcript_event(session_id, segment_id, event_type, result.text, result)
                )
                events.extend(
                    self._translation_events(state, segment_id, result.text, result.is_final)
                )
                if result.is_final:
                    state.active_segment_index += 1
        if(len(events) > 0): print(f"events: {events}")
        return events

    def stop_session(self, session_id: str) -> list[dict]:
        state = self.sessions[session_id]
        remainder = state.buffer.flush()
        events: list[dict] = []
        try:
            for result in self.adapter.push_audio(session_id, remainder, is_final=True):
                segment_id = state.active_segment_id
                event_type = "final" if result.is_final else "partial"
                events.append(
                    self._transcript_event(session_id, segment_id, event_type, result.text, result)
                )
                events.extend(
                    self._translation_events(state, segment_id, result.text, result.is_final)
                )
                if result.is_final:
                    state.active_segment_index += 1
            if state.translation is not None:
                events.extend(self._translation_payloads(state, state.translation.flush()))
        finally:
            self.cleanup_session(session_id)
        events.append(event_payload("closed", session_id))
        return events

    def _transcript_event(
        self, session_id: str, segment_id: str, event_type: str, text: str, result: object
    ) -> dict:
        return event_payload(
            event_type,
            session_id,
            segment_id=segment_id,
            text=text,
            start_ms=getattr(result, "start_ms", None),
            end_ms=getattr(result, "end_ms", None),
        )

    def _translation_events(
        self, state: LiveSessionState, segment_id: str, text: str, is_final: bool
    ) -> list[dict]:
        if state.translation is None:
            return []
        try:
            translation_events = (
                state.translation.push_final_text(segment_id, text)
                if is_final
                else state.translation.push_partial_text(segment_id, text)
            )
        except Exception:
            logger.exception(
                "Live translation failed session=%s segment=%s",
                state.start.session_id,
                segment_id,
            )
            return []
        return self._translation_payloads(state, translation_events)

    @staticmethod
    def _translation_payloads(
        state: LiveSessionState, translation_events: list[dict[str, object]]
    ) -> list[dict]:
        return [
            event_payload("translation", state.start.session_id, **event)
            for event in translation_events
        ]

    def cleanup_session(self, session_id: str) -> None:
        if session_id not in self.sessions:
            return

        try:
            self.adapter.end(session_id)
        finally:
            self.sessions.pop(session_id, None)
