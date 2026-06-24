public struct LanguagePair: Equatable, Codable {
    public var source: String
    public var target: String

    public init(source: String = "auto", target: String = "en") {
        self.source = source
        self.target = target
    }
}
