import Foundation

public protocol FunASRServicing: Sendable {
    func healthCheck() async -> Bool
}

public enum FunASRStreamingEvent: Equatable, Sendable {
    case ready
    case partial(String)
    case final(String)
    case error(String)
    case closed
}

public protocol FunASRStreamingServicing: Sendable {
    func startSession(language: String) async throws
    func sendAudioChunk(_ data: Data) async throws
    func stopSession() async
    func nextEvent() async throws -> FunASRStreamingEvent
}

public struct FunASRClient: FunASRServicing {
    public let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    public func healthCheck() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 1

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
