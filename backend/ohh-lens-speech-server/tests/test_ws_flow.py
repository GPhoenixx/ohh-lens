import asyncio

from fastapi.testclient import TestClient

from app.api.ws import build_ws_router
from app.core.protocol import StartMessage
from app.core.session_manager import SessionManager
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
