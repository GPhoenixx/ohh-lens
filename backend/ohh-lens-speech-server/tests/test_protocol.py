from app.core.protocol import StartMessage


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
