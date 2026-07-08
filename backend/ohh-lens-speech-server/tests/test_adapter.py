import logging
import os
import sys
import types

import numpy as np
import pytest

from app.funasr.adapter import FunASRStreamingAdapter


class FakeModel:
    def __init__(self, responses: list[object]) -> None:
        self.responses = responses
        self.calls: list[dict] = []

    def generate(self, **kwargs):
        self.calls.append(kwargs)
        return self.responses.pop(0)


class FakeVADModel:
    def __init__(self, responses: list[object]) -> None:
        self.responses = responses
        self.calls: list[dict] = []

    def generate(self, **kwargs):
        self.calls.append(kwargs)
        return self.responses.pop(0)


class CapturingAutoModel:
    calls: list[dict] = []

    def __init__(self, **kwargs) -> None:
        self.kwargs = kwargs
        self.calls.append(kwargs)

    def generate(self, **kwargs):
        return []


def test_adapter_logs_model_load_configuration(monkeypatch, caplog):
    fake_funasr = types.SimpleNamespace(AutoModel=CapturingAutoModel)
    monkeypatch.setitem(sys.modules, "funasr", fake_funasr)
    monkeypatch.setattr("app.funasr.adapter.find_spec", lambda name: object())
    CapturingAutoModel.calls = []
    caplog.set_level(logging.INFO)

    adapter = FunASRStreamingAdapter(
        model_name="Qwen/Qwen3-ASR-1.7B",
        device="cpu",
        hub="hf",
    )

    adapter.load()

    assert "Loading FunASR ASR model" in caplog.text
    assert "Qwen/Qwen3-ASR-1.7B" in caplog.text
    assert "hub=hf" in caplog.text
    assert "device=cpu" in caplog.text


def test_adapter_raises_clear_error_for_qwen_models_without_qwen_asr(monkeypatch):
    fake_funasr = types.SimpleNamespace(AutoModel=CapturingAutoModel)
    monkeypatch.setitem(sys.modules, "funasr", fake_funasr)
    monkeypatch.setattr("app.funasr.adapter.find_spec", lambda name: None)

    adapter = FunASRStreamingAdapter(
        model_name="Qwen/Qwen3-ASR-1.7B",
        device="cpu",
        hub="hf",
    )

    with pytest.raises(ImportError) as error:
        adapter.load()

    assert "Qwen/Qwen3-ASR-1.7B requires the qwen-asr package" in str(error.value)
    assert "pip install qwen-asr" in str(error.value)


@pytest.mark.skipif(
    os.getenv("RUN_REAL_FUNASR_TESTS") != "1",
    reason="set RUN_REAL_FUNASR_TESTS=1 to run real model load tests",
)
def test_adapter_can_attempt_real_qwen_model_load_and_emit_logs(caplog):
    caplog.set_level(logging.INFO)

    adapter = FunASRStreamingAdapter(
        model_name=os.getenv("REAL_FUNASR_MODEL_NAME", "Qwen/Qwen3-ASR-1.7B"),
        device=os.getenv("REAL_FUNASR_DEVICE", "cpu"),
        hub=os.getenv("REAL_FUNASR_HUB", "hf"),
        vad_model_name=os.getenv("REAL_FUNASR_VAD_MODEL_NAME", "fsmn-vad"),
    )

    try:
        adapter.load()
    except Exception as error:
        pytest.fail(f"real Qwen model load failed: {error}\nCaptured logs:\n{caplog.text}")

    assert adapter.ready() is True
    assert "Loading FunASR ASR model" in caplog.text
    assert "Qwen/Qwen3-ASR-1.7B" in caplog.text


@pytest.mark.skipif(
    os.getenv("RUN_REAL_FUNASR_TESTS") != "1",
    reason="set RUN_REAL_FUNASR_TESTS=1 to run real model compatibility tests",
)
def test_adapter_fun_asr_nano_accepts_streaming_silence_without_typeerror():
    adapter = FunASRStreamingAdapter(
        model_name="FunAudioLLM/Fun-ASR-Nano-2512",
        device=os.getenv("REAL_FUNASR_DEVICE", "cpu"),
        hub=os.getenv("REAL_FUNASR_HUB", "hf"),
        vad_model_name="",
    )

    adapter.load()
    adapter.begin("session-nano", language="auto")

    results = adapter.push_audio("session-nano", b"\x00\x00" * 9600, is_final=False)

    assert results == []


def test_adapter_passes_streaming_runtime_config_and_reuses_session_cache():
    adapter = FunASRStreamingAdapter(
        model_name="iic/SenseVoiceSmall",
        device="mps",
    )
    model = FakeModel(
        responses=[
            [{"text": "<|en|>hello", "is_final": False}],
            [{"text": "<|en|>world", "is_final": True}],
        ]
    )
    adapter._model = model

    adapter.begin("session-1", language="en")

    first = adapter.push_audio("session-1", b"\x00\x80\xff\x7f", is_final=False)
    second = adapter.push_audio("session-1", b"\x01\x00\x02\x00", is_final=True)

    assert [item.text for item in first] == ["hello"]
    assert [item.text for item in second] == ["world"]

    assert len(model.calls) == 2
    first_call, second_call = model.calls

    assert isinstance(first_call["input"], np.ndarray)
    assert first_call["input"].dtype == np.float32
    assert first_call["language"] == "en"
    assert first_call["use_itn"] is True
    assert first_call["chunk_size"] == [0, 10, 5]
    assert first_call["encoder_chunk_look_back"] == 4
    assert first_call["decoder_chunk_look_back"] == 1
    assert first_call["is_final"] is False
    assert first_call["cache"] is second_call["cache"]
    assert second_call["is_final"] is True


def test_adapter_passes_torch_tensor_input_for_fun_asr_models():
    adapter = FunASRStreamingAdapter(
        model_name="FunAudioLLM/Fun-ASR-Nano-2512",
        device="cpu",
        vad_model_name="",
    )
    model = FakeModel(
        responses=[
            [{"text": "hello", "is_final": False}],
        ]
    )
    adapter._model = model

    adapter.begin("session-1", language="en")

    results = adapter.push_audio("session-1", b"\x00\x80\xff\x7f", is_final=False)

    assert [item.text for item in results] == ["hello"]
    assert model.calls
    assert model.calls[0]["input"].__class__.__name__ == "Tensor"


def test_adapter_load_uses_hf_hub_by_default(monkeypatch):
    fake_funasr = types.SimpleNamespace(AutoModel=CapturingAutoModel)
    monkeypatch.setitem(sys.modules, "funasr", fake_funasr)
    CapturingAutoModel.calls = []

    adapter = FunASRStreamingAdapter(
        model_name="iic/SenseVoiceSmall",
        device="mps",
    )

    adapter.load()

    assert len(CapturingAutoModel.calls) == 2
    asr_call, vad_call = CapturingAutoModel.calls
    assert asr_call == {"model": "iic/SenseVoiceSmall", "device": "mps", "hub": "hf"}
    assert vad_call == {"model": "fsmn-vad", "device": "mps", "hub": "hf"}


def test_adapter_load_passes_hf_hub_when_configured(monkeypatch):
    fake_funasr = types.SimpleNamespace(AutoModel=CapturingAutoModel)
    monkeypatch.setitem(sys.modules, "funasr", fake_funasr)
    CapturingAutoModel.calls = []

    adapter = FunASRStreamingAdapter(
        model_name="iic/SenseVoiceSmall",
        device="mps",
        hub="hf",
    )

    adapter.load()

    assert len(CapturingAutoModel.calls) == 2
    asr_call, vad_call = CapturingAutoModel.calls
    assert asr_call == {"model": "iic/SenseVoiceSmall", "device": "mps", "hub": "hf"}
    assert vad_call == {"model": "fsmn-vad", "device": "mps", "hub": "hf"}


def test_adapter_load_enables_trust_remote_code_for_fun_asr_models(monkeypatch):
    fake_funasr = types.SimpleNamespace(AutoModel=CapturingAutoModel)
    monkeypatch.setitem(sys.modules, "funasr", fake_funasr)
    CapturingAutoModel.calls = []

    adapter = FunASRStreamingAdapter(
        model_name="FunAudioLLM/Fun-ASR-Nano-2512",
        device="cpu",
        hub="hf",
        vad_model_name="",
    )

    adapter.load()

    assert CapturingAutoModel.calls == [
        {
            "model": "FunAudioLLM/Fun-ASR-Nano-2512",
            "device": "cpu",
            "hub": "hf",
            "trust_remote_code": True,
        }
    ]


def test_adapter_end_cleans_up_session_state():
    adapter = FunASRStreamingAdapter(
        model_name="iic/SenseVoiceSmall",
        device="mps",
    )

    adapter.begin("session-1", language="en")
    assert "session-1" in adapter._sessions

    adapter.end("session-1")

    assert "session-1" not in adapter._sessions


def test_adapter_skips_asr_when_vad_detects_no_speech():
    adapter = FunASRStreamingAdapter(
        model_name="iic/SenseVoiceSmall",
        device="mps",
        vad_model_name="fsmn-vad",
    )
    model = FakeModel(
        responses=[
            [{"text": "should not be used", "is_final": False}],
        ]
    )
    vad_model = FakeVADModel(
        responses=[
            [{"value": []}],
            [{"value": []}],
            [{"value": []}],
            [{"value": []}],
            [{"value": []}],
        ]
    )
    adapter._model = model
    adapter._vad_model = vad_model

    adapter.begin("session-1", language="en")

    results = adapter.push_audio("session-1", b"\x00\x80" * 16000, is_final=False)

    assert results == []
    assert len(model.calls) == 0
    assert len(vad_model.calls) == 5


def test_adapter_runs_asr_when_vad_detects_speech():
    adapter = FunASRStreamingAdapter(
        model_name="iic/SenseVoiceSmall",
        device="mps",
        vad_model_name="fsmn-vad",
    )
    model = FakeModel(
        responses=[
            [{"text": "<|en|>hello", "is_final": False}],
        ]
    )
    vad_model = FakeVADModel(
        responses=[
            [{"value": []}],
            [{"value": []}],
            [{"value": [[610, -1]]}],
            [{"value": []}],
            [{"value": [[-1, 1000]]}],
        ]
    )
    adapter._model = model
    adapter._vad_model = vad_model

    adapter.begin("session-1", language="en")

    results = adapter.push_audio("session-1", b"\x00\x80" * 16000, is_final=False)

    assert [item.text for item in results] == ["hello"]
    assert len(model.calls) == 1
    assert len(vad_model.calls) == 5


# def test_adapter_skips_asr_when_audio_rms_is_below_threshold():
#     adapter = FunASRStreamingAdapter(
#         model_name="iic/SenseVoiceSmall",
#         device="mps",
#         vad_model_name="fsmn-vad",
#         min_audio_rms=0.01,
#     )
#     model = FakeModel(
#         responses=[
#             [{"text": "should not be used", "is_final": False}],
#         ]
#     )
#     vad_model = FakeVADModel(
#         responses=[
#             [{"value": [[0, -1]]}],
#             [{"value": [[-1, 200]]}],
#         ]
#     )
#     adapter._model = model
#     adapter._vad_model = vad_model

#     adapter.begin("session-1", language="en")

#     quiet_chunk = (np.array([100, -100], dtype=np.int16).tobytes()) * 4800
#     results = adapter.push_audio("session-1", quiet_chunk, is_final=False)

#     assert results == []
#     assert len(model.calls) == 0


def test_adapter_allows_asr_when_audio_rms_meets_threshold():
    adapter = FunASRStreamingAdapter(
        model_name="iic/SenseVoiceSmall",
        device="mps",
        vad_model_name="fsmn-vad",
        min_audio_rms=0.01,
    )
    model = FakeModel(
        responses=[
            [{"text": "<|en|>hello", "is_final": False}],
        ]
    )
    vad_model = FakeVADModel(
        responses=[
            [{"value": [[0, -1]]}],
            [{"value": []}],
            [{"value": [[-1, 600]]}],
        ]
    )
    adapter._model = model
    adapter._vad_model = vad_model

    adapter.begin("session-1", language="en")

    loud_chunk = (np.array([2000, -2000], dtype=np.int16).tobytes()) * 4800
    results = adapter.push_audio("session-1", loud_chunk, is_final=False)

    assert [item.text for item in results] == ["hello"]
    assert len(model.calls) == 1


def test_adapter_suppresses_filler_only_partial_results():
    adapter = FunASRStreamingAdapter(
        model_name="iic/SenseVoiceSmall",
        device="mps",
    )
    model = FakeModel(
        responses=[
            [{"text": "<|en|>yeah oh yeah", "is_final": False}],
        ]
    )
    adapter._model = model

    adapter.begin("session-1", language="en")

    results = adapter.push_audio("session-1", b"\x00\x80\xff\x7f", is_final=False)

    assert results == []


def test_adapter_keeps_filler_text_when_result_is_final():
    adapter = FunASRStreamingAdapter(
        model_name="iic/SenseVoiceSmall",
        device="mps",
    )
    model = FakeModel(
        responses=[
            [{"text": "<|en|>yeah oh yeah", "is_final": True}],
        ]
    )
    adapter._model = model

    adapter.begin("session-1", language="en")

    results = adapter.push_audio("session-1", b"\x00\x80\xff\x7f", is_final=True)

    assert [item.text for item in results] == ["yeah oh yeah"]


def test_adapter_strips_all_punctuation_and_lowercases_transcript_text():
    adapter = FunASRStreamingAdapter(
        model_name="iic/SenseVoiceSmall",
        device="mps",
    )
    model = FakeModel(
        responses=[
            [{"text": "<|en|>Hello, WORLD! it's Me... #1", "is_final": False}],
        ]
    )
    adapter._model = model

    adapter.begin("session-1", language="en")

    results = adapter.push_audio("session-1", b"\x00\x80\xff\x7f", is_final=False)

    assert [item.text for item in results] == ["hello world it's me 1"]
