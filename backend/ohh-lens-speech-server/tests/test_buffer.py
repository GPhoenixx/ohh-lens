from app.audio.buffer import PCMChunkBuffer


def test_pcm_buffer_rejects_non_positive_chunk_size():
    try:
        PCMChunkBuffer(chunk_bytes=0)
    except ValueError as error:
        assert "chunk_bytes" in str(error)
    else:
        raise AssertionError("expected validation error")


def test_pcm_buffer_yields_full_chunk_and_keeps_remainder():
    buffer = PCMChunkBuffer(chunk_bytes=8)

    buffer.append(b"1234567890")

    assert buffer.pop_ready_chunks() == [b"12345678"]
    assert buffer.flush() == b"90"
