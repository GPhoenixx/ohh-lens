from typing import Literal

from pydantic import BaseModel, field_validator


class StartMessage(BaseModel):
    type: Literal["start"]
    session_id: str
    sample_rate: int
    channels: int
    sample_format: str
    language: str = "auto"
    target_language: str = "vi"

    @field_validator("sample_rate")
    @classmethod
    def validate_sample_rate(cls, value: int) -> int:
        if value != 16000:
            raise ValueError("sample_rate must be 16000")
        return value

    @field_validator("channels")
    @classmethod
    def validate_channels(cls, value: int) -> int:
        if value != 1:
            raise ValueError("channels must be 1")
        return value

    @field_validator("sample_format")
    @classmethod
    def validate_sample_format(cls, value: str) -> str:
        if value != "pcm_s16le":
            raise ValueError("sample_format must be pcm_s16le")
        return value


class StopMessage(BaseModel):
    type: Literal["stop"]


def event_payload(event_type: str, session_id: str, **payload: object) -> dict:
    base = {"type": event_type, "session_id": session_id}
    base.update(payload)
    return base
