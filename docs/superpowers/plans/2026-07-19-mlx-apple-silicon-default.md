# MLX Apple Silicon Default Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Select the quantized MLX translation model by default on Apple Silicon while keeping MLX optional elsewhere and honoring explicit model configuration.

**Architecture:** Resolve the translation model default in `app/core/config.py`, where environment variables and host platform information are already combined. Keep `LocalEnglishVietnameseTranslator` platform-agnostic; it will receive the resolved model name as it does today. Update the MLX error text and README to match the optional dependency behavior, and add isolated settings tests by patching `platform.machine` and environment variables.

**Tech Stack:** Python 3.11, Pydantic settings model, pytest, uv optional dependency groups.

## Global Constraints

- Keep `mlx-lm` in the optional `mlx` dependency group; do not make it a base dependency.
- On Apple Silicon with no override, default to `mlx-community/Qwen2.5-7B-Instruct-4bit`.
- An explicit `TRANSLATION_MODEL_NAME` must always take precedence.
- Non-Apple-Silicon with no override must retain `Helsinki-NLP/opus-mt-en-vi`.
- Do not modify unrelated working-tree changes.

---

### Task 1: Add failing platform-aware settings tests

**Files:**
- Create: `backend/ohh-lens-speech-server/tests/test_config.py`

**Interfaces:**
- Consumes: `app.core.config.get_settings()` and the module’s platform detection.
- Produces: regression coverage for the three model-resolution cases.

- [x] **Step 1: Write the failing tests**

```python
import platform

from app.core.config import get_settings


def test_apple_silicon_defaults_to_mlx_model(monkeypatch):
    monkeypatch.delenv("TRANSLATION_MODEL_NAME", raising=False)
    monkeypatch.setattr(platform, "machine", lambda: "arm64")

    assert get_settings().translation_model_name == (
        "mlx-community/Qwen2.5-7B-Instruct-4bit"
    )


def test_non_apple_silicon_keeps_huggingface_default(monkeypatch):
    monkeypatch.delenv("TRANSLATION_MODEL_NAME", raising=False)
    monkeypatch.setattr(platform, "machine", lambda: "x86_64")

    assert get_settings().translation_model_name == "Helsinki-NLP/opus-mt-en-vi"


def test_explicit_translation_model_overrides_platform_default(monkeypatch):
    monkeypatch.setenv("TRANSLATION_MODEL_NAME", "Qwen/Qwen2.5-7B-Instruct")
    monkeypatch.setattr(platform, "machine", lambda: "arm64")

    assert get_settings().translation_model_name == "Qwen/Qwen2.5-7B-Instruct"
```

- [x] **Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server
pytest tests/test_config.py -v
```

Expected: the Apple Silicon test fails because the current default remains `Helsinki-NLP/opus-mt-en-vi`.

### Task 2: Implement platform-aware model resolution

**Files:**
- Modify: `backend/ohh-lens-speech-server/app/core/config.py`
- Modify: `backend/ohh-lens-speech-server/app/core/translation.py`

**Interfaces:**
- Consumes: `platform.machine()`, `TRANSLATION_MODEL_NAME`, and the existing `get_settings()` return type.
- Produces: `get_settings()` resolving the correct default and an MLX error message that points to `uv sync --extra mlx`.

- [x] **Step 1: Add explicit platform/default constants and helper**

In `app/core/config.py`, import `platform` and add:

```python
DEFAULT_TRANSLATION_MODEL = "Helsinki-NLP/opus-mt-en-vi"
APPLE_SILICON_TRANSLATION_MODEL = "mlx-community/Qwen2.5-7B-Instruct-4bit"


def _default_translation_model() -> str:
    return (
        APPLE_SILICON_TRANSLATION_MODEL
        if platform.machine().lower() in {"arm64", "aarch64"}
        else DEFAULT_TRANSLATION_MODEL
    )
```

Use `_default_translation_model()` as the fallback in `get_settings()` while keeping `os.getenv("TRANSLATION_MODEL_NAME", ...)` so explicit configuration wins.

- [x] **Step 2: Update the MLX missing-dependency message**

In `_load_mlx_translation_model()`, retain the optional dependency guidance and ensure it says:

```python
"MLX translation requires the optional 'mlx' dependency. "
"Run: uv sync --extra mlx"
```

- [x] **Step 3: Run the focused tests**

Run:

```bash
cd /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server
pytest tests/test_config.py tests/test_translation.py -v
```

Expected: all settings and translation tests pass without importing or downloading MLX models.

### Task 3: Align documentation and verify the backend suite

**Files:**
- Modify: `backend/ohh-lens-speech-server/README.md`

**Interfaces:**
- Consumes: the resolved model behavior and optional `mlx` dependency group.
- Produces: install/run instructions that accurately describe Apple Silicon auto-selection and explicit overrides.

- [x] **Step 1: Update README instructions**

Document that Apple Silicon defaults to `mlx-community/Qwen2.5-7B-Instruct-4bit` when `TRANSLATION_MODEL_NAME` is unset, while other platforms retain Helsinki-NLP. Keep the MLX installation command as:

```bash
UV_CACHE_DIR="$PWD/.uv-cache-local" uv sync --extra mlx
```

State that setting `TRANSLATION_MODEL_NAME` overrides the automatic default.

- [x] **Step 2: Run the full backend tests**

Run:

```bash
cd /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server
pytest -q
```

Expected: all backend tests pass.

- [x] **Step 3: Review the final diff**

Run:

```bash
cd /Users/steve/dev/personal/ohh-lens
git diff -- backend/ohh-lens-speech-server/app/core/config.py backend/ohh-lens-speech-server/app/core/translation.py backend/ohh-lens-speech-server/README.md backend/ohh-lens-speech-server/tests/test_config.py
```

Expected: only the platform-aware default, focused error/documentation wording, and new tests are present; no unrelated files are changed by this task.
