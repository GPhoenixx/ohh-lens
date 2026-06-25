# Ohh Lens Speech Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone local FastAPI backend that accepts `16 kHz` mono `PCM int16` audio over WebSocket, runs incremental FunASR transcription, and emits partial plus final transcript events for the Ohh Lens macOS app.

**Architecture:** Create a separate Python project under `backend/ohh-lens-speech-server/` with a small WebSocket protocol layer, deterministic PCM buffering, a session manager, and a FunASR adapter that hides model-specific streaming details. Keep the app-facing contract stable even if the adapter needs fallback behavior while we learn the exact FunASR incremental API behavior.

**Tech Stack:** Python 3.11+, FastAPI, Uvicorn, Pydantic, pytest, pytest-asyncio, websockets via FastAPI/Starlette, NumPy, FunASR

---

## Progress Tracking

- [x] Task 1 complete: scaffold the backend project and health surface
- [-] Task 2 in progress: define protocol types and deterministic PCM buffering
- [ ] Task 3 pending: add session orchestration and WebSocket flow with a fake streaming engine
- [ ] Task 4 pending: integrate the real FunASR adapter and readiness gating
- [ ] Task 5 pending: document running, testing, and crash-recovery workflow

When executing this plan, update the task line statuses directly:

- change a task to `[-]` while it is in progress
- change it to `[x]` only after tests pass and the task commit is created

## File Structure

- Create: `backend/ohh-lens-speech-server/pyproject.toml`
  Python project metadata and dependencies.
- Create: `backend/ohh-lens-speech-server/README.md`
  Local run instructions and protocol documentation.
- Create: `backend/ohh-lens-speech-server/app/main.py`
  FastAPI app factory and startup wiring.
- Create: `backend/ohh-lens-speech-server/app/api/health.py`
  `GET /health` and optional readiness routes.
- Create: `backend/ohh-lens-speech-server/app/api/ws.py`
  `/ws/transcribe` route and WebSocket message loop.
- Create: `backend/ohh-lens-speech-server/app/core/config.py`
  Environment-driven runtime configuration.
- Create: `backend/ohh-lens-speech-server/app/core/protocol.py`
  Pydantic message schemas and event serialization helpers.
- Create: `backend/ohh-lens-speech-server/app/core/session_manager.py`
  Session lifecycle and coordination between buffer, adapter, and socket.
- Create: `backend/ohh-lens-speech-server/app/audio/buffer.py`
  Byte-oriented PCM buffer and chunk extraction logic.
- Create: `backend/ohh-lens-speech-server/app/funasr/models.py`
  Internal result models used by the adapter and session manager.
- Create: `backend/ohh-lens-speech-server/app/funasr/adapter.py`
  Adapter protocol, fake adapter, and real FunASR adapter.
- Create: `backend/ohh-lens-speech-server/tests/test_health.py`
  Health endpoint tests.
- Create: `backend/ohh-lens-speech-server/tests/test_protocol.py`
  Message validation tests.
- Create: `backend/ohh-lens-speech-server/tests/test_buffer.py`
  PCM buffering tests.
- Create: `backend/ohh-lens-speech-server/tests/test_ws_flow.py`
  WebSocket happy-path and error-path tests.

## Task 1: Scaffold The Backend Project And Health Surface

**Files:**
- Create: `backend/ohh-lens-speech-server/pyproject.toml`
- Create: `backend/ohh-lens-speech-server/app/main.py`
- Create: `backend/ohh-lens-speech-server/app/core/config.py`
- Create: `backend/ohh-lens-speech-server/app/api/health.py`
- Create: `backend/ohh-lens-speech-server/tests/test_health.py`

- [ ] **Step 1: Write the failing health test**

```python
from fastapi.testclient import TestClient

from app.main import create_app


def test_health_reports_expected_defaults():
    client = TestClient(create_app())

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "service": "ohh-lens-speech-server",
        "sample_rate": 16000,
        "channels": 1,
        "sample_format": "pcm_s16le",
        "backend_ready": False,
        "model": "funasr-streaming",
    }
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
cd /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server && pytest tests/test_health.py -v
```

Expected: FAIL with `ModuleNotFoundError` for `app.main` or missing `create_app`

- [ ] **Step 3: Add the minimal project and health implementation**

```toml
# backend/ohh-lens-speech-server/pyproject.toml
[build-system]
requires = ["setuptools>=68", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "ohh-lens-speech-server"
version = "0.1.0"
description = "Local streaming speech gateway for Ohh Lens"
requires-python = ">=3.11"
dependencies = [
  "fastapi>=0.115,<1.0",
  "uvicorn[standard]>=0.30,<1.0",
  "pydantic>=2.8,<3.0",
  "numpy>=1.26,<3.0",
  "funasr",
]

[project.optional-dependencies]
dev = [
  "pytest>=8.2,<9.0",
  "pytest-asyncio>=0.23,<1.0",
]
```

```python
# backend/ohh-lens-speech-server/app/core/config.py
from pydantic import BaseModel


class Settings(BaseModel):
    service_name: str = "ohh-lens-speech-server"
    sample_rate: int = 16000
    channels: int = 1
    sample_format: str = "pcm_s16le"
    model_name: str = "funasr-streaming"


def get_settings() -> Settings:
    return Settings()
```

```python
# backend/ohh-lens-speech-server/app/api/health.py
from fastapi import APIRouter

from app.core.config import Settings


def build_health_router(settings: Settings) -> APIRouter:
    router = APIRouter()

    @router.get("/health")
    async def health() -> dict:
        return {
            "status": "ok",
            "service": settings.service_name,
            "sample_rate": settings.sample_rate,
            "channels": settings.channels,
            "sample_format": settings.sample_format,
            "backend_ready": False,
            "model": settings.model_name,
        }

    return router
```

```python
# backend/ohh-lens-speech-server/app/main.py
from fastapi import FastAPI

from app.api.health import build_health_router
from app.core.config import get_settings


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(title="Ohh Lens Speech Server", version="0.1.0")
    app.include_router(build_health_router(settings))
    return app


app = create_app()
```

- [ ] **Step 4: Run the focused test to verify it passes**

Run:

```bash
cd /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server && pytest tests/test_health.py -v
```

Expected: PASS

- [ ] **Step 5: Commit the scaffold slice**

```bash
git add backend/ohh-lens-speech-server/pyproject.toml backend/ohh-lens-speech-server/app/main.py backend/ohh-lens-speech-server/app/core/config.py backend/ohh-lens-speech-server/app/api/health.py backend/ohh-lens-speech-server/tests/test_health.py
git commit -m "feat: scaffold speech server health surface"
```

## Task 2: Define Protocol Types And Deterministic PCM Buffering

**Files:**
- Create: `backend/ohh-lens-speech-server/app/core/protocol.py`
- Create: `backend/ohh-lens-speech-server/app/audio/buffer.py`
- Create: `backend/ohh-lens-speech-server/tests/test_protocol.py`
- Create: `backend/ohh-lens-speech-server/tests/test_buffer.py`

- [ ] **Step 1: Write the failing protocol and buffer tests**

```python
from app.audio.buffer import PCMChunkBuffer
from app.core.protocol import StartMessage


def test_start_message_rejects_wrong_sample_rate():
    try:
        StartMessage(
            type="start",
            session_id="abc",
            sample_rate=48000,
            channels=1,
            sample_format="pcm_s16le",
            language="auto",
        )
    except ValueError as error:
        assert "sample_rate" in str(error)
    else:
        raise AssertionError("expected validation error")


def test_pcm_buffer_yields_full_chunk_and_keeps_remainder():
    buffer = PCMChunkBuffer(chunk_bytes=8)

    buffer.append(b"1234567890")

    assert buffer.pop_ready_chunks() == [b"12345678"]
    assert buffer.flush() == b"90"
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run:

```bash
cd /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server && pytest tests/test_protocol.py tests/test_buffer.py -v
```

Expected: FAIL with missing `StartMessage` or `PCMChunkBuffer`

- [ ] **Step 3: Add minimal protocol and buffer implementations**

```python
# backend/ohh-lens-speech-server/app/core/protocol.py
from typing import Literal

from pydantic import BaseModel, field_validator


class StartMessage(BaseModel):
    type: Literal["start"]
    session_id: str
    sample_rate: int
    channels: int
    sample_format: str
    language: str = "auto"

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
```

```python
# backend/ohh-lens-speech-server/app/audio/buffer.py
class PCMChunkBuffer:
    def __init__(self, chunk_bytes: int) -> None:
        self.chunk_bytes = chunk_bytes
        self._buffer = bytearray()

    def append(self, chunk: bytes) -> None:
        self._buffer.extend(chunk)

    def pop_ready_chunks(self) -> list[bytes]:
        chunks: list[bytes] = []
        while len(self._buffer) >= self.chunk_bytes:
            chunks.append(bytes(self._buffer[: self.chunk_bytes]))
            del self._buffer[: self.chunk_bytes]
        return chunks

    def flush(self) -> bytes:
        remainder = bytes(self._buffer)
        self._buffer.clear()
        return remainder
```

- [ ] **Step 4: Run the focused tests to verify they pass**

Run:

```bash
cd /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server && pytest tests/test_protocol.py tests/test_buffer.py -v
```

Expected: PASS

- [ ] **Step 5: Commit the protocol slice**

```bash
git add backend/ohh-lens-speech-server/app/core/protocol.py backend/ohh-lens-speech-server/app/audio/buffer.py backend/ohh-lens-speech-server/tests/test_protocol.py backend/ohh-lens-speech-server/tests/test_buffer.py
git commit -m "feat: add speech server protocol and pcm buffer"
```

## Task 3: Add Session Orchestration And WebSocket Flow With A Fake Streaming Engine

**Files:**
- Create: `backend/ohh-lens-speech-server/app/funasr/models.py`
- Create: `backend/ohh-lens-speech-server/app/funasr/adapter.py`
- Create: `backend/ohh-lens-speech-server/app/core/session_manager.py`
- Create: `backend/ohh-lens-speech-server/app/api/ws.py`
- Modify: `backend/ohh-lens-speech-server/app/main.py`
- Create: `backend/ohh-lens-speech-server/tests/test_ws_flow.py`

- [ ] **Step 1: Write the failing WebSocket happy-path test**

```python
from fastapi.testclient import TestClient

from app.main import create_app


def test_ws_transcribe_emits_ready_partial_final_closed():
    client = TestClient(create_app())

    with client.websocket_connect("/ws/transcribe") as websocket:
        websocket.send_json({
            "type": "start",
            "session_id": "session-1",
            "sample_rate": 16000,
            "channels": 1,
            "sample_format": "pcm_s16le",
            "language": "auto",
        })
        ready = websocket.receive_json()
        assert ready["type"] == "ready"

        websocket.send_bytes(b"\x00\x01" * 4000)
        partial = websocket.receive_json()
        assert partial["type"] == "partial"
        assert partial["text"] == "partial text"

        websocket.send_json({"type": "stop"})
        final_event = websocket.receive_json()
        closed_event = websocket.receive_json()
        assert final_event["type"] == "final"
        assert final_event["text"] == "final text"
        assert closed_event["type"] == "closed"
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
cd /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server && pytest tests/test_ws_flow.py -v
```

Expected: FAIL with missing `/ws/transcribe` route or missing session manager

- [ ] **Step 3: Add fake adapter, session manager, and WebSocket loop**

```python
# backend/ohh-lens-speech-server/app/funasr/models.py
from dataclasses import dataclass


@dataclass
class StreamingResult:
    text: str
    is_final: bool
    start_ms: int = 0
    end_ms: int = 0
```

```python
# backend/ohh-lens-speech-server/app/funasr/adapter.py
from typing import Protocol

from app.funasr.models import StreamingResult


class StreamingAdapter(Protocol):
    def begin(self, session_id: str) -> None: ...
    def push_audio(self, session_id: str, chunk: bytes, is_final: bool) -> list[StreamingResult]: ...
    def end(self, session_id: str) -> None: ...
    def ready(self) -> bool: ...


class FakeStreamingAdapter:
    def begin(self, session_id: str) -> None:
        return None

    def push_audio(self, session_id: str, chunk: bytes, is_final: bool) -> list[StreamingResult]:
        if is_final:
            return [StreamingResult(text="final text", is_final=True)]
        return [StreamingResult(text="partial text", is_final=False)]

    def end(self, session_id: str) -> None:
        return None

    def ready(self) -> bool:
        return True
```

```python
# backend/ohh-lens-speech-server/app/core/session_manager.py
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
                events.append(event_payload(event_type, session_id, text=result.text, start_ms=result.start_ms, end_ms=result.end_ms))
        return events

    def stop_session(self, session_id: str) -> list[dict]:
        buffer = self.buffers[session_id]
        remainder = buffer.flush()
        events: list[dict] = []
        for result in self.adapter.push_audio(session_id, remainder, is_final=True):
            event_type = "final" if result.is_final else "partial"
            events.append(event_payload(event_type, session_id, text=result.text, start_ms=result.start_ms, end_ms=result.end_ms))
        self.adapter.end(session_id)
        self.buffers.pop(session_id, None)
        events.append(event_payload("closed", session_id))
        return events
```

```python
# backend/ohh-lens-speech-server/app/api/ws.py
from fastapi import APIRouter, WebSocket

from app.core.protocol import StartMessage, StopMessage
from app.core.session_manager import SessionManager


def build_ws_router(session_manager: SessionManager) -> APIRouter:
    router = APIRouter()

    @router.websocket("/ws/transcribe")
    async def transcribe_socket(websocket: WebSocket) -> None:
        await websocket.accept()
        session_id: str | None = None

        while True:
            message = await websocket.receive()
            if "text" in message and message["text"] is not None:
                payload = message["text"]
                if '"type":"start"' in payload or '"type": "start"' in payload:
                    start = StartMessage.model_validate_json(payload)
                    session_id = start.session_id
                    await websocket.send_json(session_manager.start_session(session_id))
                else:
                    StopMessage.model_validate_json(payload)
                    for event in session_manager.stop_session(session_id):
                        await websocket.send_json(event)
                    return
            elif "bytes" in message and message["bytes"] is not None:
                for event in session_manager.push_audio(session_id, message["bytes"]):
                    await websocket.send_json(event)
```

```python
# backend/ohh-lens-speech-server/app/main.py
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
```

- [ ] **Step 4: Run the focused WebSocket test to verify it passes**

Run:

```bash
cd /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server && pytest tests/test_ws_flow.py -v
```

Expected: PASS

- [ ] **Step 5: Commit the session-flow slice**

```bash
git add backend/ohh-lens-speech-server/app/funasr/models.py backend/ohh-lens-speech-server/app/funasr/adapter.py backend/ohh-lens-speech-server/app/core/session_manager.py backend/ohh-lens-speech-server/app/api/ws.py backend/ohh-lens-speech-server/app/main.py backend/ohh-lens-speech-server/tests/test_ws_flow.py
git commit -m "feat: add websocket transcription session flow"
```

## Task 4: Integrate The Real FunASR Adapter And Readiness Gating

**Files:**
- Modify: `backend/ohh-lens-speech-server/app/funasr/adapter.py`
- Modify: `backend/ohh-lens-speech-server/app/api/health.py`
- Modify: `backend/ohh-lens-speech-server/app/api/ws.py`
- Modify: `backend/ohh-lens-speech-server/app/main.py`
- Modify: `backend/ohh-lens-speech-server/tests/test_health.py`
- Modify: `backend/ohh-lens-speech-server/tests/test_ws_flow.py`

- [ ] **Step 1: Write the failing readiness test**

```python
from fastapi.testclient import TestClient

from app.main import create_app


def test_health_reports_backend_ready_when_adapter_is_ready():
    client = TestClient(create_app(adapter_ready=True))

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["backend_ready"] is True
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run:

```bash
cd /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server && pytest tests/test_health.py tests/test_ws_flow.py -v
```

Expected: FAIL because `create_app(adapter_ready=True)` is unsupported or readiness is hard-coded

- [ ] **Step 3: Replace the fake-only construction path with a real adapter boundary**

```python
# backend/ohh-lens-speech-server/app/funasr/adapter.py
import numpy as np
from funasr import AutoModel

from app.funasr.models import StreamingResult


class FunASRStreamingAdapter:
    def __init__(self, model_name: str = "paraformer-zh-streaming", language: str = "auto") -> None:
        self.model_name = model_name
        self.language = language
        self._model = None
        self._caches: dict[str, dict] = {}

    def load(self) -> None:
        if self._model is None:
            self._model = AutoModel(model=self.model_name, disable_update=True)

    def ready(self) -> bool:
        return self._model is not None

    def begin(self, session_id: str) -> None:
        self.load()
        self._caches[session_id] = {}

    def push_audio(self, session_id: str, chunk: bytes, is_final: bool) -> list[StreamingResult]:
        if not chunk:
            return []
        audio = np.frombuffer(chunk, dtype=np.int16).astype(np.float32) / 32768.0
        cache = self._caches[session_id]
        result = self._model.generate(input=audio, cache=cache, is_final=is_final, language=self.language)
        text = result[0].get("text", "").strip()
        if not text:
            return []
        return [StreamingResult(text=text, is_final=is_final)]

    def end(self, session_id: str) -> None:
        self._caches.pop(session_id, None)
```

```python
# backend/ohh-lens-speech-server/app/main.py
from fastapi import FastAPI

from app.api.health import build_health_router
from app.api.ws import build_ws_router
from app.core.config import get_settings
from app.core.session_manager import SessionManager
from app.funasr.adapter import FakeStreamingAdapter, FunASRStreamingAdapter


def create_app(adapter_ready: bool = False) -> FastAPI:
    settings = get_settings()
    adapter = FakeStreamingAdapter() if not adapter_ready else FunASRStreamingAdapter()
    if adapter_ready:
        adapter.load()
    session_manager = SessionManager(adapter=adapter)
    app = FastAPI(title="Ohh Lens Speech Server", version="0.1.0")
    app.include_router(build_health_router(settings, adapter))
    app.include_router(build_ws_router(session_manager, adapter))
    return app
```

Implementation notes for this task:

- Change `build_health_router(settings)` to `build_health_router(settings, adapter)` and set `backend_ready` from `adapter.ready()`.
- Change `build_ws_router(...)` to reject new sockets with an `error` event when `adapter.ready()` is false.
- Keep the fake adapter available for tests that should not load a real model.

- [ ] **Step 4: Run focused tests to verify they pass**

Run:

```bash
cd /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server && pytest tests/test_health.py tests/test_ws_flow.py -v
```

Expected: PASS

- [ ] **Step 5: Commit the real-adapter slice**

```bash
git add backend/ohh-lens-speech-server/app/funasr/adapter.py backend/ohh-lens-speech-server/app/api/health.py backend/ohh-lens-speech-server/app/api/ws.py backend/ohh-lens-speech-server/app/main.py backend/ohh-lens-speech-server/tests/test_health.py backend/ohh-lens-speech-server/tests/test_ws_flow.py
git commit -m "feat: integrate funasr streaming adapter"
```

## Task 5: Document Running, Testing, And Crash-Recovery Workflow

**Files:**
- Create: `backend/ohh-lens-speech-server/README.md`
- Modify: `docs/superpowers/plans/2026-06-25-ohh-lens-speech-server.md`

- [ ] **Step 1: Write the failing documentation expectation as a smoke checklist**

```text
README must include:
- how to create a virtual environment
- how to install dependencies
- how to run the server locally
- how to hit /health
- how to connect from Ohh Lens
- how to recover progress if execution is interrupted
```

- [ ] **Step 2: Add the README with exact run instructions**

```markdown
# Ohh Lens Speech Server

## Run locally

```bash
cd /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server
python3 -m venv .venv
source .venv/bin/activate
pip install -e .[dev]
uvicorn app.main:app --host 127.0.0.1 --port 8765 --reload
```

## Check health

```bash
curl http://127.0.0.1:8765/health
```

## Expected client contract

- WebSocket URL: `ws://127.0.0.1:8765/ws/transcribe`
- Audio format: `16000 Hz`, mono, `pcm_s16le`
- Client sends: `start`, binary chunks, `stop`
- Server emits: `ready`, `partial`, `final`, `error`, `closed`

## Recovery workflow

If implementation stops unexpectedly:

1. Open `docs/superpowers/plans/2026-06-25-ohh-lens-speech-server.md`
2. Find the task marked `[-]`
3. Run that task’s focused tests
4. Inspect `git status --short`
5. Resume from the first unchecked step in that task
```

- [ ] **Step 3: Update the plan progress section as execution proceeds**

For each completed task, edit these lines in this file:

```markdown
- [x] Task 1 complete: scaffold the backend project and health surface
- [-] Task 2 in progress: define protocol types and deterministic PCM buffering
```

Do not mark future tasks complete early. Always leave the current active task as `[-]` until its tests pass and commit is created.

- [ ] **Step 4: Run the full backend test suite**

Run:

```bash
cd /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server && pytest tests -v
```

Expected: PASS across health, protocol, buffer, and WebSocket tests

- [ ] **Step 5: Commit the docs and recovery slice**

```bash
git add backend/ohh-lens-speech-server/README.md docs/superpowers/plans/2026-06-25-ohh-lens-speech-server.md
git commit -m "docs: add speech server runbook and recovery flow"
```
