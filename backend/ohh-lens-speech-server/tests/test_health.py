from fastapi.testclient import TestClient

import app.main as app_main
from app.main import create_app


class StubReadyFunASRAdapter:
    def __init__(self) -> None:
        self._ready = False

    def load(self) -> None:
        self._ready = True

    def ready(self) -> bool:
        return True


def test_health_reports_expected_defaults():
    client = TestClient(create_app())

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "service": "ohh-lens-speech-server",
        "sample_rate": 16000,
        "channels": 1,
        "sample_format": "pcm_s16le",
        "backend_ready": False,
        "model": "funasr-streaming",
    }


def test_health_reports_backend_ready_when_adapter_is_ready():
    original_adapter = app_main.FunASRStreamingAdapter
    app_main.FunASRStreamingAdapter = StubReadyFunASRAdapter

    try:
        client = TestClient(create_app(adapter_ready=True))
    finally:
        app_main.FunASRStreamingAdapter = original_adapter

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["backend_ready"] is True
