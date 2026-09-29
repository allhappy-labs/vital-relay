import HealthSyncCore
import StoreKit
import XCTest

@testable import HAHealthSync

@MainActor
final class StoreKitLifetimeUnlockTests: XCTestCase {
  private let productID = "com.marynavdovenko.HAHealthSync.lifetimeUnlock"

  func testDeveloperAccessUnlocksWithoutAStoreKitTransaction() async {
    let subject = DeveloperLifetimeUnlock()

    XCTAssertEqual(subject.state, .unlocked)
    XCTAssertTrue(subject.isDeveloperAccess)
    XCTAssertNil(subject.displayPrice)
    let access = await subject.access.accessState()
    let purchase = await subject.purchase()
    XCTAssertEqual(access, .unlocked)
    XCTAssertEqual(purchase, .unavailable)
  }

  func testDefaultBuildKeepsStoreKitAsThePurchaseAuthority() {
    #if OWNER_UNLOCK
      XCTAssertTrue(AppRuntime.lifetimeUnlock.isDeveloperAccess)
    #else
      XCTAssertFalse(AppRuntime.lifetimeUnlock.isDeveloperAccess)
    #endif
  }

  func testEffectiveAccessChangesNotifySchedulingIncludingRefund() async {
    let client = FakeLifetimeStoreKitClient()
    let subject = LifetimeUnlockAuthority(client: client)
    var states: [PaidAccessState] = []
    subject.onAccessChanged = { states.append(subject.state) }
    await subject.load()
    client.entitlements = [.init(id: 1, productID: productID, revoked: false)]
    _ = await subject.access.accessState()
    _ = await subject.access.accessState()
    client.continuation.yield(.verified(.init(id: 1, productID: productID, revoked: true)))
    for _ in 0..<100 where states.last != .locked { await Task.yield() }
    XCTAssertEqual(states, [.unavailable, .unlocked, .locked])
    subject.onAccessChanged = nil
  }

  func testVerifiedPurchaseUnlocksAndFinishes() async throws {
    let client = try await clientWithProduct()
    client.result = .verified(.init(id: 42, productID: productID, revoked: false))
    let subject = LifetimeUnlockAuthority(client: client)
    await subject.load()
    let outcome = await subject.purchase()
    XCTAssertEqual(outcome, .purchased)
    XCTAssertEqual(subject.state, .unlocked)
    XCTAssertEqual(client.finished, [42])
    let access = await subject.access.accessState()
    XCTAssertEqual(access, .unlocked)
  }

  func testExplicitRestoreRefreshesEntitlement() async throws {
    let client = FakeLifetimeStoreKitClient()
    let subject = LifetimeUnlockAuthority(client: client)
    await subject.load()
    XCTAssertEqual(client.syncCount, 0)
    client.afterSync = [.init(id: 1, productID: productID, revoked: false)]
    try await subject.restore()
    XCTAssertEqual(client.syncCount, 1)
    XCTAssertEqual(subject.state, .unlocked)
  }

  func testCancellationPendingAndUnverifiedDoNotUnlockOrFinish() async throws {
    let cases: [(LifetimePurchaseResult, PurchaseOutcome)] = [
      (.cancelled, .cancelled), (.pending, .pending), (.unverified, .unverified),
    ]
    for (result, expected) in cases {
      let client = try await clientWithProduct()
      client.result = result
      let subject = LifetimeUnlockAuthority(client: client)
      await subject.load()
      let outcome = await subject.purchase()
      XCTAssertEqual(outcome, expected)
      XCTAssertNotEqual(subject.state, .unlocked)
      XCTAssertTrue(client.finished.isEmpty)
    }
  }

  func testOnlyVerifiedExactNonRevokedEntitlementUnlocks() async {
    for entry in [
      LifetimeTransaction(id: 1, productID: productID + ".other", revoked: false),
      LifetimeTransaction(id: 2, productID: productID, revoked: true),
    ] {
      let client = FakeLifetimeStoreKitClient()
      client.entitlements = [entry]
      let subject = LifetimeUnlockAuthority(client: client)
      await subject.load()
      XCTAssertNotEqual(subject.state, .unlocked)
    }
  }

  func testOfflineProductLookupPreservesVerifiedAccess() async {
    let client = FakeLifetimeStoreKitClient()
    client.productError = URLError(.notConnectedToInternet)
    client.entitlements = [.init(id: 1, productID: productID, revoked: false)]
    let subject = LifetimeUnlockAuthority(client: client)
    await subject.load()
    XCTAssertEqual(subject.state, .unlocked)
    XCTAssertNil(subject.product)
    XCTAssertEqual(client.syncCount, 0)
  }

  func testForegroundReloadRecoversProductWithoutRestorePrompt() async {
    let client = FakeLifetimeStoreKitClient()
    client.productError = URLError(.notConnectedToInternet)
    let subject = LifetimeUnlockAuthority(client: client)
    await subject.load()
    XCTAssertEqual(subject.state, .unavailable)
    client.productError = nil
    client.products = [.init(id: productID, type: .nonConsumable)]
    let presenting: any LifetimeUnlockPresenting = subject
    await presenting.load()
    XCTAssertEqual(subject.state, .locked)
    XCTAssertEqual(presenting.displayPrice, "CHF 9.00")
    XCTAssertEqual(client.syncCount, 0)
    XCTAssertEqual(client.purchaseCount, 0)
  }

  func testAccessAdapterRechecksRevocationWithoutAnUpdate() async {
    let client = FakeLifetimeStoreKitClient()
    client.entitlements = [.init(id: 1, productID: productID, revoked: false)]
    let subject = LifetimeUnlockAuthority(client: client)
    await subject.load()
    XCTAssertEqual(subject.state, .unlocked)
    client.entitlements = []
    let state = await subject.access.accessState()
    XCTAssertNotEqual(state, .unlocked)
    XCTAssertEqual(client.syncCount, 0)
  }

  func testWrongProductPurchaseIsNotFinishedOrGranted() async throws {
    let client = try await clientWithProduct()
    client.result = .verified(.init(id: 42, productID: "other", revoked: false))
    let subject = LifetimeUnlockAuthority(client: client)
    await subject.load()
    let outcome = await subject.purchase()
    XCTAssertEqual(outcome, .unverified)
    XCTAssertEqual(subject.state, .locked)
    XCTAssertTrue(client.finished.isEmpty)
  }

  func testUnavailableProductDoesNotOfferOrAttemptPurchase() async {
    let client = FakeLifetimeStoreKitClient()
    let subject = LifetimeUnlockAuthority(client: client)
    await subject.load()
    XCTAssertEqual(subject.state, .unavailable)
    let outcome = await subject.purchase()
    XCTAssertEqual(outcome, .unavailable)
    XCTAssertEqual(client.purchaseCount, 0)
    XCTAssertEqual(client.requestedIDs, [productID])
  }

  func testOtherProductAndConsumableAreNotOffered() async {
    let client = FakeLifetimeStoreKitClient()
    client.products = [
      .init(id: "other", type: .nonConsumable),
      .init(id: productID, type: .consumable),
    ]
    let subject = LifetimeUnlockAuthority(client: client)
    await subject.load()
    XCTAssertNil(subject.product)
    XCTAssertEqual(subject.state, .unavailable)
    let outcome = await subject.purchase()
    XCTAssertEqual(outcome, .unavailable)
    XCTAssertEqual(client.purchaseCount, 0)
  }

  func testUpdatesUnlockAndRefundRemovesAccess() async {
    let client = FakeLifetimeStoreKitClient()
    let subject = LifetimeUnlockAuthority(client: client)
    await subject.load()
    let unlocked = expectation(description: "Verified update grants access")
    subject.onAccessChanged = { if subject.state == .unlocked { unlocked.fulfill() } }
    client.continuation.yield(.verified(.init(id: 1, productID: productID, revoked: false)))
    await fulfillment(of: [unlocked], timeout: 2)
    XCTAssertEqual(subject.state, .unlocked)
    let revoked = expectation(description: "Revoked update removes access")
    subject.onAccessChanged = { if subject.state == .locked { revoked.fulfill() } }
    client.continuation.yield(.verified(.init(id: 1, productID: productID, revoked: true)))
    await fulfillment(of: [revoked], timeout: 2)
    XCTAssertNotEqual(subject.state, .unlocked)
    subject.onAccessChanged = nil
  }

  func testUnverifiedUpdateFailsClosedAndOtherProductIsIgnored() async {
    let client = FakeLifetimeStoreKitClient()
    client.entitlements = [.init(id: 1, productID: productID, revoked: false)]
    let subject = LifetimeUnlockAuthority(client: client)
    await subject.load()
    let invalidated = expectation(description: "Unverified update fails closed")
    var observedStates: [PaidAccessState] = []
    subject.onAccessChanged = {
      observedStates.append(subject.state)
      if subject.state == .unavailable { invalidated.fulfill() }
    }
    client.continuation.yield(.verified(.init(id: 2, productID: "other", revoked: true)))
    client.continuation.yield(.unverified)
    await fulfillment(of: [invalidated], timeout: 2)
    XCTAssertEqual(observedStates, [.unavailable])
    XCTAssertNotEqual(subject.state, .unlocked)
    subject.onAccessChanged = nil
  }

  func testStoreErrorsAndTransactionsDoNotWriteAppPersistence() async throws {
    let client = try await clientWithProduct()
    let subject = LifetimeUnlockAuthority(client: client)
    let before = try persistedAppData()
    let defaultsBefore =
      UserDefaults.standard.persistentDomain(
        forName: try XCTUnwrap(Bundle.main.bundleIdentifier)) as NSDictionary?
    await subject.load()
    client.result = .verified(.init(id: 42, productID: productID, revoked: false))
    _ = await subject.purchase()
    client.productError = NSError(
      domain: "test", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "receipt=private health=123 token=secret"])
    await subject.load()
    try await subject.restore()
    XCTAssertTrue(try persistedAppData() == before)
    let defaultsAfter =
      UserDefaults.standard.persistentDomain(
        forName: try XCTUnwrap(Bundle.main.bundleIdentifier)) as NSDictionary?
    XCTAssertTrue(defaultsBefore == defaultsAfter)
  }

  private func persistedAppData() throws -> [String: Data] {
    let manager = FileManager.default
    let directory = try XCTUnwrap(
      manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    ).appending(path: "com.olhapi.HAHealthSync")
    guard
      let files = manager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
    else { return [:] }
    var snapshot: [String: Data] = [:]
    for case let url as URL in files {
      if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
        snapshot[url.path] = try Data(contentsOf: url)
      }
    }
    return snapshot
  }

  private func clientWithProduct() async throws -> FakeLifetimeStoreKitClient {
    let client = FakeLifetimeStoreKitClient()
    client.products = [.init(id: productID, type: .nonConsumable)]
    return client
  }
}

@MainActor
private final class FakeLifetimeStoreKitClient: LifetimeStoreKitClient {
  var products: [FakeLifetimeProduct] = []
  var entitlements: [LifetimeTransaction] = []
  var afterSync: [LifetimeTransaction] = []
  var productError: Error?
  var result: LifetimePurchaseResult = .cancelled
  var requestedIDs: [String] = []
  var finished: [UInt64] = []
  var syncCount = 0
  var purchaseCount = 0
  let updates: AsyncStream<LifetimePurchaseResult>
  let continuation: AsyncStream<LifetimePurchaseResult>.Continuation

  init() { (updates, continuation) = AsyncStream.makeStream() }
  func products(for ids: [String]) async throws -> [FakeLifetimeProduct] {
    requestedIDs = ids
    if let productError { throw productError }
    return products
  }
  func currentEntitlements() async -> [LifetimeTransaction] { entitlements }
  func purchase(_ product: FakeLifetimeProduct) async throws -> LifetimePurchaseResult {
    purchaseCount += 1
    if case .verified(let transaction) = result { entitlements = [transaction] }
    return result
  }
  func sync() async throws {
    syncCount += 1
    entitlements = afterSync
  }
  func finish(_ id: UInt64) async { finished.append(id) }
}

private struct FakeLifetimeProduct: LifetimeStoreProduct {
  let id: String
  let type: Product.ProductType
  var displayPrice: String { "CHF 9.00" }
}
