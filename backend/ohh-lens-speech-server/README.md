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

## Multilingual sessions

The app sends the source language and translation language in the WebSocket
start message:

```json
{
  "type": "start",
  "language": "ja",
  "target_language": "vi"
}
```

Supported language codes are: `zh`, `en`, `yue`, `ar`, `de`, `fr`, `es`, `pt`,
`id`, `it`, `ko`, `ru`, `th`, `vi`, `ja`, `tr`, `hi`, `ms`, `nl`, `sv`, `da`,
`fi`, `pl`, `cs`, `fil`, `fa`, `el`, `hu`, `mk`, and `ro`.

`language="auto"` is supported for ASR-only sessions. Translation is skipped
when the source and target languages are the same or the target is `same`.
Otherwise Qwen receives the selected source/target language names and the
recent completed bilingual pairs as context.

Override with environment variables when needed:

- `FUNASR_MODEL_NAME=iic/SenseVoiceSmall`
- `FUNASR_DEVICE=mps`
- `FUNASR_HUB=ms` if you want to prefer ModelScope instead
- `TRANSLATION_MODEL_NAME=Helsinki-NLP/opus-mt-en-vi`
- `TRANSLATION_DEVICE=cpu`
- `TRANSLATION_SECONDS_CAP=6.0` maximum wait before emitting a translation block
- `TRANSLATION_MIN_SENTENCE_WORDS=8` minimum words before a punctuated sentence emits early
- `TRANSLATION_CONTEXT_PAIR_COUNT=2` completed bilingual pairs retained for Qwen context

For multilingual translation, set `TRANSLATION_MODEL_NAME=facebook/m2m100_418M`.
The backend automatically configures M2M100 for English input and Vietnamese output.

For context-aware English-to-Vietnamese translation, use Qwen:

```bash
export TRANSLATION_MODEL_NAME="Qwen/Qwen2.5-7B-Instruct"
export TRANSLATION_DEVICE="mps"
export TRANSLATION_CONTEXT_PAIR_COUNT=2
```

The backend gives Qwen the latest completed English/Vietnamese pairs as prompt
context and instructs it to return only the new Vietnamese translation. Qwen is
substantially larger than OPUS or M2M100, so its first download and responses
will require more memory and may add subtitle latency.

For Apple Silicon, prefer the quantized MLX version instead of the full
PyTorch checkpoint:

```bash
UV_CACHE_DIR="$PWD/.uv-cache-local" uv sync --extra mlx
export TRANSLATION_CONTEXT_PAIR_COUNT=2
```

On Apple Silicon, the backend automatically defaults to
`mlx-community/Qwen3-8B-4bit` when `TRANSLATION_MODEL_NAME` is unset. Qwen3 runs
with thinking disabled for low-latency translation while still following the
translation prompt and using the bilingual context.
Other platforms retain the `Helsinki-NLP/opus-mt-en-vi` default. Set
`TRANSLATION_MODEL_NAME` explicitly to override the platform default.

MLX-LM loads the 4-bit model locally and retains the same bilingual context
prompt. `TRANSLATION_DEVICE` is not used by this MLX path.

FunASR resolves the configured model through `AutoModel(...)`. If the model is not already present locally, FunASR may download it on first use.
If `FUNASR_HUB` is unset, the server defaults to `hub="hf"` for both the ASR and VAD model loads.

Live English-to-Vietnamese translation is enabled for sessions started with
`language="en"` and `target_language="vi"`. The backend restores punctuation
with FunASR's `ct-punc` model, then translates locally with
`Helsinki-NLP/opus-mt-en-vi` by default. The backend accumulates partial text
across ASR segments and emits a bilingual subtitle block when punctuation forms
a sentence of at least eight words, or after six seconds. Remaining buffered
text is translated when listening stops.

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
- `partial` while audio is still streaming, with a `segment_id`
- `final` after `stop`, with a `segment_id`
- `translation` after a buffered English sentence is punctuated and translated,
  with `source_text`, `translated_text`, and the original `segment_id`
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
