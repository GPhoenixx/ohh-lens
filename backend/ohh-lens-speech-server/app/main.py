from fastapi import FastAPI

from app.api.health import build_health_router
from app.core.config import get_settings


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(title="Ohh Lens Speech Server", version="0.1.0")
    app.include_router(build_health_router(settings))
    return app


app = create_app()
