import json

from fastapi import APIRouter, WebSocket
from starlette.websockets import WebSocketDisconnect
from pydantic import ValidationError

from app.core.protocol import StartMessage, StopMessage
from app.core.session_manager import SessionManager
from app.funasr.adapter import StreamingAdapter


def build_ws_router(
    session_manager: SessionManager, adapter: StreamingAdapter
) -> APIRouter:
    router = APIRouter()

    @router.websocket("/ws/transcribe")
    async def transcribe_socket(websocket: WebSocket) -> None:
        await websocket.accept()

        if not adapter.ready():
            await websocket.send_json(
                {"type": "error", "message": "backend not ready"}
            )
            await websocket.close()
            return

        session_id: str | None = None

        try:
            while True:
                message = await websocket.receive()
                if "text" in message and message["text"] is not None:
                    payload = message["text"]
                    try:
                        try:
                            decoded_payload = json.loads(payload)
                            if not isinstance(decoded_payload, dict):
                                raise TypeError("message payload must be an object")
                            message_type = decoded_payload["type"]
                        except (json.JSONDecodeError, KeyError, TypeError) as error:
                            raise ValueError("message must include a valid type") from error

                        if message_type == "start":
                            if session_id is not None:
                                raise ValueError("session has already started")
                            start = StartMessage.model_validate_json(payload)
                            session_id = start.session_id
                            await websocket.send_json(
                                session_manager.start_session(session_id)
                            )
                        elif message_type == "stop":
                            StopMessage.model_validate_json(payload)
                            if session_id is None:
                                raise ValueError("session has not started")
                            for event in session_manager.stop_session(session_id):
                                await websocket.send_json(event)
                            return
                        else:
                            raise ValueError(f"unsupported message type: {message_type}")
                    except (ValidationError, ValueError) as error:
                        await websocket.send_json({"type": "error", "message": str(error)})
                        await websocket.close()
                        return
                elif "bytes" in message and message["bytes"] is not None:
                    if session_id is None:
                        await websocket.send_json(
                            {"type": "error", "message": "session has not started"}
                        )
                        await websocket.close()
                        return
                    try:
                        for event in session_manager.push_audio(session_id, message["bytes"]):
                            await websocket.send_json(event)
                    except Exception as error:
                        await websocket.send_json({"type": "error", "message": str(error)})
                        await websocket.close()
                        return
        except WebSocketDisconnect:
            return
        finally:
            if session_id is not None:
                session_manager.cleanup_session(session_id)

    return router
