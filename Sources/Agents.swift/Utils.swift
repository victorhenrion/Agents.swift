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

// MARK: - camelCaseToKebabCase

func camelCaseToKebabCase(_ str: String) -> String {
    // If string is all uppercase, convert to lowercase
    if str == str.uppercased() && str != str.lowercased() {
        return str.lowercased().replacingOccurrences(of: "_", with: "-")
    }
    // Otherwise handle camelCase to kebab-case
    return
        str
        .replacingOccurrences(of: "[A-Z]", with: "-$0", options: .regularExpression)
        .deletingPrefix("-")
        .replacingOccurrences(of: "_", with: "-")
        .deletingSuffix("-")
}

extension String {
    fileprivate func deletingPrefix(_ prefix: String) -> String {
        guard self.hasPrefix(prefix) else { return self }
        return String(self.dropFirst(prefix.count))
    }
    fileprivate func deletingSuffix(_ suffix: String) -> String {
        guard self.hasSuffix(suffix) else { return self }
        return String(self.dropLast(suffix.count))
    }
}
