import logging

import torch

from app.core.translation import LocalEnglishVietnameseTranslator
from types import SimpleNamespace


class FakeTensor:
    def to(self, _device: str) -> "FakeTensor":
        return self


class FakeTokenizer:
    def __init__(self) -> None:
        self.src_lang: str | None = None

    def __call__(self, _text: str, return_tensors: str) -> dict[str, FakeTensor]:
        assert return_tensors == "pt"
        return {"input_ids": FakeTensor()}

    def get_lang_id(self, language: str) -> int:
        assert language == "vi"
        return 42

    def batch_decode(self, _generated: object, skip_special_tokens: bool) -> list[str]:
        assert skip_special_tokens is True
        return ["ban dich"]


class FakeTranslationModel:
    device = "cpu"

    def __init__(self) -> None:
        self.generate_kwargs: dict[str, object] | None = None

    def generate(self, **kwargs: object) -> list[int]:
        self.generate_kwargs = kwargs
        return [1, 2, 3]


class FakeBatch(dict):
    def to(self, _device: str) -> "FakeBatch":
        return self


class FakeQwenTokenizer:
    def __init__(self) -> None:
        self.messages: list[dict[str, str]] | None = None

    def apply_chat_template(
        self,
        messages: list[dict[str, str]],
        add_generation_prompt: bool,
        tokenize: bool,
        return_dict: bool,
        return_tensors: str,
    ) -> FakeBatch:
        assert add_generation_prompt is True
        assert tokenize is True
        assert return_dict is True
        assert return_tensors == "pt"
        self.messages = messages
        return FakeBatch({"input_ids": [[10, 11]]})

    def decode(self, token_ids: list[int], skip_special_tokens: bool) -> str:
        assert token_ids == [99]
        assert skip_special_tokens is True
        return "Bản dịch mới"


class FakeQwenModel:
    device = "cpu"

    def __init__(self) -> None:
        self.generate_kwargs: dict[str, object] | None = None
        self.generation_config = SimpleNamespace(
            temperature=0.6,
            top_p=0.95,
            top_k=20,
        )

    def generate(self, **kwargs: object) -> list[list[int]]:
        self.generate_kwargs = kwargs
        return [[10, 11, 99]]


class FakeMLXTokenizer:
    def __init__(self) -> None:
        self.messages: list[dict[str, str]] | None = None
        self.enable_thinking: bool | None = None

    def apply_chat_template(
        self,
        messages: list[dict[str, str]],
        add_generation_prompt: bool,
        enable_thinking: bool | None = None,
    ) -> str:
        assert add_generation_prompt is True
        self.messages = messages
        self.enable_thinking = enable_thinking
        return "formatted prompt"


def test_m2m100_translation_sets_english_source_and_forces_vietnamese_output():
    translator = LocalEnglishVietnameseTranslator(model_name="facebook/m2m100_418M")
    tokenizer = FakeTokenizer()
    model = FakeTranslationModel()
    translator._tokenizer = tokenizer
    translator._translation_model = model

    assert translator.translate("hello") == "ban dich"
    assert tokenizer.src_lang == "en"
    assert model.generate_kwargs == {
        "input_ids": model.generate_kwargs["input_ids"],
        "max_new_tokens": 128,
        "forced_bos_token_id": 42,
    }


def test_qwen_translation_uses_bilingual_pairs_as_context_and_returns_new_output_only():
    translator = LocalEnglishVietnameseTranslator(model_name="Qwen/Qwen2.5-7B-Instruct")
    tokenizer = FakeQwenTokenizer()
    model = FakeQwenModel()
    translator._tokenizer = tokenizer
    translator._translation_model = model

    translated = translator.translate_with_context(
        "Then make it thinner.",
        [("Move the control line to the top.", "Di chuyển đường điều khiển lên trên.")],
    )

    assert translated == "Bản dịch mới"
    assert "Move the control line to the top." in tokenizer.messages[1]["content"]
    assert "Di chuyển đường điều khiển lên trên." in tokenizer.messages[1]["content"]
    assert "Then make it thinner." in tokenizer.messages[1]["content"]
    assert model.generate_kwargs["do_sample"] is False
    assert model.generation_config.temperature is None
    assert model.generation_config.top_p is None
    assert model.generation_config.top_k is None


def test_qwen_translation_prompt_uses_source_and_target_languages():
    translator = LocalEnglishVietnameseTranslator(
        model_name="mlx-community/Qwen3-8B-4bit",
        source_language="ja",
        target_language="vi",
    )
    tokenizer = FakeMLXTokenizer()
    translator._tokenizer = tokenizer
    translator._translation_model = object()
    translator._mlx_generate = lambda **_kwargs: "Bản dịch mới"
    translator._mlx_sampler = "greedy-sampler"

    translator.translate_with_context(
        "これは新しい字幕です。",
        [("これは前の字幕です。", "Đây là phụ đề trước.")],
    )

    prompt_context = tokenizer.messages[1]["content"]
    assert "Japanese" in tokenizer.messages[0]["content"]
    assert "Vietnamese" in tokenizer.messages[0]["content"]
    assert "これは前の字幕です。" in prompt_context
    assert "Đây là phụ đề trước." in prompt_context
    assert "これは新しい字幕です。" in prompt_context


def test_qwen_translation_logs_context_and_duration_without_transcript_text(caplog):
    translator = LocalEnglishVietnameseTranslator(model_name="Qwen/Qwen2.5-7B-Instruct")
    translator._tokenizer = FakeQwenTokenizer()
    translator._translation_model = FakeQwenModel()

    with caplog.at_level(logging.INFO):
        translator.translate_with_context("secret subtitle", [("old", "cu")])

    assert "Qwen translation started model=Qwen/Qwen2.5-7B-Instruct" in caplog.text
    assert "context_pairs=1" in caplog.text
    assert "secret subtitle" not in caplog.text


def test_qwen_uses_float16_weights_on_mps_to_reduce_memory_use():
    translator = LocalEnglishVietnameseTranslator(
        model_name="Qwen/Qwen2.5-7B-Instruct",
        device="mps",
    )

    assert translator._translation_model_load_kwargs() == {"torch_dtype": torch.float16}


def test_mlx_qwen_translation_uses_context_and_greedy_generation():
    translator = LocalEnglishVietnameseTranslator(
        model_name="mlx-community/Qwen3-8B-4bit"
    )
    tokenizer = FakeMLXTokenizer()
    generation_calls: list[dict[str, object]] = []
    translator._tokenizer = tokenizer
    translator._translation_model = object()
    translator._mlx_generate = lambda **kwargs: generation_calls.append(kwargs) or "Bản dịch MLX"
    translator._mlx_sampler = "greedy-sampler"

    translated = translator.translate_with_context(
        "Then make it thinner.",
        [("Move the control line to the top.", "Di chuyển đường điều khiển lên trên.")],
    )

    assert translated == "Bản dịch MLX"
    assert tokenizer.enable_thinking is False
    assert "Then make it thinner." in tokenizer.messages[1]["content"]
    assert generation_calls == [
        {
            "model": translator._translation_model,
            "tokenizer": tokenizer,
            "prompt": "formatted prompt",
            "max_tokens": 128,
            "sampler": "greedy-sampler",
            "verbose": False,
        }
    ]


def test_mlx_qwen_retries_when_the_first_output_uses_cyrillic_script():
    translator = LocalEnglishVietnameseTranslator(
        model_name="mlx-community/Qwen2.5-7B-Instruct-4bit"
    )
    outputs = iter(["Механизм света", "Cơ chế ánh sáng"])
    translator._tokenizer = FakeMLXTokenizer()
    translator._translation_model = object()
    translator._mlx_generate = lambda **_kwargs: next(outputs)
    translator._mlx_sampler = "greedy-sampler"

    translated = translator.translate_with_context("light mechanism", [])

    assert translated == "Cơ chế ánh sáng"


def test_mlx_qwen_returns_empty_text_after_two_non_latin_outputs():
    translator = LocalEnglishVietnameseTranslator(
        model_name="mlx-community/Qwen2.5-7B-Instruct-4bit"
    )
    outputs = iter(["Механизм света", "Механизм света"])
    translator._tokenizer = FakeMLXTokenizer()
    translator._translation_model = object()
    translator._mlx_generate = lambda **_kwargs: next(outputs)
    translator._mlx_sampler = "greedy-sampler"

    assert translator.translate_with_context("light mechanism", []) == ""
