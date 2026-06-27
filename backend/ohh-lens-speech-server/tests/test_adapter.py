import numpy as np

from app.funasr.adapter import FunASRStreamingAdapter


class FakeModel:
    def __init__(self, responses: list[object]) -> None:
        self.responses = responses
        self.calls: list[dict] = []

    def generate(self, **kwargs):
        self.calls.append(kwargs)
        return self.responses.pop(0)


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
    assert first_call["is_final"] is False
    assert first_call["cache"] is second_call["cache"]
    assert second_call["is_final"] is True


def test_adapter_end_cleans_up_session_state():
    adapter = FunASRStreamingAdapter(
        model_name="iic/SenseVoiceSmall",
        device="mps",
    )

    adapter.begin("session-1", language="en")
    assert "session-1" in adapter._sessions

    adapter.end("session-1")

    assert "session-1" not in adapter._sessions
