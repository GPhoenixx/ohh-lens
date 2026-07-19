# Multilingual Transcription and Translation Design

## Goal

Support the ASR language set across the app and backend, and use the start-session `language` and `target_language` fields to produce contextual translation for any supported source/target pair.

## Supported languages

The shared language-code contract is:

`zh`, `en`, `yue`, `ar`, `de`, `fr`, `es`, `pt`, `id`, `it`, `ko`, `ru`, `th`, `vi`, `ja`, `tr`, `hi`, `ms`, `nl`, `sv`, `da`, `fi`, `pl`, `cs`, `fil`, `fa`, `el`, `hu`, `mk`, `ro`.

The backend validates both source and target codes against this set. The app exposes the same set in its language pickers. The existing `auto` source value remains accepted for ASR-only sessions, but translation requires an explicit supported source code.

## Socket and session behavior

The existing start message remains the transport contract:

    {"type":"start","language":"ja","target_language":"vi"}

The backend forwards `language` to FunASR. A translation assembler is created when source and target are different and both are supported. When source and target are equal, or the target is `same`, transcript events continue without translation events.

## Translation behavior

The local translator receives `source_language` and `target_language` for each session. Qwen prompts will use language names/codes dynamically instead of hard-coded English/Vietnamese labels. Completed context pairs retain their source and target text and are presented using the active language pair, preserving the existing context-window behavior.

Qwen3 MLX remains the Apple Silicon default and continues to run with thinking disabled for low-latency translation. Existing non-Qwen translation models retain their current behavior; the multilingual routing primarily targets the Qwen contextual path.

## Errors and compatibility

Unsupported explicit language codes produce a validation error at session start and close the socket. Missing/`auto` source language is valid for transcription but does not create a translation assembler. Existing clients that omit `target_language` retain the backend default and existing ASR behavior.

## Testing

Add backend tests for supported-code validation, same-language bypass, forwarding non-English source hints, and source/target-aware Qwen prompts/context. Add Swift tests for the complete language picker codes and start-message round trips. Run the full Python backend suite and Swift test suite.
