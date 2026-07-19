from app.core.protocol import StartMessage


def test_start_message_accepts_supported_multilingual_pair():
    message = StartMessage(
        type="start",
        session_id="ja-vi",
        sample_rate=16000,
        channels=1,
        sample_format="pcm_s16le",
        language="JA",
        target_language="VI",
    )

    assert message.language == "ja"
    assert message.target_language == "vi"


def test_start_message_rejects_unsupported_language_codes():
    for field in ("language", "target_language"):
        values = {
            "type": "start",
            "session_id": "unsupported",
            "sample_rate": 16000,
            "channels": 1,
            "sample_format": "pcm_s16le",
            "language": "en",
            "target_language": "vi",
        }
        values[field] = "xx"

        try:
            StartMessage(**values)
        except ValueError as error:
            assert field in str(error)
        else:
            raise AssertionError(f"expected {field} validation error")


def test_start_message_allows_auto_source_for_asr_only_session():
    message = StartMessage(
        type="start",
        session_id="auto",
        sample_rate=16000,
        channels=1,
        sample_format="pcm_s16le",
        language="auto",
        target_language="vi",
    )

    assert message.language == "auto"


def test_start_message_rejects_wrong_sample_rate():
    try:
        StartMessage(
            type="start",
            session_id="abc",
            sample_rate=48000,
            channels=1,
            sample_format="pcm_s16le",
            language="auto",
        )
    except ValueError as error:
        assert "sample_rate" in str(error)
    else:
        raise AssertionError("expected validation error")
