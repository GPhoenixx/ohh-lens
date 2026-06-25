from fastapi import FastAPI

from app.api.health import build_health_router
from app.api.ws import build_ws_router
from app.core.config import get_settings
from app.core.session_manager import SessionManager
from app.funasr.adapter import FakeStreamingAdapter


def create_app() -> FastAPI:
    settings = get_settings()
    session_manager = SessionManager(adapter=FakeStreamingAdapter())
    app = FastAPI(title="Ohh Lens Speech Server", version="0.1.0")
    app.include_router(build_health_router(settings))
    app.include_router(build_ws_router(session_manager))
    return app


app = create_app()
