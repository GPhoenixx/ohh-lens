# Ohh Lens FunASR Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch the speech server from strict local-path FunASR loading to env-configurable name-based loading with `SenseVoice` on `mps` as the default runtime.

**Architecture:** Keep the existing FastAPI + adapter seam intact, but replace path-based adapter construction with runtime config for model name and device. Surface runtime state through `/health`, keep startup resilient when model load fails, and align the README with the real FunASR install workflow.

**Tech Stack:** Python 3.9, FastAPI, Pydantic, pytest, FunASR, torch, torchaudio

---

### Task 1: Replace Path-Based Runtime Config

**Files:**
- Modify: `backend/ohh-lens-speech-server/app/core/config.py`
- Modify: `backend/ohh-lens-speech-server/app/api/health.py`
- Test: `backend/ohh-lens-speech-server/tests/test_health.py`

- [ ] Add env-backed `FUNASR_MODEL_NAME` and `FUNASR_DEVICE` settings with defaults `iic/SenseVoiceSmall` and `mps`.
- [ ] Remove the `FUNASR_MODEL_PATH`-based health payload fields and replace them with `model` and `device`.
- [ ] Update health tests so the default payload and env override behavior reflect the new runtime config.

### Task 2: Rewire the Real FunASR Adapter

**Files:**
- Modify: `backend/ohh-lens-speech-server/app/funasr/adapter.py`
- Modify: `backend/ohh-lens-speech-server/app/main.py`
- Test: `backend/ohh-lens-speech-server/tests/test_health.py`

- [ ] Write or update a failing test that proves app startup constructs the real adapter with model name and device instead of a local path.
- [ ] Change `FunASRStreamingAdapter` to accept `model_name` and `device`, then call `AutoModel(model=<name>, device=<device>)`.
- [ ] Keep startup non-fatal when real model loading fails so `/health` can still report `backend_ready: false`.

### Task 3: Update the Backend Runbook

**Files:**
- Modify: `backend/ohh-lens-speech-server/README.md`

- [ ] Replace local-path-only instructions with the real FunASR install flow using `pip install torch torchaudio` and `pip install funasr`.
- [ ] Document the default `SenseVoice` + `mps` runtime and show env overrides for `FUNASR_MODEL_NAME` and `FUNASR_DEVICE`.
- [ ] Update troubleshooting so it checks runtime model/device configuration instead of a required filesystem path.

### Task 4: Verify the Corrected Runtime Slice

**Files:**
- Test: `backend/ohh-lens-speech-server/tests/test_health.py`
- Test: `backend/ohh-lens-speech-server/tests`

- [ ] Run the focused health tests first and confirm the runtime correction behaves as expected.
- [ ] Run the full backend test suite with the established `uv run --no-project ... pytest tests -v` command.
- [ ] Review `git status --short` and keep generated caches out of the final staged changes.
