import logging
import os

from fastapi.testclient import TestClient

import app.main as app_main
from app.core.config import get_settings
from app.main import create_app


class StubReadyFunASRAdapter:
    def __init__(self, model_name: str, device: str, **_: object) -> None:
        self.model_name = model_name
        self.device = device
        self._ready = False

    def load(self) -> None:
        self._ready = True

    def ready(self) -> bool:
        return True


class StubConfigAwareFunASRAdapter:
    last_kwargs: dict[str, object] | None = None

    def __init__(self, model_name: str, device: str, **kwargs: object) -> None:
        self.model_name = model_name
        self.device = device
        self._ready = False
        self.last_kwargs = kwargs
        type(self).last_kwargs = kwargs

    def load(self) -> None:
        self._ready = bool(self.model_name) and bool(self.device)

    def ready(self) -> bool:
        return self._ready


class StubBrokenQwenAdapter:
    def __init__(self, model_name: str, device: str, **_: object) -> None:
        self.model_name = model_name
        self.device = device

    def load(self) -> None:
        raise ImportError(
            "Qwen/Qwen3-ASR-1.7B requires the qwen-asr package. "
            "Install with: pip install qwen-asr"
        )

    def ready(self) -> bool:
        return False


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
    original_hub = os.environ.get("FUNASR_HUB")
    os.environ["FUNASR_MODEL_NAME"] = "iic/SenseVoiceSmall"
    os.environ["FUNASR_DEVICE"] = "cpu"
    os.environ["FUNASR_HUB"] = "hf"
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
        if original_hub is None:
            os.environ.pop("FUNASR_HUB", None)
        else:
            os.environ["FUNASR_HUB"] = original_hub

    assert response.status_code == 200
    assert response.json()["backend_ready"] is True
    assert response.json()["model"] == "iic/SenseVoiceSmall"
    assert response.json()["device"] == "cpu"
    assert StubConfigAwareFunASRAdapter.last_kwargs is not None
    assert StubConfigAwareFunASRAdapter.last_kwargs["hub"] == "hf"
    assert StubConfigAwareFunASRAdapter.last_kwargs["asr_chunk_size"] == [0, 10, 5]
    assert StubConfigAwareFunASRAdapter.last_kwargs["encoder_chunk_look_back"] == 4
    assert StubConfigAwareFunASRAdapter.last_kwargs["decoder_chunk_look_back"] == 1


def test_startup_logs_clear_error_when_qwen_dependency_is_missing(caplog):
    original_adapter = app_main.FunASRStreamingAdapter
    app_main.FunASRStreamingAdapter = StubBrokenQwenAdapter
    caplog.set_level(logging.ERROR)

    try:
        with TestClient(create_app(adapter_ready=True)) as client:
            response = client.get("/health")
    finally:
        app_main.FunASRStreamingAdapter = original_adapter

    assert response.status_code == 200
    assert response.json()["backend_ready"] is False
    assert "Failed to load speech backend" in caplog.text
    assert "requires the qwen-asr package" in caplog.text
