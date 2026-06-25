from fastapi import APIRouter

from app.core.config import Settings
from app.funasr.adapter import StreamingAdapter


def build_health_router(settings: Settings, adapter: StreamingAdapter) -> APIRouter:
    router = APIRouter()

    @router.get("/health")
    async def health() -> dict:
        return {
            "status": "ok",
            "service": settings.service_name,
            "sample_rate": settings.sample_rate,
            "channels": settings.channels,
            "sample_format": settings.sample_format,
            "backend_ready": adapter.ready(),
            "model": settings.model_name,
        }

    return router
