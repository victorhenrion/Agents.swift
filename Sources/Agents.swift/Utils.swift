import Foundation

// MARK: - JSON Decoder and Encoder

let jsonDecoder = {
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601withOptionalFractionalSeconds
    return dec
}()

let jsonEncoder = {
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601  // iso8601withFractionalSeconds not required
    return enc
}()

// MARK: - Broader ISO8601 Support for JSON

extension ParseStrategy where Self == Date.ISO8601FormatStyle {
    static var iso8601withFractionalSeconds: Self { .init(includingFractionalSeconds: true) }
}

extension JSONDecoder.DateDecodingStrategy {
    static let iso8601withOptionalFractionalSeconds = custom {
        let string = try $0.singleValueContainer().decode(String.self)
        do {
            return try .init(string, strategy: .iso8601withFractionalSeconds)
        } catch {
            return try .init(string, strategy: .iso8601)
        }
    }
}

extension FormatStyle where Self == Date.ISO8601FormatStyle {
    static var iso8601withFractionalSeconds: Self { .init(includingFractionalSeconds: true) }
}

extension JSONEncoder.DateEncodingStrategy {
    static let iso8601withFractionalSeconds = custom {
        var container = $1.singleValueContainer()
        try container.encode($0.formatted(.iso8601withFractionalSeconds))
    }
}
