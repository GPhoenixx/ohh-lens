import os

from pydantic import BaseModel


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
    funasr_model_name: str = "iic/SenseVoiceSmall"
    funasr_device: str = "mps"
    funasr_hub: str = "hf"
    funasr_vad_model_name: str = "fsmn-vad"
    funasr_vad_chunk_ms: int = 200
    funasr_asr_chunk_size: list[int] = [0, 10, 5]
    funasr_encoder_chunk_look_back: int = 4
    funasr_decoder_chunk_look_back: int = 1


def get_settings() -> Settings:
    return Settings(
        funasr_model_name=os.getenv("FUNASR_MODEL_NAME", "iic/SenseVoiceSmall"),
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
    )
