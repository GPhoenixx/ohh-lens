# Ohh Lens Local Model Loading Design

## Summary

Update the speech server so FunASR loads strictly from local filesystem paths instead of resolving a remote model name. The backend must not silently download models or fall back to hub-based resolution.

## Goals

- Load the main FunASR ASR model only from a local path.
- Support a clear default local path plus env-var overrides.
- Fail readiness cleanly when the local model path is missing or invalid.
- Make the local-model requirement explicit in backend health output and docs.

## Non-Goals

- Reintroducing remote fallback or automatic downloads.
- Adding translation or extra model types in this slice.
- Bundling the model into the repo.

## Behavior

The backend uses a strict local model path policy:

- It reads the ASR model location from config.
- Config can come from:
  - a default local path
  - an explicit `FUNASR_MODEL_PATH` env var override
- If the resolved path does not exist, readiness stays false.
- If `AutoModel` fails to load from that path, readiness stays false.
- The backend must not pass a remote model name string as the primary loading path.

## Configuration Shape

At minimum add:

- `funasr_model_path`

Suggested sources:

- default path under the user’s local model directory
- override via `FUNASR_MODEL_PATH`

## Adapter Rules

`FunASRStreamingAdapter` should:

- accept a local model path at initialization
- validate the path before calling `AutoModel`
- call `AutoModel(model=<local path>)`
- expose a useful error message for missing path vs load failure

## Health Rules

The backend health response should make the setup state clearer by exposing whether a model path is configured and/or resolved. This can be a simple field such as:

- `model_path`
- or `model_path_configured`

The backend still reports `backend_ready=false` if the adapter is not actually loaded.

## README Changes

The runbook should show:

- where to place the local model
- which env var to set
- an example launch command
- how to diagnose a missing model path from `/health`

## Testing

Add or update tests for:

- missing local model path leaves backend not ready
- explicit configured path is surfaced correctly
- readiness path still works when a ready adapter is injected

## Implementation Note

This slice should keep the existing adapter seam used by tests. Production startup should use the strict local-path adapter, while tests can continue to inject fake adapters so the suite remains fast and deterministic.
