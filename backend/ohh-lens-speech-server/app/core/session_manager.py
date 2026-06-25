from app.audio.buffer import PCMChunkBuffer
from app.core.protocol import event_payload
from app.funasr.adapter import StreamingAdapter


class SessionManager:
    def __init__(self, adapter: StreamingAdapter, chunk_bytes: int = 8000) -> None:
        self.adapter = adapter
        self.chunk_bytes = chunk_bytes
        self.buffers: dict[str, PCMChunkBuffer] = {}

    def start_session(self, session_id: str) -> dict:
        self.buffers[session_id] = PCMChunkBuffer(chunk_bytes=self.chunk_bytes)
        self.adapter.begin(session_id)
        return event_payload("ready", session_id)

    def push_audio(self, session_id: str, audio: bytes) -> list[dict]:
        buffer = self.buffers[session_id]
        buffer.append(audio)
        events: list[dict] = []
        for chunk in buffer.pop_ready_chunks():
            for result in self.adapter.push_audio(session_id, chunk, is_final=False):
                event_type = "final" if result.is_final else "partial"
                events.append(
                    event_payload(
                        event_type,
                        session_id,
                        text=result.text,
                        start_ms=result.start_ms,
                        end_ms=result.end_ms,
                    )
                )
        return events

    def stop_session(self, session_id: str) -> list[dict]:
        buffer = self.buffers[session_id]
        remainder = buffer.flush()
        events: list[dict] = []
        try:
            for result in self.adapter.push_audio(session_id, remainder, is_final=True):
                event_type = "final" if result.is_final else "partial"
                events.append(
                    event_payload(
                        event_type,
                        session_id,
                        text=result.text,
                        start_ms=result.start_ms,
                        end_ms=result.end_ms,
                    )
                )
        finally:
            self.cleanup_session(session_id)
        events.append(event_payload("closed", session_id))
        return events

    def cleanup_session(self, session_id: str) -> None:
        if session_id not in self.buffers:
            return

        try:
            self.adapter.end(session_id)
        finally:
            self.buffers.pop(session_id, None)
