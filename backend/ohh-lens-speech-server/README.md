# Ohh Lens Speech Server

Local FastAPI server for incremental speech transcription during Ohh Lens development.

## Requirements

- Python 3.9.x
- A shell with `python3`, `pip`, and `curl`

Current note:

- FunASR currently pulls a transitive dependency chain that does not install cleanly on Python `3.11` in this project setup.
- Use Python `3.9` for the real backend environment until the upstream dependency chain is updated.
- The real adapter now loads strictly from a local filesystem path. It will not fall back to remote model resolution.

## Local model setup

Default local model path:

- `~/.ohh-lens/models/funasr`

Override with an environment variable:

- `FUNASR_MODEL_PATH=/absolute/path/to/your/local/funasr-model`

The backend expects that path to already exist on disk before startup. If it is missing or invalid, `/health` will report `backend_ready: false`.

## Run locally

```bash
cd /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server
python3 -m venv .venv
source .venv/bin/activate
export FUNASR_MODEL_PATH="$HOME/.ohh-lens/models/funasr"
pip install -e .[dev]
uvicorn app.main:app --host 127.0.0.1 --port 8765 --reload
```

What this does:

- creates an isolated virtual environment in `.venv`
- installs the app plus test dependencies in editable mode
- starts the FastAPI server on `127.0.0.1:8765`

## Check health

```bash
curl http://127.0.0.1:8765/health
```

Expected shape:

```json
{
  "status": "ok",
  "service": "ohh-lens-speech-server",
  "sample_rate": 16000,
  "channels": 1,
  "sample_format": "pcm_s16le",
  "backend_ready": true,
  "model": "funasr-streaming",
  "model_path": "/Users/you/.ohh-lens/models/funasr",
  "model_path_configured": true
}
```

If `backend_ready` is `false`, the server is up but the FunASR adapter did not load successfully.

## Run tests

```bash
cd /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server
source .venv/bin/activate
pytest tests -v
```

If you are only validating the protocol layer on a machine that already has Python `3.11`, use the fallback command we verified in development:

```bash
HOME=/Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server/.home \
UV_CACHE_DIR=/Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server/.uv-cache-local \
PYTHONPATH=/Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server \
uv run --no-project --with fastapi --with 'uvicorn[standard]' --with pydantic --with numpy --with pytest --with pytest-asyncio --with httpx python -m pytest tests -v
```

## Connect from Ohh Lens

Use these values from the macOS app:

- WebSocket URL: `ws://127.0.0.1:8765/ws/transcribe`
- Audio format: `16000 Hz`
- Channels: `1`
- Sample format: `pcm_s16le`

Client message flow:

1. Send a JSON `start` message with `session_id`, `sample_rate`, `channels`, `sample_format`, and `language`.
2. Send binary PCM audio chunks.
3. Send a JSON `stop` message when the utterance is complete.

Server event flow:

- `ready` after a valid `start`
- `partial` while audio is still streaming
- `final` after `stop`
- `error` if validation or audio processing fails
- `closed` when the session shuts down cleanly

## Recovery workflow

If execution stops unexpectedly, resume from the task plan instead of guessing:

1. Open `/Users/steve/dev/personal/ohh-lens/docs/superpowers/plans/2026-06-25-ohh-lens-speech-server.md`.
2. Find the task marked `[-]`.
3. Run that task's focused tests before editing anything else.
4. Inspect `git status --short` to see what was already changed.
5. Resume from the first unchecked step in the active task.

If the server crashes during local development:

1. Restart the virtual environment with `source .venv/bin/activate`.
2. Confirm `FUNASR_MODEL_PATH` still points at the expected local model directory.
3. Re-run `uvicorn app.main:app --host 127.0.0.1 --port 8765 --reload`.
4. Confirm recovery with `curl http://127.0.0.1:8765/health`.
5. If `backend_ready` is still `false`, verify that `model_path` in `/health` matches the real directory on disk before reinstalling anything.
6. If install fails on Python `3.11`, switch to Python `3.9` for the real backend environment instead of retrying the same interpreter.
