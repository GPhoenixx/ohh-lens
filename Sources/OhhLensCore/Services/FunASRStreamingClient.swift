import Foundation

public actor FunASRStreamingClient: FunASRStreamingServicing {
    private let webSocketURL: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    public init(
        webSocketURL: URL = URL(string: "ws://127.0.0.1:8765/ws/transcribe")!,
        session: URLSession = .shared
    ) {
        self.webSocketURL = webSocketURL
        self.session = session
    }

    public func startSession(language: String, targetLanguage: String) async throws {
        let task = session.webSocketTask(with: webSocketURL)
        self.task = task
        task.resume()

        let payload = try Self.startMessage(language: language, targetLanguage: targetLanguage)
        try await task.send(.string(payload))
    }

    public func sendAudioChunk(_ data: Data) async throws {
        guard let task else {
            throw StreamingError.notConnected
        }

        try await task.send(.data(data))
    }

    public func stopSession() async {
        guard let task else {
            return
        }

        try? await task.send(.string(#"{"type":"stop"}"#))
        task.cancel(with: .goingAway, reason: nil)
        self.task = nil
    }

    public func nextEvent() async throws -> FunASRStreamingEvent {
        guard let task else {
            throw StreamingError.notConnected
        }

        let message = try await task.receive()

        switch message {
        case .string(let string):
            return try Self.decodeEvent(from: Data(string.utf8))
        case .data(let data):
            return try Self.decodeEvent(from: data)
        @unknown default:
            throw StreamingError.unsupportedMessage
        }
    }
}

extension FunASRStreamingClient {
    static func startMessage(
        language: String,
        targetLanguage: String = "vi",
        sessionID: String = UUID().uuidString
    ) throws -> String {
        let payload = StartMessage(
            type: "start",
            sessionID: sessionID,
            sampleRate: 16_000,
            channels: 1,
            sampleFormat: "pcm_s16le",
            language: language,
            targetLanguage: targetLanguage
        )
        let data = try JSONEncoder().encode(payload)
        return String(decoding: data, as: UTF8.self)
    }

    static func decodeEvent(from data: Data) throws -> FunASRStreamingEvent {
        let payload = try JSONDecoder().decode(EventPayload.self, from: data)

        switch payload.type {
        case "ready":
            return .ready
        case "partial":
            if let segmentID = payload.segmentID {
                return .partialSegment(segmentID: segmentID, text: payload.text ?? "")
            }
            return .partial(payload.text ?? "")
        case "final":
            if let segmentID = payload.segmentID {
                return .finalSegment(segmentID: segmentID, text: payload.text ?? "")
            }
            return .final(payload.text ?? "")
        case "translation":
            return .translation(
                segmentID: payload.segmentID ?? "legacy-segment",
                translationID: payload.translationID ?? "legacy-translation",
                sourceText: payload.sourceText ?? "",
                translatedText: payload.translatedText ?? ""
            )
        case "error":
            return .error(payload.message ?? payload.text ?? "Unknown backend error")
        case "closed":
            return .closed
        default:
            throw StreamingError.unknownEvent(payload.type)
        }
    }
}

private extension FunASRStreamingClient {
    struct StartMessage: Encodable {
        let type: String
        let sessionID: String
        let sampleRate: Int
        let channels: Int
        let sampleFormat: String
        let language: String
        let targetLanguage: String

        enum CodingKeys: String, CodingKey {
            case type
            case sessionID = "session_id"
            case sampleRate = "sample_rate"
            case channels
            case sampleFormat = "sample_format"
            case language
            case targetLanguage = "target_language"
        }
    }

    struct EventPayload: Decodable {
        let type: String
        let segmentID: String?
        let translationID: String?
        let text: String?
        let message: String?
        let sourceText: String?
        let translatedText: String?

        enum CodingKeys: String, CodingKey {
            case type
            case segmentID = "segment_id"
            case translationID = "translation_id"
            case text
            case message
            case sourceText = "source_text"
            case translatedText = "translated_text"
        }
    }

    enum StreamingError: LocalizedError {
        case notConnected
        case unsupportedMessage
        case unknownEvent(String)

        var errorDescription: String? {
            switch self {
            case .notConnected:
                return "Streaming session is not connected."
            case .unsupportedMessage:
                return "Received an unsupported WebSocket message."
            case .unknownEvent(let eventType):
                return "Unknown streaming event: \(eventType)"
            }
        }
    }
}
