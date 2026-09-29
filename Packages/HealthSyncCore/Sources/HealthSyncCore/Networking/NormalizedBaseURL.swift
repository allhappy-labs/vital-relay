import Foundation

public enum NormalizedBaseURLError: Error, Equatable, Sendable {
  case malformedURL
  case unsupportedScheme
  case credentialsNotAllowed
  case insecureRemoteHTTP
  case localHTTPRequiresConfirmation
  case invalidPathComponent
}

public struct NormalizedBaseURL: Sendable, Equatable {
  public let url: URL

  private init(url: URL) {
    self.url = url
  }

  public static func parse(
    _ input: String,
    allowConfirmedLocalHTTP: Bool
  ) throws -> Self {
    let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedInput.isEmpty,
      var components = URLComponents(string: trimmedInput),
      let originalScheme = components.scheme,
      let originalHost = components.host,
      !originalHost.isEmpty
    else {
      throw NormalizedBaseURLError.malformedURL
    }

    guard components.user == nil, components.password == nil else {
      throw NormalizedBaseURLError.credentialsNotAllowed
    }

    let scheme = originalScheme.lowercased()
    let host = originalHost.lowercased()
    let classificationHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    guard scheme == "https" || scheme == "http" else {
      throw NormalizedBaseURLError.unsupportedScheme
    }

    if scheme == "http" {
      guard isLocalHost(classificationHost) else {
        throw NormalizedBaseURLError.insecureRemoteHTTP
      }
      guard allowConfirmedLocalHTTP else {
        throw NormalizedBaseURLError.localHTTPRequiresConfirmation
      }
    }

    components.scheme = scheme
    components.host = host
    components.query = nil
    components.fragment = nil
    components.percentEncodedPath = normalizedPath(components.percentEncodedPath)

    guard let normalizedURL = components.url else {
      throw NormalizedBaseURLError.malformedURL
    }

    return Self(url: normalizedURL)
  }

  public var authenticatedAPIURL: URL {
    endpointURL(pathComponents: ["api"], trailingSlash: true)
  }

  public var healthBridgeWebhookURL: URL {
    endpointURL(pathComponents: ["api", "webhook", "health_bridge"])
  }

  public var statesURL: URL {
    endpointURL(pathComponents: ["api", "states"])
  }

  public func stateURL(entityID: String) throws -> URL {
    guard Self.isValidPathComponent(entityID) else {
      throw NormalizedBaseURLError.invalidPathComponent
    }
    return endpointURL(pathComponents: ["api", "states", entityID])
  }

  private func endpointURL(
    pathComponents: [String],
    trailingSlash: Bool = false
  ) -> URL {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    var path = components.percentEncodedPath

    for pathComponent in pathComponents {
      if !path.hasSuffix("/") {
        path += "/"
      }
      path += Self.percentEncodePathComponent(pathComponent)
    }

    if trailingSlash, !path.hasSuffix("/") {
      path += "/"
    }

    components.percentEncodedPath = path
    return components.url!
  }

  private static func normalizedPath(_ path: String) -> String {
    var normalized = path
    while normalized.count > 1, normalized.hasSuffix("/") {
      normalized.removeLast()
    }
    return normalized == "/" ? "" : normalized
  }

  private static func percentEncodePathComponent(_ value: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#%")
    return value.addingPercentEncoding(withAllowedCharacters: allowed)!
  }

  private static func isValidPathComponent(_ value: String) -> Bool {
    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
  }

  private static func isLocalHost(_ host: String) -> Bool {
    if host == "localhost" || host.hasSuffix(".local") {
      return true
    }

    if TailscaleAddressPolicy.isMachineMagicDNSHost(host) {
      return true
    }

    if host.contains(":") {
      return isLocalIPv6(host)
    }

    return isLocalIPv4(host)
  }

  private static func isLocalIPv4(_ host: String) -> Bool {
    let octets = host.split(separator: ".", omittingEmptySubsequences: false)
    guard octets.count == 4 else {
      return false
    }

    let values = octets.compactMap { octet -> UInt8? in
      guard !octet.isEmpty, octet.allSatisfy(\.isNumber), let value = UInt8(octet) else {
        return nil
      }
      return value
    }
    guard values.count == 4 else {
      return false
    }

    if TailscaleAddressPolicy.isTailscaleIPAddress(host) {
      return true
    }

    switch (values[0], values[1]) {
    case (10, _), (127, _), (169, 254), (192, 168):
      return true
    case (172, 16...31):
      return true
    default:
      return false
    }
  }

  private static func isLocalIPv6(_ host: String) -> Bool {
    let address = host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
    if address == "::1" {
      return true
    }

    let lowercaseAddress = address.lowercased()
    return lowercaseAddress.hasPrefix("fc")
      || lowercaseAddress.hasPrefix("fd")
      || ["fe8", "fe9", "fea", "feb"].contains { lowercaseAddress.hasPrefix($0) }
  }
}
