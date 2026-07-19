from typing import Literal

from pydantic import BaseModel, field_validator


SUPPORTED_LANGUAGE_CODES = frozenset(
    {
        "zh",
        "en",
        "yue",
        "ar",
        "de",
        "fr",
        "es",
        "pt",
        "id",
        "it",
        "ko",
        "ru",
        "th",
        "vi",
        "ja",
        "tr",
        "hi",
        "ms",
        "nl",
        "sv",
        "da",
        "fi",
        "pl",
        "cs",
        "fil",
        "fa",
        "el",
        "hu",
        "mk",
        "ro",
    }
)


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

    @field_validator("language", "target_language", mode="before")
    @classmethod
    def validate_language_code(cls, value: str, info) -> str:
        if not isinstance(value, str):
            raise ValueError(f"{info.field_name} must be a language code")
        normalized = value.strip().lower()
        if info.field_name == "language" and normalized == "auto":
            return normalized
        if info.field_name == "target_language" and normalized == "same":
            return normalized
        if normalized not in SUPPORTED_LANGUAGE_CODES:
            raise ValueError(f"{info.field_name} must be one of the supported language codes")
        return normalized


class StopMessage(BaseModel):
    type: Literal["stop"]


def event_payload(event_type: str, session_id: str, **payload: object) -> dict:
    base = {"type": event_type, "session_id": session_id}
    base.update(payload)
    return base
