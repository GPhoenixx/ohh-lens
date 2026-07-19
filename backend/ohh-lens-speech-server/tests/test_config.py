import platform

from app.core.config import get_settings


def test_apple_silicon_defaults_to_mlx_model(monkeypatch):
    monkeypatch.delenv("TRANSLATION_MODEL_NAME", raising=False)
    monkeypatch.setattr(platform, "machine", lambda: "arm64")

    assert get_settings().translation_model_name == (
        "mlx-community/Qwen3-8B-4bit"
    )


def test_non_apple_silicon_keeps_huggingface_default(monkeypatch):
    monkeypatch.delenv("TRANSLATION_MODEL_NAME", raising=False)
    monkeypatch.setattr(platform, "machine", lambda: "x86_64")

    assert get_settings().translation_model_name == "facebook/m2m100_418M"


def test_explicit_translation_model_overrides_platform_default(monkeypatch):
    monkeypatch.setenv("TRANSLATION_MODEL_NAME", "Qwen/Qwen2.5-7B-Instruct")
    monkeypatch.setattr(platform, "machine", lambda: "arm64")

    assert get_settings().translation_model_name == "Qwen/Qwen2.5-7B-Instruct"
