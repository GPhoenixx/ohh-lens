from pydantic import BaseModel


class Settings(BaseModel):
    service_name: str = "ohh-lens-speech-server"
    sample_rate: int = 16000
    channels: int = 1
    sample_format: str = "pcm_s16le"
    model_name: str = "funasr-streaming"


def get_settings() -> Settings:
    return Settings()
