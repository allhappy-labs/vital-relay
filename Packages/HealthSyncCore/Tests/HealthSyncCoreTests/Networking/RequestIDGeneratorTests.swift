import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Health Bridge request IDs")
struct RequestIDGeneratorTests {
  private let uuid = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!

  @Test("Live ID is lowercase, bounded, and protocol-safe")
  func liveID() throws {
    let generator = RequestIDGenerator(uuidProvider: { uuid })
    let requestID = generator.live()

    #expect(requestID == "live.01234567-89ab-cdef-0123-456789abcdef")
    #expect(requestID.count <= 64)
    #expect(
      requestID.range(
        of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$",
        options: .regularExpression
      ) != nil
    )
  }

  @Test("Connection-test ID uses a distinct prefix")
  func connectionTestID() {
    let generator = RequestIDGenerator(uuidProvider: { uuid })

    #expect(generator.connectionTest() == "test.01234567-89ab-cdef-0123-456789abcdef")
  }
}
