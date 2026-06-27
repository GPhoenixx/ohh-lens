# Ohh Lens FunASR Runtime Design

## Summary

Update the speech server to use FunASR the way you described: install runtime dependencies such as `torch`, `torchaudio`, and `funasr`, then load models by supported FunASR model name through `AutoModel(...)`. The backend should default to `SenseVoice` on `mps`, with English-first usage, while keeping model name and device configurable through environment variables.

## Goals

- Default the backend to `SenseVoice` on Apple Silicon `mps`.
- Use FunASR-supported model names instead of strict local filesystem model paths.
- Keep model name and device configurable through environment variables.
- Reflect model/device runtime state clearly in `/health`.
- Update the runbook so installation and runtime behavior match the real FunASR workflow.

## Non-Goals

- CUDA-first deployment.
- Strict local-model-only loading.
- Per-session model switching.
- Translation in this slice.

## Runtime Defaults

- model name: `iic/SenseVoiceSmall`
- device: `mps`

These defaults should be overridable through:

- `FUNASR_MODEL_NAME`
- `FUNASR_DEVICE`

## Adapter Rules

The real adapter should:

- call `AutoModel(model=<configured model name>, device=<configured device>)`
- keep the existing test seam so fake adapters can still be injected
- surface readiness through successful model load

## Health Rules

The health response should expose:

- `model`
- `device`
- `backend_ready`

If the adapter fails to load, the backend should still start and report `backend_ready=false`.

## README Rules

The backend runbook must show:

- `pip install torch torchaudio`
- `pip install funasr`
- default model/device behavior
- example env overrides for `FUNASR_MODEL_NAME` and `FUNASR_DEVICE`
- that `SenseVoice` is the default English-first runtime

## Implementation Note

This slice supersedes the earlier strict local-model-loading assumption. The adapter seam and health diagnostics remain useful, but model resolution should now follow supported FunASR name-based loading instead of a required local model path.
