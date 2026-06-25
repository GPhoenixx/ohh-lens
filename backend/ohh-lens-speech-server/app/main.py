from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.api.health import build_health_router
from app.api.ws import build_ws_router
from app.core.config import get_settings
from app.core.session_manager import SessionManager
from app.funasr.adapter import (
    FunASRStreamingAdapter,
    StreamingAdapter,
)


def _create_app(
    adapter: StreamingAdapter | None = None, adapter_ready: bool = False
) -> FastAPI:
    settings = get_settings()
    active_adapter = adapter or FunASRStreamingAdapter()
    session_manager = SessionManager(adapter=active_adapter)
    
    @asynccontextmanager
    async def lifespan(_: FastAPI):
        if adapter is None and adapter_ready:
            try:
                active_adapter.load()
            except Exception:
                # Leave the adapter in a not-ready state so health and ws gating can surface it.
                pass
        yield

    app = FastAPI(
        title="Ohh Lens Speech Server",
        version="0.1.0",
        lifespan=lifespan,
    )

    app.include_router(build_health_router(settings, active_adapter))
    app.include_router(build_ws_router(session_manager, active_adapter))
    return app


def create_app(adapter_ready: bool = False, adapter: StreamingAdapter | None = None) -> FastAPI:
    return _create_app(adapter=adapter, adapter_ready=adapter_ready)


def create_default_app() -> FastAPI:
    return create_app(adapter_ready=True)


app = create_default_app()
