import Foundation

public enum SecretRedactor: Sendable {
  public static func redact(_ text: String, secrets: [String] = []) -> String {
    var result = text
    let secretVariants = Set(
      secrets
        .filter { !$0.isEmpty }
        .flatMap { secret in
          let encoded = percentEncode(secret)
          return [secret, encoded, encoded.lowercased()]
        }
    ).sorted { $0.count > $1.count }
    for secret in secretVariants {
      result = result.replacingOccurrences(of: secret, with: "<redacted>")
    }

    result = replacing(
      #"(?im)(authorization\s*:\s*(?:bearer\s+)?)[^\r\n]+"#,
      in: result,
      with: "$1<redacted>"
    )
    result = replacing(
      #"(?im)([\"']?(?:token|access[_-]?token|webhook[_-]?secret|authorization)[\"']?\s*[:=]\s*)(?:\"(?:\\.|[^\"])*\"|'[^']*'|[^\s,}\]]+)"#,
      in: result,
      with: "$1\"<redacted>\""
    )
    result = replacing(
      #"(?im)([\"']?(?:state|value)[\"']?\s*[:=]\s*)(?:\"(?:\\.|[^\"])*\"|'[^']*'|[^\s,}\]]+)"#,
      in: result,
      with: "$1\"<redacted>\""
    )
    result = replacing(
      #"(?im)(\b(?:request\s+|response\s+)?body\s*[:=]\s*).*$"#,
      in: result,
      with: "$1<redacted>"
    )
    result = replacing(#"(?i)\bhttps?://[^\s\"'<>]+"#, in: result, with: "<redacted-url>")
    result = replacing(
      #"(?i)\b(?:sensor|binary_sensor|input_number|number|device_tracker|person)\.[a-z0-9_]+\b"#,
      in: result,
      with: "<redacted-entity>"
    )
    result = replacing(#"\[[0-9A-Fa-f:]+\]"#, in: result, with: "<redacted-address>")
    result = replacing(
      #"(?<![A-Za-z0-9])(?:[A-Fa-f0-9]{1,4}:){2,7}[A-Fa-f0-9]{0,4}(?![A-Za-z0-9])"#,
      in: result,
      with: "<redacted-address>"
    )
    result = replacing(
      #"(?<![0-9])(?:25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})(?:\.(?:25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})){3}(?![0-9])"#,
      in: result,
      with: "<redacted-address>"
    )
    return result
  }

  private static func replacing(
    _ pattern: String,
    in text: String,
    with template: String
  ) -> String {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
    return expression.stringByReplacingMatches(
      in: text,
      range: NSRange(text.startIndex..., in: text),
      withTemplate: template
    )
  }

  private static func percentEncode(_ value: String) -> String {
    value.utf8.map { byte in
      switch byte {
      case 45, 46, 48...57, 65...90, 95, 97...122, 126:
        String(UnicodeScalar(byte))
      default:
        String(format: "%%%02X", byte)
      }
    }.joined()
  }
}
