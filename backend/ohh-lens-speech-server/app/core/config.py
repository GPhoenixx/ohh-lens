import os
from pathlib import Path
from typing import Optional

from pydantic import BaseModel


class Settings(BaseModel):
    service_name: str = "ohh-lens-speech-server"
    sample_rate: int = 16000
    channels: int = 1
    sample_format: str = "pcm_s16le"
    model_name: str = "funasr-streaming"
    funasr_model_path: Optional[str] = None


def get_settings() -> Settings:
    default_model_path = str(
        Path.home() / ".ohh-lens" / "models" / "funasr"
    )
    return Settings(
        funasr_model_path=os.getenv("FUNASR_MODEL_PATH", default_model_path)
    )
