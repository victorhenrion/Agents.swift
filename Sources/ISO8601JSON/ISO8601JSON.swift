import Foundation

// #region Decoding
extension ParseStrategy where Self == Date.ISO8601FormatStyle {
    package static var iso8601withFractionalSeconds: Self {
        .init(includingFractionalSeconds: true)
    }
}

extension JSONDecoder.DateDecodingStrategy {
    package static let iso8601withOptionalFractionalSeconds = custom {
        let value: String = try $0.singleValueContainer().decode(String.self)
        let fractional: Bool = value.contains(".")
        return try .init(value, strategy: fractional ? .iso8601withFractionalSeconds : .iso8601)
    }
}
// #endregion

// #region Encoding
extension FormatStyle where Self == Date.ISO8601FormatStyle {
    package static var iso8601withFractionalSeconds: Self {
        .init(includingFractionalSeconds: true)
    }
}

extension JSONEncoder.DateEncodingStrategy {
    package static let iso8601withFractionalSeconds = custom {
        var container = $1.singleValueContainer()
        try container.encode($0.formatted(.iso8601withFractionalSeconds))
    }
}
// #endregion
