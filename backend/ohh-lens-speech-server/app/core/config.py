import os
import platform

from pydantic import BaseModel


DEFAULT_TRANSLATION_MODEL = "facebook/m2m100_418M"
APPLE_SILICON_TRANSLATION_MODEL = "mlx-community/Qwen3-8B-4bit"


def _default_translation_model() -> str:
    return (
        APPLE_SILICON_TRANSLATION_MODEL
        if platform.machine().lower() in {"arm64", "aarch64"}
        else DEFAULT_TRANSLATION_MODEL
    )


def _parse_int_list_env(name: str, default: list[int]) -> list[int]:
    value = os.getenv(name)
    if value is None:
        return default
    return [int(item.strip()) for item in value.split(",") if item.strip()]


class Settings(BaseModel):
    service_name: str = "ohh-lens-speech-server"
    sample_rate: int = 16000
    channels: int = 1
    sample_format: str = "pcm_s16le"
    funasr_model_name: str = "Qwen/Qwen3-ASR-0.6B"
    funasr_device: str = "mps"
    funasr_hub: str = "hf"
    funasr_vad_model_name: str = "fsmn-vad"
    funasr_vad_chunk_ms: int = 200
    funasr_asr_chunk_size: list[int] = [0, 10, 5]
    funasr_encoder_chunk_look_back: int = 4
    funasr_decoder_chunk_look_back: int = 1
    funasr_min_audio_rms: float = 0.0
    translation_model_name: str = DEFAULT_TRANSLATION_MODEL
    translation_device: str = "cpu"
    translation_seconds_cap: float = 6.0
    translation_min_sentence_words: int = 8
    translation_context_pair_count: int = 4


def get_settings() -> Settings:
    return Settings(
        funasr_model_name=os.getenv("FUNASR_MODEL_NAME", "Qwen/Qwen3-ASR-0.6B"),
        funasr_device=os.getenv("FUNASR_DEVICE", "mps"),
        funasr_hub=os.getenv("FUNASR_HUB", "hf"),
        funasr_vad_model_name=os.getenv("FUNASR_VAD_MODEL_NAME", "fsmn-vad"),
        funasr_vad_chunk_ms=int(os.getenv("FUNASR_VAD_CHUNK_MS", "200")),
        funasr_asr_chunk_size=_parse_int_list_env("FUNASR_ASR_CHUNK_SIZE", [0, 10, 5]),
        funasr_encoder_chunk_look_back=int(
            os.getenv("FUNASR_ENCODER_CHUNK_LOOK_BACK", "4")
        ),
        funasr_decoder_chunk_look_back=int(
            os.getenv("FUNASR_DECODER_CHUNK_LOOK_BACK", "1")
        ),
        funasr_min_audio_rms=float(os.getenv("FUNASR_MIN_AUDIO_RMS", "0.0")),
        translation_model_name=os.getenv(
            "TRANSLATION_MODEL_NAME", _default_translation_model()
        ),
        translation_device=os.getenv("TRANSLATION_DEVICE", "cpu"),
        translation_seconds_cap=float(os.getenv("TRANSLATION_SECONDS_CAP", "6.0")),
        translation_min_sentence_words=int(
            os.getenv("TRANSLATION_MIN_SENTENCE_WORDS", "8")
        ),
        translation_context_pair_count=int(
            os.getenv("TRANSLATION_CONTEXT_PAIR_COUNT", "2")
        ),
    )
