import Foundation

/// Shared timeout for UI test waits that assert an element **should** appear.
///
/// The suite's original per-call timeouts (2-3s) were tuned for an idle machine.
/// On a busy machine, an app launch or navigation transition can easily exceed
/// that budget, producing cascading false failures at unrelated assertions even
/// though every affected test passes in isolation. Centralizing on one generous
/// timeout makes presence waits resilient to machine load.
///
/// This does not apply to waits that assert absence (`XCTAssertFalse(...waitForExistence...)`)
/// or to timeouts deliberately tuned to a specific behavior under test — those stay
/// as short as the behavior they verify requires.
enum UITestWait {
  static let standard: TimeInterval = 10
}
