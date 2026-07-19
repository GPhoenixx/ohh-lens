import asyncio

from fastapi.testclient import TestClient

from app.api.ws import build_ws_router
from app.core.protocol import StartMessage
from app.core.session_manager import SessionManager
from app.core.live_translation import LiveTranslationAssembler
from app.funasr.adapter import FakeStreamingAdapter
from app.main import create_app


class NeverReadyAdapter:
    def ready(self) -> bool:
        return False


class LanguageCapturingAdapter:
    def __init__(self) -> None:
        self.languages: list[str] = []

    def load(self) -> None:
        return None

    def ready(self) -> bool:
        return True

    def begin(self, session_id: str, language: str = "auto") -> None:
        self.languages.append(language)

    def push_audio(self, session_id: str, chunk: bytes, is_final: bool) -> list:
        return []

    def end(self, session_id: str) -> None:
        return None


class BrokenAudioAdapter:
    def load(self) -> None:
        return None

    def ready(self) -> bool:
        return True

    def begin(self, session_id: str, language: str = "auto") -> None:
        return None

    def push_audio(self, session_id: str, chunk: bytes, is_final: bool) -> list:
        raise ValueError("bad audio chunk")

    def end(self, session_id: str) -> None:
        return None


class CleanupCapturingAdapter:
    def __init__(self) -> None:
        self.ended_sessions: list[str] = []

    def load(self) -> None:
        return None

    def ready(self) -> bool:
        return True

    def begin(self, session_id: str, language: str = "auto") -> None:
        return None

    def push_audio(self, session_id: str, chunk: bytes, is_final: bool) -> list:
        return []

    def end(self, session_id: str) -> None:
        self.ended_sessions.append(session_id)


class StubTranslator:
    def punctuate(self, text: str) -> str:
        if text == "i want to review this page":
            return "I want to review this page."
        return text

    def translate(self, text: str) -> str:
        if text == "I want to review this page.":
            return "toi muon xem lai trang nay"
        return "translated text"


class SentenceEndingTranslator(StubTranslator):
    def punctuate(self, text: str) -> str:
        return f"{text.rstrip('.')} .".replace(" .", ".")


class ContextCapturingTranslator(SentenceEndingTranslator):
    def __init__(self) -> None:
        self.contexts: list[list[tuple[str, str]]] = []

    def translate_with_context(
        self, text: str, context: list[tuple[str, str]]
    ) -> str:
        self.contexts.append(context)
        return f"vi:{text}"


class EmptyTranslationTranslator(SentenceEndingTranslator):
    def translate(self, text: str) -> str:
        return ""


class FailingTranslator:
    def punctuate(self, text: str) -> str:
        raise RuntimeError("punctuation model unavailable")

    def translate(self, text: str) -> str:
        raise RuntimeError("translation model unavailable")


def test_session_manager_buffers_short_audio_before_emitting_subtitle_events():
    session_manager = SessionManager(adapter=FakeStreamingAdapter())
    start = StartMessage(
        type="start",
        session_id="session-buffering",
        sample_rate=16000,
        channels=1,
        sample_format="pcm_s16le",
        language="en",
    )

    session_manager.start_session("session-buffering", start)

    first_events = session_manager.push_audio("session-buffering", b"\x00\x01" * 4000)
    assert first_events == []

    second_events = session_manager.push_audio("session-buffering", b"\x00\x01" * 28000)
    assert len(second_events) == 3
    assert [event["type"] for event in second_events] == ["partial", "partial", "partial"]
    assert [event["text"] for event in second_events] == ["partial text", "partial text", "partial text"]


def test_session_manager_uses_600ms_streaming_chunks():
    session_manager = SessionManager(adapter=FakeStreamingAdapter())
    start = StartMessage(
        type="start",
        session_id="session-600ms",
        sample_rate=16000,
        channels=1,
        sample_format="pcm_s16le",
        language="en",
    )

    session_manager.start_session("session-600ms", start)

    first_events = session_manager.push_audio("session-600ms", b"\x00\x01" * 9599)
    assert first_events == []

    second_events = session_manager.push_audio("session-600ms", b"\x00\x01")
    assert len(second_events) == 1
    assert second_events[0]["type"] == "partial"
    assert second_events[0]["text"] == "partial text"
    assert second_events[0]["segment_id"] == "session-600ms-1"


def test_session_manager_emits_segment_ids_for_partial_and_final_events():
    session_manager = SessionManager(adapter=FakeStreamingAdapter())
    start = StartMessage(
        type="start",
        session_id="segment-session",
        sample_rate=16000,
        channels=1,
        sample_format="pcm_s16le",
        language="en",
    )

    session_manager.start_session("segment-session", start)

    partial_events = session_manager.push_audio("segment-session", b"\x00\x01" * 32000)
    final_events = session_manager.stop_session("segment-session")

    assert partial_events[0]["segment_id"] == "segment-session-1"
    assert final_events[0]["segment_id"] == "segment-session-1"


def test_live_translation_assembler_accumulates_across_asr_segments_until_six_seconds():
    current_time = [0.0]
    assembler = LiveTranslationAssembler(
        translator=StubTranslator(),
        seconds_cap=6.0,
        clock=lambda: current_time[0],
    )

    assert assembler.push_partial_text("segment-session-1", "i want to review") == []

    current_time[0] = 2.0
    assert assembler.push_final_text("segment-session-1", "i want to review") == []
    assert assembler.push_partial_text("segment-session-2", "this page with you") == []

    current_time[0] = 6.0
    events = assembler.push_partial_text(
        "segment-session-2", "this page with you today"
    )

    assert events[0]["type"] == "translation"
    assert events[0]["translation_id"] == "segment-session-1-translation-1"
    assert events[0]["source_text"] == "i want to review this page with you today"


def test_session_manager_emits_translation_before_closed_for_english_session():
    session_manager = SessionManager(
        adapter=FakeStreamingAdapter(),
        translator=StubTranslator(),
    )
    start = StartMessage(
        type="start",
        session_id="translation-session",
        sample_rate=16000,
        channels=1,
        sample_format="pcm_s16le",
        language="en",
    )

    session_manager.start_session("translation-session", start)
    session_manager.push_audio("translation-session", b"\x00\x01" * 32000)
    events = session_manager.stop_session("translation-session")

    assert [event["type"] for event in events] == [
        "final",
        "translation",
        "closed",
    ]
    assert events[1]["segment_id"] == "translation-session-1"
    assert events[1]["session_id"] == "translation-session"


def test_live_translation_assembler_flushes_at_time_cap():
    current_time = [0.0]
    assembler = LiveTranslationAssembler(
        translator=StubTranslator(),
        seconds_cap=6.0,
        clock=lambda: current_time[0],
    )

    assert assembler.push_final_text("segment-session-1", "still speaking") == []

    current_time[0] = 6.0
    events = assembler.push_final_text("segment-session-1", "after six seconds")

    assert events[0]["type"] == "translation"
    assert events[0]["segment_id"] == "segment-session-1"


def test_live_translation_assembler_flushes_a_complete_sentence_before_time_cap():
    assembler = LiveTranslationAssembler(
        translator=SentenceEndingTranslator(),
        seconds_cap=6.0,
        min_sentence_words=8,
    )

    events = assembler.push_partial_text(
        "segment-session-1",
        "we need to adjust the control line before lunch",
    )

    assert events[0]["source_text"] == "we need to adjust the control line before lunch"


def test_live_translation_assembler_passes_recent_completed_pairs_to_contextual_translator():
    translator = ContextCapturingTranslator()
    assembler = LiveTranslationAssembler(
        translator=translator,
        min_sentence_words=1,
        context_pair_count=2,
    )

    assembler.push_partial_text("segment-1", "first sentence")
    assembler.push_partial_text("segment-2", "second sentence")

    assert translator.contexts == [
        [],
        [("first sentence", "vi:first sentence.")],
    ]


def test_live_translation_assembler_skips_empty_translation_without_emitting_a_blank_row():
    assembler = LiveTranslationAssembler(
        translator=EmptyTranslationTranslator(),
        min_sentence_words=1,
    )

    assert assembler.push_partial_text("segment-1", "first sentence") == []


def test_live_translation_assembler_translates_cumulative_partial_updates():
    current_time = [0.0]
    assembler = LiveTranslationAssembler(
        translator=StubTranslator(),
        seconds_cap=2.0,
        clock=lambda: current_time[0],
    )

    assert assembler.push_partial_text("segment-session-1", "i want") == []
    current_time[0] = 2.0
    events = assembler.push_partial_text("segment-session-1", "i want to review")

    assert events[0]["type"] == "translation"
    assert events[0]["source_text"] == "i want to review"


def test_session_manager_keeps_english_event_when_translation_fails():
    session_manager = SessionManager(
        adapter=FakeStreamingAdapter(),
        translator=FailingTranslator(),
    )
    start = StartMessage(
        type="start",
        session_id="translation-failure-session",
        sample_rate=16000,
        channels=1,
        sample_format="pcm_s16le",
        language="en",
    )

    session_manager.start_session("translation-failure-session", start)
    events = session_manager.push_audio(
        "translation-failure-session", b"\x00\x01" * 32000
    )

    assert [event["type"] for event in events] == ["partial", "partial", "partial"]


def test_ws_transcribe_emits_ready_partial_final_closed():
    client = TestClient(create_app(adapter=FakeStreamingAdapter()))

    with client.websocket_connect("/ws/transcribe") as websocket:
        websocket.send_json(
            {
                "type": "start",
                "session_id": "session-1",
                "sample_rate": 16000,
                "channels": 1,
                "sample_format": "pcm_s16le",
                "language": "auto",
            }
        )
        ready = websocket.receive_json()
        assert ready["type"] == "ready"

        websocket.send_bytes(b"\x00\x01" * 32000)
        partial_events = [websocket.receive_json() for _ in range(3)]
        assert [event["type"] for event in partial_events] == [
            "partial",
            "partial",
            "partial",
        ]
        assert [event["text"] for event in partial_events] == [
            "partial text",
            "partial text",
            "partial text",
        ]

        websocket.send_json({"type": "stop"})
        final_event = websocket.receive_json()
        closed_event = websocket.receive_json()
        assert final_event["type"] == "final"
        assert final_event["text"] == "final text"
        assert closed_event["type"] == "closed"


def test_ws_transcribe_rejects_invalid_start_message():
    client = TestClient(create_app(adapter=FakeStreamingAdapter()))

    with client.websocket_connect("/ws/transcribe") as websocket:
        websocket.send_json(
            {
                "type": "start",
                "session_id": "session-2",
                "sample_rate": 48000,
                "channels": 1,
                "sample_format": "pcm_s16le",
                "language": "auto",
            }
        )

        error_event = websocket.receive_json()

        assert error_event["type"] == "error"
        assert "sample_rate" in error_event["message"]


def test_ws_transcribe_rejects_unknown_message_type():
    client = TestClient(create_app(adapter=FakeStreamingAdapter()))

    with client.websocket_connect("/ws/transcribe") as websocket:
        websocket.send_json({"type": "ping"})

        error_event = websocket.receive_json()

        assert error_event["type"] == "error"
        assert "unsupported message type" in error_event["message"]


def test_ws_transcribe_rejects_malformed_text_message():
    client = TestClient(create_app(adapter=FakeStreamingAdapter()))

    with client.websocket_connect("/ws/transcribe") as websocket:
        websocket.send_text('{"bad": true}')

        error_event = websocket.receive_json()

        assert error_event["type"] == "error"
        assert "valid type" in error_event["message"]


def test_ws_transcribe_rejects_duplicate_start_message():
    client = TestClient(create_app(adapter=FakeStreamingAdapter()))

    with client.websocket_connect("/ws/transcribe") as websocket:
        start_message = {
            "type": "start",
            "session_id": "session-3",
            "sample_rate": 16000,
            "channels": 1,
            "sample_format": "pcm_s16le",
            "language": "auto",
        }
        websocket.send_json(start_message)
        ready = websocket.receive_json()
        assert ready["type"] == "ready"

        websocket.send_json(start_message)
        error_event = websocket.receive_json()

        assert error_event["type"] == "error"
        assert "already started" in error_event["message"]


def test_ws_transcribe_rejects_connections_when_adapter_is_not_ready():
    client = TestClient(create_app(adapter=NeverReadyAdapter()))

    with client.websocket_connect("/ws/transcribe") as websocket:
        error_event = websocket.receive_json()

        assert error_event["type"] == "error"
        assert "backend not ready" in error_event["message"]


def test_session_manager_rejects_duplicate_active_session_id():
    session_manager = SessionManager(adapter=FakeStreamingAdapter())
    start = StartMessage(
        type="start",
        session_id="shared-session",
        sample_rate=16000,
        channels=1,
        sample_format="pcm_s16le",
        language="auto",
    )

    session_manager.start_session("shared-session", start)

    try:
        session_manager.start_session("shared-session", start)
    except ValueError as error:
        assert "already active" in str(error)
    else:
        raise AssertionError("expected duplicate session validation error")


def test_ws_transcribe_forwards_language_hint_to_adapter():
    adapter = LanguageCapturingAdapter()
    client = TestClient(create_app(adapter=adapter))

    with client.websocket_connect("/ws/transcribe") as websocket:
        websocket.send_json(
            {
                "type": "start",
                "session_id": "session-language",
                "sample_rate": 16000,
                "channels": 1,
                "sample_format": "pcm_s16le",
                "language": "en",
            }
        )
        ready = websocket.receive_json()
        assert ready["type"] == "ready"
        websocket.send_json({"type": "stop"})
        closed_event = websocket.receive_json()
        assert closed_event["type"] == "closed"

    assert adapter.languages == ["en"]


def test_ws_transcribe_returns_structured_error_when_audio_processing_fails():
    client = TestClient(create_app(adapter=BrokenAudioAdapter()))

    with client.websocket_connect("/ws/transcribe") as websocket:
        websocket.send_json(
            {
                "type": "start",
                "session_id": "session-error",
                "sample_rate": 16000,
                "channels": 1,
                "sample_format": "pcm_s16le",
                "language": "auto",
            }
        )
        ready = websocket.receive_json()
        assert ready["type"] == "ready"

        websocket.send_bytes(b"\x00\x01" * 32000)
        error_event = websocket.receive_json()

        assert error_event["type"] == "error"
        assert "bad audio chunk" in error_event["message"]


def test_ws_transcribe_treats_post_disconnect_receive_runtime_as_normal_close(
):
    adapter = CleanupCapturingAdapter()
    router = build_ws_router(SessionManager(adapter=adapter), adapter)
    endpoint = next(
        route.endpoint
        for route in router.routes
        if getattr(route, "path", None) == "/ws/transcribe"
    )

    class FakeWebSocket:
        def __init__(self) -> None:
            self.accepted = False
            self.sent_messages: list[dict] = []
            self.receive_calls = 0

        async def accept(self) -> None:
            self.accepted = True

        async def receive(self) -> dict:
            self.receive_calls += 1
            if self.receive_calls == 1:
                return {
                    "text": (
                        '{"type":"start","session_id":"session-disconnect",'
                        '"sample_rate":16000,"channels":1,'
                        '"sample_format":"pcm_s16le","language":"auto"}'
                    )
                }
            raise RuntimeError(
                'Cannot call "receive" once a disconnect message has been received.'
            )

        async def send_json(self, payload: dict) -> None:
            self.sent_messages.append(payload)

        async def close(self) -> None:
            return None

    websocket = FakeWebSocket()

    asyncio.run(endpoint(websocket))

    assert websocket.accepted is True
    assert websocket.sent_messages == [{"type": "ready", "session_id": "session-disconnect"}]
    assert adapter.ended_sessions == ["session-disconnect"]
