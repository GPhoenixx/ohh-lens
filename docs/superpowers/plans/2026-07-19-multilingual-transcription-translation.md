# Multilingual Transcription and Translation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Support the ASR language set end-to-end and translate any supported source language into any supported target language selected in the start-session message.

**Architecture:** Keep the existing WebSocket fields language and target_language as the shared contract. Define the supported language codes once in backend protocol validation and mirror the same list in the Swift UI. Pass source/target metadata into the per-session translation assembler and contextual translator; Qwen will render language-aware prompts and bilingual context while same-language sessions bypass translation.

**Tech Stack:** Python 3.11, Pydantic, FastAPI WebSockets, pytest, SwiftUI, Swift Package/Xcode tests.

## Global Constraints

- Supported codes: zh, en, yue, ar, de, fr, es, pt, id, it, ko, ru, th, vi, ja, tr, hi, ms, nl, sv, da, fi, pl, cs, fil, fa, el, hu, mk, ro.
- Preserve language=auto for ASR-only sessions.
- Create translation only when source and target are explicit, supported, and different.
- Preserve the existing bilingual context window and Qwen3 MLX enable_thinking=False behavior.
- Do not modify unrelated working-tree changes.

---

### Task 1: Establish backend language contract and tests

Files:
- Modify: backend/ohh-lens-speech-server/app/core/protocol.py
- Test: backend/ohh-lens-speech-server/tests/test_protocol.py

Interfaces:
- Consumes: WebSocket StartMessage payloads.
- Produces: SUPPORTED_LANGUAGE_CODES and normalized/validated language and target_language values.

- [ ] Step 1: Write failing validation tests

Add tests that construct StartMessage with language=ja and target_language=vi successfully; reject language=xx and target_language=xx; and preserve language=auto for ASR-only starts.

- [ ] Step 2: Run the protocol tests and verify the new assertions fail

Run: cd backend/ohh-lens-speech-server && ./.venv/bin/python -m pytest tests/test_protocol.py -v

Expected: unsupported-language tests fail because the current model accepts arbitrary strings.

- [ ] Step 3: Implement shared backend constants and validators

Add a frozenset of the 30 codes and Pydantic validators that lowercase values, allow auto only for language, and reject unsupported explicit source/target codes with clear messages.

- [ ] Step 4: Run protocol tests and verify they pass

Run the same command. Expected: all protocol tests pass.

### Task 2: Make translation routing and prompts multilingual

Files:
- Modify: backend/ohh-lens-speech-server/app/core/translation.py
- Modify: backend/ohh-lens-speech-server/app/core/live_translation.py
- Modify: backend/ohh-lens-speech-server/app/core/session_manager.py
- Test: backend/ohh-lens-speech-server/tests/test_translation.py
- Test: backend/ohh-lens-speech-server/tests/test_ws_flow.py

Interfaces:
- Consumes: validated StartMessage.language and .target_language.
- Produces: source/target-aware LocalEnglishVietnameseTranslator behavior and per-session translation bypass/routing.

- [ ] Step 1: Write failing multilingual prompt and session tests

Add tests asserting a Japanese-to-Vietnamese Qwen prompt contains Japanese, Vietnamese, the source text, and prior bilingual context; assert an English-to-English session creates no translation assembler; and assert a Japanese start is forwarded to the adapter.

- [ ] Step 2: Run focused tests and verify they fail

Run: ./.venv/bin/python -m pytest tests/test_translation.py tests/test_ws_flow.py -v

Expected: the prompt API rejects source/target metadata or still contains hard-coded English/Vietnamese behavior, and same-language routing is not yet covered.

- [ ] Step 3: Add language metadata to translator and assembler interfaces

Extend the translator constructor with source_language and target_language defaults, extend LiveTranslationAssembler with the same pair, and pass those fields from SessionManager.start_session().

- [ ] Step 4: Replace hard-coded Qwen labels with dynamic language names

Add a code-to-name mapping for the supported languages. Build prompts such as Translate NEW_TEXT from Japanese to Vietnamese, label context with Japanese and Vietnamese, and retain the existing strict Latin-script retry only when the target language uses the Latin script.

- [ ] Step 5: Bypass translation for same-language and ASR-only sessions

Change SessionManager.start_session() to create LiveTranslationAssembler only when both codes are explicit/supported and differ. Keep transcript streaming and adapter language forwarding unchanged.

- [ ] Step 6: Run focused tests and verify they pass

Run the focused command again. Expected: all translation, routing, prompt, and language-forwarding tests pass.

### Task 3: Expand Swift language selection and verify the socket contract

Files:
- Modify: Sources/OhhLensApp/Views/Shared/TranscriptWidgets.swift
- Test: Tests/OhhLensCoreTests/FunASRStreamingClientTests.swift

Interfaces:
- Consumes: the shared 30-code language list and existing LanguagePair bindings.
- Produces: UI selectors that can choose every ASR language and continue sending source/target codes in the existing start payload.

- [ ] Step 1: Add a test for representative multilingual start payloads

Extend the existing start-message test to cover language=ja and target_language=ar and assert both JSON fields are preserved.

- [ ] Step 2: Run the focused Swift test and verify the new assertion fails

Run the repository’s existing Swift test command for FunASRStreamingClientTests. Expected: the new test fails until the fixture/API coverage is updated.

- [ ] Step 3: Replace the four-entry picker list with the 30 supported languages

Update languageOptions with the exact backend code/name list, retaining the existing same target option and source/target binding behavior.

- [ ] Step 4: Run Swift tests and verify they pass

Run the focused Swift test, then the full Swift suite using the repository’s configured DEVELOPER_DIR, HOME, and CLANG_MODULE_CACHE_PATH command. Expected: all tests pass.

### Task 4: Update documentation and perform full verification

Files:
- Modify: backend/ohh-lens-speech-server/README.md

Interfaces:
- Consumes: the finalized language contract and prompt behavior.
- Produces: user-facing documentation for multilingual source/target selection.

- [ ] Step 1: Document supported languages and WebSocket fields

Explain that the app sends language and target_language on start, list the supported codes, and state that auto is ASR-only while equal source/target codes skip translation.

- [ ] Step 2: Run the full backend suite

Run: cd backend/ohh-lens-speech-server && ./.venv/bin/python -m pytest -q

Expected: all backend tests pass.

- [ ] Step 3: Review the final scoped diff and status

Run git diff over the listed multilingual files and git status from the repository root. Expected: only multilingual contract/routing/UI/docs changes appear in scope.
