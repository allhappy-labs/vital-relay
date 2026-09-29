import Darwin
import Foundation
import Network

enum ResolvedIPAddress: Hashable, Sendable {
  case ipv4(String)
  case ipv6(String)

  init?(_ value: String) {
    if IPv4Address(value) != nil {
      self = .ipv4(value)
    } else if IPv6Address(value) != nil {
      self = .ipv6(value)
    } else {
      return nil
    }
  }

  var stringValue: String {
    switch self {
    case .ipv4(let value), .ipv6(let value):
      value
    }
  }

  var sortRank: Int {
    switch self {
    case .ipv4:
      0
    case .ipv6:
      1
    }
  }

  var percentEncodedHost: String {
    switch self {
    case .ipv4(let value):
      value
    case .ipv6(let value):
      "[\(value)]"
    }
  }
}

protocol HostAddressResolving: Sendable {
  func addresses(for host: String) async throws -> [ResolvedIPAddress]
}

struct SystemHostAddressResolver: HostAddressResolving {
  func addresses(for host: String) async throws -> [ResolvedIPAddress] {
    try Task.checkCancellation()
    let addresses = try await Task.detached(priority: .utility) {
      try Self.resolveSynchronously(host)
    }.value
    try Task.checkCancellation()
    return addresses
  }

  private static func resolveSynchronously(_ host: String) throws -> [ResolvedIPAddress] {
    var hints = addrinfo()
    hints.ai_flags = AI_ADDRCONFIG
    hints.ai_family = AF_UNSPEC
    hints.ai_socktype = SOCK_STREAM
    hints.ai_protocol = IPPROTO_TCP

    var result: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, nil, &hints, &result) == 0, let firstResult = result else {
      throw HostResolutionError.failed
    }
    defer { freeaddrinfo(firstResult) }

    var addresses = Set<ResolvedIPAddress>()
    var current: UnsafeMutablePointer<addrinfo>? = firstResult
    while let entry = current {
      let info = entry.pointee
      current = info.ai_next
      guard info.ai_family == AF_INET || info.ai_family == AF_INET6,
        let socketAddress = info.ai_addr
      else {
        continue
      }

      var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      let status = getnameinfo(
        socketAddress,
        info.ai_addrlen,
        &hostBuffer,
        socklen_t(hostBuffer.count),
        nil,
        0,
        NI_NUMERICHOST
      )
      guard status == 0 else {
        continue
      }
      let terminator = hostBuffer.firstIndex(of: 0) ?? hostBuffer.endIndex
      let addressString = String(
        decoding: hostBuffer[..<terminator].map { UInt8(bitPattern: $0) },
        as: UTF8.self
      )
      guard let address = ResolvedIPAddress(addressString) else {
        continue
      }
      addresses.insert(address)
    }

    guard !addresses.isEmpty else {
      throw HostResolutionError.failed
    }
    return Array(addresses)
  }
}

private enum HostResolutionError: Error, Sendable {
  case failed
}
