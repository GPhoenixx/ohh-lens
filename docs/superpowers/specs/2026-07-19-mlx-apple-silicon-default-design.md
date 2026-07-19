# MLX Apple Silicon Default Design

## Goal

Make the speech backend use the quantized MLX translation path by default on Apple Silicon, while keeping MLX optional for other platforms and preserving explicit environment configuration.

## Decisions

- Keep `mlx-lm` in the optional `mlx` dependency group. Non-Apple-Silicon installations should not install it by default.
- Detect Apple Silicon from the running Python platform/architecture in the settings layer.
- On Apple Silicon, use `mlx-community/Qwen2.5-7B-Instruct-4bit` as the default translation model.
- An explicit `TRANSLATION_MODEL_NAME` always takes precedence, so users can select OPUS, M2M100, PyTorch Qwen, or another supported model.
- Keep `TRANSLATION_DEVICE` behavior unchanged. The MLX path does not use that setting.
- Update the MLX dependency error and README to describe the automatic Apple Silicon default and the optional install command.

## Architecture and data flow

`get_settings()` will resolve the translation model default after inspecting the host platform. It will use the existing environment variable when present; otherwise it will select the MLX model only when the host is Apple Silicon and retain the existing Helsinki-NLP default everywhere else. The resolved setting continues through `main.py` into `LocalEnglishVietnameseTranslator`, so model selection remains centralized and the translator needs no platform-detection logic.

## Testing

Add focused settings tests covering:

1. Apple Silicon with no model environment variable selects the MLX model.
2. Non-Apple-Silicon with no model environment variable retains the Helsinki-NLP model.
3. An explicit `TRANSLATION_MODEL_NAME` overrides the platform default.

Tests will patch the platform-detection input and environment variables without requiring MLX or downloading any model. Existing backend translation tests should continue to validate the MLX code path through its current fakes.

## Scope and non-goals

This change does not make MLX a base dependency, change the translation algorithm, force MLX when an explicit model is configured, alter FunASR selection, or modify unrelated application/backend work already present in the working tree.
