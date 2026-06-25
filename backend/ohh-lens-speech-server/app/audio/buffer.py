class PCMChunkBuffer:
    def __init__(self, chunk_bytes: int) -> None:
        if chunk_bytes <= 0:
            raise ValueError("chunk_bytes must be positive")
        self.chunk_bytes = chunk_bytes
        self._buffer = bytearray()

    def append(self, chunk: bytes) -> None:
        self._buffer.extend(chunk)

    def pop_ready_chunks(self) -> list[bytes]:
        chunks: list[bytes] = []
        while len(self._buffer) >= self.chunk_bytes:
            chunks.append(bytes(self._buffer[: self.chunk_bytes]))
            del self._buffer[: self.chunk_bytes]
        return chunks

    def flush(self) -> bytes:
        remainder = bytes(self._buffer)
        self._buffer.clear()
        return remainder
