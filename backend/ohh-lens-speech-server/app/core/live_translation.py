from dataclasses import dataclass
import time
from typing import Callable, Protocol


class TranslatorProtocol(Protocol):
    def punctuate(self, text: str) -> str: ...

    def translate(self, text: str) -> str: ...


class ContextualTranslatorProtocol(TranslatorProtocol, Protocol):
    def translate_with_context(
        self,
        text: str,
        context: list[tuple[str, str]],
        source_language: str,
        target_language: str,
    ) -> str: ...


@dataclass
class LiveTranslationAssembler:
    translator: TranslatorProtocol
    seconds_cap: float = 6.0
    min_sentence_words: int = 8
    context_pair_count: int = 2
    source_language: str = "en"
    target_language: str = "vi"
    clock: Callable[[], float] = time.monotonic
    pending_source_text: str = ""
    pending_segment_id: str | None = None
    pending_started_at: float | None = None
    last_partial_text: str = ""
    last_partial_segment_id: str | None = None
    translation_index: int = 0
    completed_pairs: list[tuple[str, str]] | None = None

    def __post_init__(self) -> None:
        if self.completed_pairs is None:
            self.completed_pairs = []

    def push_partial_text(self, segment_id: str, text: str) -> list[dict[str, object]]:
        incoming = " ".join(text.split()).strip()
        if not incoming:
            return []

        if self.last_partial_segment_id not in (None, segment_id):
            self.last_partial_text = ""

        delta = self._partial_delta(incoming)
        self.last_partial_text = incoming
        self.last_partial_segment_id = segment_id
        if not delta:
            return []

        return self._push_candidate(segment_id, delta)

    def push_final_text(self, segment_id: str, text: str) -> list[dict[str, object]]:
        incoming = " ".join(text.split()).strip()
        if not incoming:
            return []

        if self.last_partial_segment_id == segment_id:
            incoming = self._partial_delta(incoming)
        self.last_partial_text = ""
        self.last_partial_segment_id = None
        if incoming:
            return self._push_candidate(segment_id, incoming)
        return []

    def _push_candidate(self, segment_id: str, incoming: str) -> list[dict[str, object]]:
        if self.pending_source_text == "":
            self.pending_started_at = self.clock()
        if self.pending_segment_id is None:
            # One translation can span several VAD/ASR segments. Preserve the
            # first ID so the emitted translation pair remains stable.
            self.pending_segment_id = segment_id
        self.pending_source_text = " ".join(
            part for part in (self.pending_source_text, incoming) if part
        ).strip()
        print(f"self.pending_source_text: {self.pending_source_text}")
        punctuated = self.translator.punctuate(self.pending_source_text)
        print(f"punctuated: {punctuated}")
        if self._should_flush(punctuated):
            return self.flush(punctuated=punctuated)
        return []

    def _partial_delta(self, incoming: str) -> str:
        previous = self.last_partial_text
        if not previous:
            return incoming
        if incoming == previous:
            return ""
        if incoming.startswith(previous):
            return incoming[len(previous) :].strip()
        if previous.startswith(incoming):
            return ""
        return incoming

    def flush(self, punctuated: str | None = None) -> list[dict[str, object]]:
        if not self.pending_source_text or self.pending_segment_id is None:
            return []

        source_text = self.pending_source_text
        segment_id = self.pending_segment_id
        self.translation_index += 1
        translation_id = f"{segment_id}-translation-{self.translation_index}"
        translation_input = punctuated if punctuated is not None else self.translator.punctuate(source_text)
        contextual_translate = getattr(self.translator, "translate_with_context", None)
        if callable(contextual_translate):
            print(f"contextual_translate: {contextual_translate}")
            print(f"self.completed_pairs: {self.completed_pairs}")
            print(f"self.completed_pairs[-self.context_pair_count :]: {self.completed_pairs[-self.context_pair_count :]}")
            translated_text = contextual_translate(
                translation_input,
                self.completed_pairs[-self.context_pair_count :] if self.context_pair_count else [],
                self.source_language,
                self.target_language,
            )
        else:
            translated_text = self.translator.translate(translation_input)
        if not translated_text.strip():
            self.pending_source_text = ""
            self.pending_segment_id = None
            self.pending_started_at = None
            return []
        self.completed_pairs.append((source_text, translated_text))
        if self.context_pair_count:
            self.completed_pairs = self.completed_pairs[-self.context_pair_count :]
        else:
            self.completed_pairs = []
        self.pending_source_text = ""
        self.pending_segment_id = None
        self.pending_started_at = None
        return [
            {
                "type": "translation",
                "segment_id": segment_id,
                "translation_id": translation_id,
                "source_text": source_text,
                "translated_text": translated_text,
            }
        ]

    def _should_flush(self, punctuated: str) -> bool:
        print(f"punctuated: {punctuated}")
        if self.pending_started_at is None:
            return False
        if self.clock() - self.pending_started_at >= self.seconds_cap:
            return True

        return len(punctuated.split()) >= self.min_sentence_words and punctuated.rstrip().endswith(
            (".", "?", "!")
        )
