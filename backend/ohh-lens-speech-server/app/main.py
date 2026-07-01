from contextlib import asynccontextmanager
import logging
from typing import Optional

from fastapi import FastAPI

from app.api.health import build_health_router
from app.api.ws import build_ws_router
from app.core.config import get_settings
from app.core.session_manager import SessionManager
from app.funasr.adapter import (
    FunASRStreamingAdapter,
    StreamingAdapter,
)


logger = logging.getLogger(__name__)


def _bytes_per_sample(sample_format: str) -> int:
    if sample_format == "pcm_s16le":
        return 2
    raise ValueError(f"unsupported sample format for chunk sizing: {sample_format}")


def _streaming_chunk_bytes(settings) -> int:
    stride_units = settings.funasr_asr_chunk_size[1]
    stride_ms = stride_units * 60
    bytes_per_frame = settings.channels * _bytes_per_sample(settings.sample_format)
    return int(settings.sample_rate * stride_ms / 1000) * bytes_per_frame


def _create_app(
    adapter: Optional[StreamingAdapter] = None, adapter_ready: bool = False
) -> FastAPI:   
    settings = get_settings()
    active_adapter = adapter or FunASRStreamingAdapter(
        model_name=settings.funasr_model_name,
        device=settings.funasr_device,
        hub=settings.funasr_hub,
        vad_model_name=settings.funasr_vad_model_name,
        vad_chunk_ms=settings.funasr_vad_chunk_ms,
        sample_rate=settings.sample_rate,
        asr_chunk_size=settings.funasr_asr_chunk_size,
        encoder_chunk_look_back=settings.funasr_encoder_chunk_look_back,
        decoder_chunk_look_back=settings.funasr_decoder_chunk_look_back,
    )
    session_manager = SessionManager(
        adapter=active_adapter,
        chunk_bytes=_streaming_chunk_bytes(settings),
    )

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        if adapter is None and adapter_ready:
            try:
                active_adapter.load()
            except Exception:
                # Leave the adapter in a not-ready state so health and ws gating can surface it.
                logger.exception("Failed to load speech backend")
        yield

    app = FastAPI(
        title="Ohh Lens Speech Server",
        version="0.1.0",
        lifespan=lifespan,
    )

    app.include_router(build_health_router(settings, active_adapter))
    app.include_router(build_ws_router(session_manager, active_adapter))
    return app


def create_app(
    adapter_ready: bool = False, adapter: Optional[StreamingAdapter] = None
) -> FastAPI:
    return _create_app(adapter=adapter, adapter_ready=adapter_ready)


def create_default_app() -> FastAPI:
    return create_app(adapter_ready=True)


app = create_default_app()
