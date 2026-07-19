import logging
import time
import unicodedata

from funasr import AutoModel


logger = logging.getLogger(__name__)


class LocalEnglishVietnameseTranslator:
    """Lazy local English -> Vietnamese translation with backend punctuation."""

    def __init__(
        self,
        model_name: str = "Helsinki-NLP/opus-mt-en-vi",
        punctuation_model_name: str = "ct-punc",
        device: str = "cpu",
        hub: str = "hf",
    ) -> None:
        self.model_name = model_name
        self.punctuation_model_name = punctuation_model_name
        self.device = device
        self.hub = hub
        self._tokenizer = None
        self._translation_model = None
        self._punctuation_model = None
        self._mlx_generate = None
        self._mlx_sampler = None

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
            self._tokenizer.src_lang = "en"
        inputs = self._tokenizer(text, return_tensors="pt")
        inputs = {key: value.to(self._translation_model.device) for key, value in inputs.items()}
        generation_kwargs = {"max_new_tokens": 128}
        if self._uses_m2m100:
            generation_kwargs["forced_bos_token_id"] = self._tokenizer.get_lang_id("vi")
        generated = self._translation_model.generate(**inputs, **generation_kwargs)
        return self._tokenizer.batch_decode(generated, skip_special_tokens=True)[0].strip()

    def translate_with_context(
        self, text: str, context: list[tuple[str, str]]
    ) -> str:
        if self._uses_mlx:
            return self._translate_with_mlx(text, context)
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
            messages = self._translation_messages(text, context)
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

    def _translate_with_mlx(self, text: str, context: list[tuple[str, str]]) -> str:
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
                self._translation_messages(text, context)
            )
            if not self._uses_latin_script(translated):
                logger.warning(
                    "MLX translation rejected non-Latin output model=%s; retrying",
                    self.model_name,
                )
                translated = self._generate_mlx_translation(
                    self._translation_messages(text, context, strict=True)
                )
            if not self._uses_latin_script(translated):
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

    @staticmethod
    def _qwen_translation_prompt(text: str, context: list[tuple[str, str]]) -> str:
        context_lines = [
            f"English: {english}\nVietnamese: {vietnamese}"
            for english, vietnamese in context
        ]
        context_text = "\n\n".join(context_lines) or "(none)"
        return f"CONTEXT\n{context_text}\n\nNEW_ENGLISH\n{text}"

    def _generate_mlx_translation(self, messages: list[dict[str, str]]) -> str:
        prompt = self._tokenizer.apply_chat_template(
            messages,
            add_generation_prompt=True,
        )
        return self._mlx_generate(
            model=self._translation_model,
            tokenizer=self._tokenizer,
            prompt=prompt,
            max_tokens=128,
            sampler=self._mlx_sampler,
            verbose=False,
        ).strip()

    def _translation_messages(
        self, text: str, context: list[tuple[str, str]], strict: bool = False
    ) -> list[dict[str, str]]:
        system_text = (
            "Translate NEW_ENGLISH into natural Vietnamese. Use CONTEXT only "
            "to resolve references and terminology. Return only the Vietnamese "
            "translation. Do not explain or repeat the context. Write Vietnamese "
            "quoc ngu using the Latin Vietnamese alphabet with diacritics."
        )
        if strict:
            system_text += " Never output Cyrillic, Chinese, Arabic, or any non-Latin script."
        return [
            {"role": "system", "content": system_text},
            {"role": "user", "content": self._qwen_translation_prompt(text, context)},
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
