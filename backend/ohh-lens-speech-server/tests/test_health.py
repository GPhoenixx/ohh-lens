import os

from fastapi.testclient import TestClient

import app.main as app_main
from app.core.config import get_settings
from app.main import create_app


class StubReadyFunASRAdapter:
    def __init__(self, model_name: str, device: str) -> None:
        self.model_name = model_name
        self.device = device
        self._ready = False

    def load(self) -> None:
        self._ready = True

    def ready(self) -> bool:
        return True


class StubConfigAwareFunASRAdapter:
    def __init__(self, model_name: str, device: str) -> None:
        self.model_name = model_name
        self.device = device
        self._ready = False

    def load(self) -> None:
        self._ready = bool(self.model_name) and bool(self.device)

    def ready(self) -> bool:
        return self._ready


def test_health_reports_expected_defaults():
    settings = get_settings()
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
        "model": settings.funasr_model_name,
        "device": settings.funasr_device,
    }


def test_health_reports_backend_ready_when_adapter_is_ready():
    original_adapter = app_main.FunASRStreamingAdapter
    app_main.FunASRStreamingAdapter = StubReadyFunASRAdapter

    try:
        with TestClient(create_app(adapter_ready=True)) as client:
            response = client.get("/health")
    finally:
        app_main.FunASRStreamingAdapter = original_adapter

    assert response.status_code == 200
    assert response.json()["backend_ready"] is True


def test_health_reports_runtime_config_from_settings():
    settings = get_settings()
    client = TestClient(create_app())

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["model"] == settings.funasr_model_name
    assert response.json()["device"] == settings.funasr_device


def test_health_uses_runtime_env_when_building_real_adapter():
    original_adapter = app_main.FunASRStreamingAdapter
    original_model_name = os.environ.get("FUNASR_MODEL_NAME")
    original_device = os.environ.get("FUNASR_DEVICE")
    os.environ["FUNASR_MODEL_NAME"] = "iic/SenseVoiceSmall"
    os.environ["FUNASR_DEVICE"] = "cpu"
    app_main.FunASRStreamingAdapter = StubConfigAwareFunASRAdapter

    try:
        with TestClient(create_app(adapter_ready=True)) as client:
            response = client.get("/health")
    finally:
        app_main.FunASRStreamingAdapter = original_adapter
        if original_model_name is None:
            os.environ.pop("FUNASR_MODEL_NAME", None)
        else:
            os.environ["FUNASR_MODEL_NAME"] = original_model_name
        if original_device is None:
            os.environ.pop("FUNASR_DEVICE", None)
        else:
            os.environ["FUNASR_DEVICE"] = original_device

    assert response.status_code == 200
    assert response.json()["backend_ready"] is True
    assert response.json()["model"] == "iic/SenseVoiceSmall"
    assert response.json()["device"] == "cpu"
