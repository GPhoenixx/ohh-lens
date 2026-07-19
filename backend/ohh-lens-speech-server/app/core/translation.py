import logging
import time
import unicodedata

from funasr import AutoModel


logger = logging.getLogger(__name__)


LANGUAGE_NAMES = {
    "zh": "Chinese", "en": "English", "yue": "Cantonese", "ar": "Arabic",
    "de": "German", "fr": "French", "es": "Spanish", "pt": "Portuguese",
    "id": "Indonesian", "it": "Italian", "ko": "Korean", "ru": "Russian",
    "th": "Thai", "vi": "Vietnamese", "ja": "Japanese", "tr": "Turkish",
    "hi": "Hindi", "ms": "Malay", "nl": "Dutch", "sv": "Swedish",
    "da": "Danish", "fi": "Finnish", "pl": "Polish", "cs": "Czech",
    "fil": "Filipino", "fa": "Persian", "el": "Greek", "hu": "Hungarian",
    "mk": "Macedonian", "ro": "Romanian",
}

LATIN_SCRIPT_LANGUAGES = frozenset(
    {"en", "de", "fr", "es", "pt", "id", "it", "vi", "tr", "ms", "nl", "sv", "da", "fi", "pl", "cs", "fil", "hu", "ro"}
)


class LocalEnglishVietnameseTranslator:
    """Local English -> Vietnamese translation with backend punctuation."""

    def __init__(
        self,
        model_name: str = "Helsinki-NLP/opus-mt-en-vi",
        punctuation_model_name: str = "ct-punc",
        device: str = "cpu",
        hub: str = "hf",
        source_language: str = "en",
        target_language: str = "vi",
    ) -> None:
        self.model_name = model_name
        self.punctuation_model_name = punctuation_model_name
        self.device = device
        self.hub = hub
        self.source_language = source_language.lower()
        self.target_language = target_language.lower()
        self._tokenizer = None
        self._translation_model = None
        self._punctuation_model = None
        self._mlx_generate = None
        self._mlx_sampler = None

    def load(self) -> None:
        """Load the configured translation model before the first translation."""
        self._load_translation_model()

    def punctuate(self, text: str) -> str:
        self._load_punctuation_model()
        result = self._punctuation_model.generate(input=text)
        value = result[0].get("text", "") if result else ""
        return str(value).strip() or text

    def translate(self, text: str) -> str:
        if self._uses_qwen or self._uses_mlx:
            return self.translate_with_context(text, [])

        self._load_translation_model()
        if self._uses_m2m100:
            self._tokenizer.src_lang = self.source_language
        inputs = self._tokenizer(text, return_tensors="pt")
        inputs = {key: value.to(self._translation_model.device) for key, value in inputs.items()}
        generation_kwargs = {"max_new_tokens": 128}
        if self._uses_m2m100:
            generation_kwargs["forced_bos_token_id"] = self._tokenizer.get_lang_id(
                self.target_language
            )
        generated = self._translation_model.generate(**inputs, **generation_kwargs)
        return self._tokenizer.batch_decode(generated, skip_special_tokens=True)[0].strip()

    def translate_with_context(
        self,
        text: str,
        context: list[tuple[str, str]],
        source_language: str | None = None,
        target_language: str | None = None,
    ) -> str:
        source_language = source_language or self.source_language
        target_language = target_language or self.target_language
        if self._uses_mlx:
            return self._translate_with_mlx(text, context, source_language, target_language)
        if not self._uses_qwen:
            return self.translate(text)

        started_at = time.monotonic()
        logger.info(
            "Qwen translation started model=%s device=%s context_pairs=%d input_chars=%d",
            self.model_name,
            self.device,
            len(context),
            len(text),
        )
        try:
            self._load_translation_model()
            messages = self._translation_messages(text, context, source_language, target_language)
            inputs = self._tokenizer.apply_chat_template(
                messages,
                add_generation_prompt=True,
                tokenize=True,
                return_dict=True,
                return_tensors="pt",
            ).to(self._translation_model.device)
            self._configure_deterministic_qwen_generation()
            generated = self._translation_model.generate(
                **inputs,
                do_sample=False,
                max_new_tokens=128,
            )
            output_ids = generated[0][len(inputs["input_ids"][0]) :]
            translated = self._tokenizer.decode(output_ids, skip_special_tokens=True).strip()
        except Exception:
            logger.exception(
                "Qwen translation failed model=%s device=%s context_pairs=%d",
                self.model_name,
                self.device,
                len(context),
            )
            raise

        logger.info(
            "Qwen translation finished model=%s elapsed_seconds=%.2f output_chars=%d",
            self.model_name,
            time.monotonic() - started_at,
            len(translated),
        )
        return translated

    def _translate_with_mlx(
        self,
        text: str,
        context: list[tuple[str, str]],
        source_language: str,
        target_language: str,
    ) -> str:
        started_at = time.monotonic()
        logger.info(
            "MLX translation started model=%s context_pairs=%d input_chars=%d",
            self.model_name,
            len(context),
            len(text),
        )
        try:
            self._load_translation_model()
            translated = self._generate_mlx_translation(
                self._translation_messages(
                    text, context, source_language, target_language
                )
            )
            if target_language in LATIN_SCRIPT_LANGUAGES and not self._uses_latin_script(translated):
                logger.warning(
                    "MLX translation rejected non-Latin output model=%s; retrying",
                    self.model_name,
                )
                translated = self._generate_mlx_translation(
                    self._translation_messages(
                        text, context, source_language, target_language, strict=True
                    )
                )
            if target_language in LATIN_SCRIPT_LANGUAGES and not self._uses_latin_script(translated):
                logger.warning(
                    "MLX translation rejected repeated non-Latin output model=%s",
                    self.model_name,
                )
                return ""
        except Exception:
            logger.exception(
                "MLX translation failed model=%s context_pairs=%d",
                self.model_name,
                len(context),
            )
            raise

        logger.info(
            "MLX translation finished model=%s elapsed_seconds=%.2f output_chars=%d",
            self.model_name,
            time.monotonic() - started_at,
            len(translated),
        )
        return translated

    @property
    def _uses_m2m100(self) -> bool:
        return self.model_name.lower().startswith("facebook/m2m100_")

    @property
    def _uses_qwen(self) -> bool:
        return self.model_name.lower().startswith("qwen/")

    @property
    def _uses_mlx(self) -> bool:
        return self.model_name.lower().startswith("mlx-community/")

    @property
    def _uses_qwen3_mlx(self) -> bool:
        return self.model_name.lower().startswith("mlx-community/qwen3")

    def _qwen_translation_prompt(
        self,
        text: str,
        context: list[tuple[str, str]],
        source_language: str | None = None,
        target_language: str | None = None,
    ) -> str:
        source_language = source_language or self.source_language
        target_language = target_language or self.target_language
        source_name = LANGUAGE_NAMES.get(source_language, source_language)
        target_name = LANGUAGE_NAMES.get(target_language, target_language)
        context_lines = [
            f"{source_name}: {source_text}\n{target_name}: {target_text}"
            for source_text, target_text in context
        ]
        context_text = "\n\n".join(context_lines) or "(none)"
        return f"CONTEXT\n{context_text}\n\nNEW_TEXT\n{text}"

    def _generate_mlx_translation(self, messages: list[dict[str, str]]) -> str:
        template_kwargs = {"add_generation_prompt": True}
        if self._uses_qwen3_mlx:
            template_kwargs["enable_thinking"] = False
        prompt = self._tokenizer.apply_chat_template(messages, **template_kwargs)
        return self._mlx_generate(
            model=self._translation_model,
            tokenizer=self._tokenizer,
            prompt=prompt,
            max_tokens=128,
            sampler=self._mlx_sampler,
            verbose=False,
        ).strip()

    def _translation_messages(
        self,
        text: str,
        context: list[tuple[str, str]],
        source_language: str | None = None,
        target_language: str | None = None,
        strict: bool = False,
    ) -> list[dict[str, str]]:
        source_language = source_language or self.source_language
        target_language = target_language or self.target_language
        source_name = LANGUAGE_NAMES.get(source_language, source_language)
        target_name = LANGUAGE_NAMES.get(target_language, target_language)
        system_text = (
            f"Translate NEW_TEXT from {source_name} into natural {target_name}. Use CONTEXT only "
            "to resolve references and terminology. Return only the translation. "
            "Do not explain or repeat the context. Preserve the meaning, tone, and names."
        )
        if strict and self.target_language in LATIN_SCRIPT_LANGUAGES:
            system_text += " Never output a non-Latin script."
        return [
            {"role": "system", "content": system_text},
            {
                "role": "user",
                "content": self._qwen_translation_prompt(
                    text, context, source_language, target_language
                ),
            },
        ]

    @staticmethod
    def _uses_latin_script(text: str) -> bool:
        if not text.strip():
            return False
        return all(
            not character.isalpha() or "LATIN" in unicodedata.name(character, "")
            for character in text
        )

    def _configure_deterministic_qwen_generation(self) -> None:
        generation_config = getattr(self._translation_model, "generation_config", None)
        if generation_config is None:
            return

        generation_config.do_sample = False
        generation_config.temperature = None
        generation_config.top_p = None
        generation_config.top_k = None

    def _translation_model_load_kwargs(self) -> dict[str, object]:
        if not self._uses_qwen:
            return {}

        if self.device.startswith("mps"):
            import torch

            return {"torch_dtype": torch.float16}
        return {"torch_dtype": "auto"}

    def _load_punctuation_model(self) -> None:
        if self._punctuation_model is None:
            kwargs = {"model": self.punctuation_model_name, "device": self.device}
            if self.hub:
                kwargs["hub"] = self.hub
            self._punctuation_model = AutoModel(**kwargs)

    def _load_translation_model(self) -> None:
        if self._translation_model is not None:
            return

        if self._uses_mlx:
            self._load_mlx_translation_model()
            return

        from transformers import AutoModelForCausalLM, AutoModelForSeq2SeqLM, AutoTokenizer

        started_at = time.monotonic()
        logger.info(
            "Translation model loading model=%s device=%s mode=%s",
            self.model_name,
            self.device,
            "qwen-contextual" if self._uses_qwen else "seq2seq",
        )
        self._tokenizer = AutoTokenizer.from_pretrained(self.model_name)
        model_class = AutoModelForCausalLM if self._uses_qwen else AutoModelForSeq2SeqLM
        self._translation_model = model_class.from_pretrained(
            self.model_name,
            **self._translation_model_load_kwargs(),
        )
        logger.info(
            "Translation model moving to device model=%s device=%s",
            self.model_name,
            self.device,
        )
        self._translation_model.to(self.device)
        logger.info(
            "Translation model loaded model=%s elapsed_seconds=%.2f",
            self.model_name,
            time.monotonic() - started_at,
        )

    def _load_mlx_translation_model(self) -> None:
        try:
            from mlx_lm import generate, load
            from mlx_lm.sample_utils import make_sampler
        except ImportError as error:
            raise RuntimeError(
                "MLX translation requires the optional 'mlx' dependency. "
                "Run: uv sync --extra mlx"
            ) from error

        started_at = time.monotonic()
        logger.info("MLX translation model loading model=%s", self.model_name)
        self._translation_model, self._tokenizer = load(self.model_name)
        self._mlx_generate = generate
        self._mlx_sampler = make_sampler(temp=0.0)
        logger.info(
            "MLX translation model loaded model=%s elapsed_seconds=%.2f",
            self.model_name,
            time.monotonic() - started_at,
        )
