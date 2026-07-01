# Ohh Lens Speech Server

Local FastAPI server for incremental speech transcription during Ohh Lens development.

## Requirements

- Python 3.11.x
- A shell with `uv` and `curl`
- Apple Silicon is the intended first target for the default `mps` runtime

Current note:

- The backend is pinned to Python `3.11`.
- Use `uv` for environment creation and dependency sync so the local environment matches the lockfile.
- Model downloads use HuggingFace by default.
- Qwen ASR support is included in the base backend dependencies through `qwen-asr`.

## Runtime defaults

- Model: `iic/SenseVoiceSmall`
- Device: `mps`
- Hub: `hf`

This is the English-first default runtime for the current backend slice.

Override with environment variables when needed:

- `FUNASR_MODEL_NAME=iic/SenseVoiceSmall`
- `FUNASR_DEVICE=mps`
- `FUNASR_HUB=ms` if you want to prefer ModelScope instead

FunASR resolves the configured model through `AutoModel(...)`. If the model is not already present locally, FunASR may download it on first use.
If `FUNASR_HUB` is unset, the server defaults to `hub="hf"` for both the ASR and VAD model loads.

## Run locally

```bash
cd /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server
UV_CACHE_DIR="$PWD/.uv-cache-local" uv venv --python 3.11 .venv
source .venv/bin/activate
UV_CACHE_DIR="$PWD/.uv-cache-local" uv sync --extra dev
export FUNASR_MODEL_NAME="iic/SenseVoiceSmall"
export FUNASR_DEVICE="mps"
export FUNASR_HUB="hf"
export MODELSCOPE_CACHE="$PWD/.modelscope-cache"
uvicorn app.main:app --host 127.0.0.1 --port 8765 --reload
```

What this does:

- creates an isolated virtual environment in `.venv`
- installs the runtime and dev dependencies from `pyproject.toml` and `uv.lock`
- configures the default `SenseVoice` + `mps` runtime explicitly
- keeps model downloads on the default HuggingFace path
- stores downloaded FunASR model assets in a project-local cache
- starts the FastAPI server on `127.0.0.1:8765`

Example override:

```bash
export FUNASR_MODEL_NAME="iic/SenseVoiceSmall"
export FUNASR_DEVICE="cpu"
export FUNASR_HUB="ms"
```

Use `cpu` if you need a fallback on a machine where `mps` is unavailable. Set `FUNASR_HUB="ms"` if you want ModelScope instead of the default HuggingFace source.

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
  "model": "iic/SenseVoiceSmall",
  "device": "mps"
}
```

If `backend_ready` is `false`, the server is up but the FunASR adapter did not load successfully.

## Run tests

```bash
cd /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server
source .venv/bin/activate
uv run pytest tests -v
```

If you are only validating the protocol layer in an isolated shell, use:

```bash
UV_CACHE_DIR=/Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server/.uv-cache-local \
uv run pytest tests -v
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

1. Open `/Users/steve/dev/personal/ohh-lens/docs/superpowers/plans/2026-06-26-ohh-lens-funasr-runtime.md`.
2. Find the task marked `[-]`.
3. Run that task's focused tests before editing anything else.
4. Inspect `git status --short` to see what was already changed.
5. Resume from the first unchecked step in the active task.

If the server crashes during local development:

1. Restart the virtual environment with `source .venv/bin/activate`.
2. Confirm `FUNASR_MODEL_NAME` and `FUNASR_DEVICE` still match the runtime you intend to use.
3. Re-run `uvicorn app.main:app --host 127.0.0.1 --port 8765 --reload`.
4. Confirm recovery with `curl http://127.0.0.1:8765/health`.
5. If `backend_ready` is still `false`, verify that `model` and `device` in `/health` match the runtime you expect before reinstalling anything.
6. If dependency sync fails, rerun `UV_CACHE_DIR="$PWD/.uv-cache-local" uv sync --extra dev` before changing Python versions.
