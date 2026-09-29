import Foundation
import Network

public enum TailscaleAddressPolicy {
  public static func isMachineMagicDNSHost(_ host: String) -> Bool {
    let normalized = host.lowercased()
    let labels = normalized.split(separator: ".", omittingEmptySubsequences: false)
    return normalized.hasSuffix(".ts.net")
      && labels.count >= 4
      && labels.allSatisfy { !$0.isEmpty }
  }

  public static func isTailscaleIPAddress(_ address: String) -> Bool {
    let unbracketed = address.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    if let ipv4 = IPv4Address(unbracketed) {
      let bytes = Array(ipv4.rawValue)
      return bytes.count == 4 && bytes[0] == 100 && (bytes[1] & 0xC0) == 64
    }
    if let ipv6 = IPv6Address(unbracketed) {
      let bytes = Array(ipv6.rawValue)
      return bytes.count == 16
        && bytes[0] == 0xFD
        && bytes[1] == 0x7A
        && bytes[2] == 0x11
        && bytes[3] == 0x5C
        && bytes[4] == 0xA1
        && bytes[5] == 0xE0
    }
    return false
  }
}
