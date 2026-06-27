import os

from pydantic import BaseModel


class Settings(BaseModel):
    service_name: str = "ohh-lens-speech-server"
    sample_rate: int = 16000
    channels: int = 1
    sample_format: str = "pcm_s16le"
    funasr_model_name: str = "iic/SenseVoiceSmall"
    funasr_device: str = "mps"


def get_settings() -> Settings:
    return Settings(
        funasr_model_name=os.getenv("FUNASR_MODEL_NAME", "iic/SenseVoiceSmall"),
        funasr_device=os.getenv("FUNASR_DEVICE", "mps"),
    )
