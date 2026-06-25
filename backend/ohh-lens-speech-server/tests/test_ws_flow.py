from fastapi.testclient import TestClient

from app.main import create_app


def test_ws_transcribe_emits_ready_partial_final_closed():
    client = TestClient(create_app())

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

        websocket.send_bytes(b"\x00\x01" * 4000)
        partial = websocket.receive_json()
        assert partial["type"] == "partial"
        assert partial["text"] == "partial text"

        websocket.send_json({"type": "stop"})
        final_event = websocket.receive_json()
        closed_event = websocket.receive_json()
        assert final_event["type"] == "final"
        assert final_event["text"] == "final text"
        assert closed_event["type"] == "closed"


def test_ws_transcribe_rejects_invalid_start_message():
    client = TestClient(create_app())

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
    client = TestClient(create_app())

    with client.websocket_connect("/ws/transcribe") as websocket:
        websocket.send_json({"type": "ping"})

        error_event = websocket.receive_json()

        assert error_event["type"] == "error"
        assert "unsupported message type" in error_event["message"]


def test_ws_transcribe_rejects_malformed_text_message():
    client = TestClient(create_app())

    with client.websocket_connect("/ws/transcribe") as websocket:
        websocket.send_text('{"bad": true}')

        error_event = websocket.receive_json()

        assert error_event["type"] == "error"
        assert "valid type" in error_event["message"]


def test_ws_transcribe_rejects_duplicate_start_message():
    client = TestClient(create_app())

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
