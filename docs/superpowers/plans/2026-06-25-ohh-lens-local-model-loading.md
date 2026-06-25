# Ohh Lens Local Model Loading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the speech server load FunASR strictly from a local filesystem model path, with no remote fallback.

**Architecture:** Extend backend config with a resolved local model path, thread that into the real FunASR adapter, and surface the setup state through health plus README guidance. Keep tests fast by using injected fake adapters for behavior checks instead of loading a real model in the suite.

**Tech Stack:** Python 3.9, FastAPI, Pydantic, pytest, FunASR

---

## Progress Tracking

- [x] Task 1 complete: add strict local model path config and health visibility
- [-] Task 2 in progress: update the real FunASR adapter to require a local path
- [ ] Task 3 pending: document local-model setup and verify the backend suite

## File Structure

- Modify: `backend/ohh-lens-speech-server/app/core/config.py`
  Add env-backed local model path settings.
- Modify: `backend/ohh-lens-speech-server/app/api/health.py`
  Surface model-path setup state in health output.
- Modify: `backend/ohh-lens-speech-server/app/main.py`
  Pass the resolved config path into the real adapter.
- Modify: `backend/ohh-lens-speech-server/app/funasr/adapter.py`
  Enforce strict local-path loading for the real adapter.
- Modify: `backend/ohh-lens-speech-server/tests/test_health.py`
  Cover model-path visibility and readiness behavior.
- Modify: `backend/ohh-lens-speech-server/README.md`
  Add exact local-model setup instructions.

## Task 1: Add Strict Local Model Path Config And Health Visibility

**Files:**
- Modify: `backend/ohh-lens-speech-server/app/core/config.py`
- Modify: `backend/ohh-lens-speech-server/app/api/health.py`
- Modify: `backend/ohh-lens-speech-server/tests/test_health.py`

- [ ] **Step 1: Write the failing health/config test**
- [ ] **Step 2: Run the focused test to verify it fails**
- [ ] **Step 3: Add env-backed `funasr_model_path` config and expose it from `/health`**
- [ ] **Step 4: Run the focused test to verify it passes**
- [ ] **Step 5: Commit**

## Task 2: Require Local Path In The Real FunASR Adapter

**Files:**
- Modify: `backend/ohh-lens-speech-server/app/funasr/adapter.py`
- Modify: `backend/ohh-lens-speech-server/app/main.py`

- [ ] **Step 1: Write the failing adapter/readiness test or focused regression**
- [ ] **Step 2: Run the focused test to verify it fails**
- [ ] **Step 3: Update `FunASRStreamingAdapter` to accept and validate a local model path only**
- [ ] **Step 4: Run the focused tests to verify they pass**
- [ ] **Step 5: Commit**

## Task 3: Document Local-Model Setup And Verify The Backend Suite

**Files:**
- Modify: `backend/ohh-lens-speech-server/README.md`
- Modify: `docs/superpowers/plans/2026-06-25-ohh-lens-local-model-loading.md`

- [ ] **Step 1: Add README instructions for `FUNASR_MODEL_PATH` and default path behavior**
- [ ] **Step 2: Update progress markers in this plan**
- [ ] **Step 3: Run the full backend test suite**
- [ ] **Step 4: Commit**
