import HealthSyncCore
import Observation
import StoreKit

#if OWNER_UNLOCK && !DEBUG
  #error("OWNER_UNLOCK is only permitted in Debug builds")
#endif

/// Minimal verified metadata. Receipts and signed payloads never leave the live client.
struct LifetimeTransaction: Sendable {
  let id: UInt64
  let productID: String
  let revoked: Bool
}

enum LifetimePurchaseResult: Sendable {
  case verified(LifetimeTransaction)
  case unverified
  case cancelled
  case pending
}

enum PurchaseOutcome: Sendable, Equatable {
  case purchased
  case cancelled
  case pending
  case unverified
  case unavailable
}

@MainActor
protocol LifetimeUnlockPresenting: AnyObject {
  var state: PaidAccessState { get }
  var displayPrice: String? { get }
  var isDeveloperAccess: Bool { get }
  func load() async
  func purchase() async -> PurchaseOutcome
  func restore() async throws
}

extension LifetimeUnlockPresenting {
  var isDeveloperAccess: Bool { false }
}

@MainActor
protocol LifetimeStoreKitClient {
  associatedtype StoreProduct: LifetimeStoreProduct
  var updates: AsyncStream<LifetimePurchaseResult> { get }
  func products(for ids: [String]) async throws -> [StoreProduct]
  func currentEntitlements() async -> [LifetimeTransaction]
  func purchase(_ product: StoreProduct) async throws -> LifetimePurchaseResult
  func sync() async throws
  func finish(_ id: UInt64) async
}

protocol LifetimeStoreProduct: Sendable {
  var id: String { get }
  var type: Product.ProductType { get }
  var displayPrice: String { get }
}

extension Product: LifetimeStoreProduct {}

typealias StoreKitLifetimeUnlock = LifetimeUnlockAuthority<LiveLifetimeStoreKitClient>

@MainActor
@Observable
final class LifetimeUnlockAuthority<Client: LifetimeStoreKitClient> {
  static var productID: String { "com.marynavdovenko.HAHealthSync.lifetimeUnlock" }

  private(set) var product: Client.StoreProduct?
  private(set) var state: PaidAccessState = .checking {
    didSet {
      if oldValue != state { onAccessChanged?() }
    }
  }
  @ObservationIgnored var onAccessChanged: (@MainActor () -> Void)?
  private let client: Client
  @ObservationIgnored private var updatesTask: Task<Void, Never>?
  private var revision = 0

  var access: any PaidFeatureAccessing { LifetimeAccessAdapter(authority: self) }

  init(client: Client) {
    self.client = client
    let updates = client.updates
    updatesTask = Task { [weak self] in
      for await result in updates {
        guard !Task.isCancelled else { return }
        await self?.receive(result)
      }
    }
  }

  deinit { updatesTask?.cancel() }

  func load() async {
    do {
      product = try await client.products(for: [Self.productID])
        .first { $0.id == Self.productID && $0.type == .nonConsumable }
    } catch {
      product = nil
    }
    await refreshEntitlements()
  }

  func purchase() async -> PurchaseOutcome {
    guard let product else { return .unavailable }
    do {
      let result = try await client.purchase(product)
      await receive(result)
      switch result {
      case .verified(let transaction):
        return transaction.productID == Self.productID && !transaction.revoked
          ? .purchased : .unverified
      case .cancelled: return .cancelled
      case .pending: return .pending
      case .unverified: return .unverified
      }
    } catch {
      // A store error is not evidence that an existing purchase was revoked.
      return .unavailable
    }
  }

  /// Only an explicit foreground Restore Purchases action may call this method.
  func restore() async throws {
    try await client.sync()
    await load()
  }

  fileprivate func refreshEntitlements() async {
    let expectedRevision = revision
    let entitlements = await client.currentEntitlements()
    guard revision == expectedRevision else { return }
    state =
      entitlements.contains { $0.productID == Self.productID && !$0.revoked }
      ? .unlocked : (product == nil ? .unavailable : .locked)
  }

  private func receive(_ result: LifetimePurchaseResult) async {
    switch result {
    case .verified(let transaction):
      guard transaction.productID == Self.productID else { return }
      revision += 1
      state = transaction.revoked ? .locked : .unlocked
      await client.finish(transaction.id)
    case .unverified:
      revision += 1
      state = .unavailable
    case .cancelled, .pending:
      break
    }
  }
}

extension LifetimeUnlockAuthority: LifetimeUnlockPresenting {
  var displayPrice: String? { product?.displayPrice }
}

extension LifetimeUnlockAuthority where Client == LiveLifetimeStoreKitClient {
  convenience init() { self.init(client: LiveLifetimeStoreKitClient()) }
}

#if DEBUG
  /// Explicitly selected for a locally installed owner build. Never compiled into Release.
  @MainActor
  final class DeveloperLifetimeUnlock: LifetimeUnlockPresenting {
    let state: PaidAccessState = .unlocked
    let displayPrice: String? = nil
    let isDeveloperAccess = true
    var onAccessChanged: (@MainActor () -> Void)?
    var access: any PaidFeatureAccessing { DeveloperPaidAccess() }

    func load() async {}
    func purchase() async -> PurchaseOutcome { .unavailable }
    func restore() async throws {}
  }

  private struct DeveloperPaidAccess: PaidFeatureAccessing {
    func accessState() async -> PaidAccessState { .unlocked }
  }
#endif

private struct LifetimeAccessAdapter<Client: LifetimeStoreKitClient>: PaidFeatureAccessing {
  let authority: LifetimeUnlockAuthority<Client>

  @MainActor func accessState() async -> PaidAccessState {
    await authority.refreshEntitlements()
    return authority.state
  }
}

@MainActor
final class LiveLifetimeStoreKitClient: LifetimeStoreKitClient {
  let updates: AsyncStream<LifetimePurchaseResult>
  private var listener: Task<Void, Never>?
  private var unfinished: [UInt64: Transaction] = [:]

  init() {
    let (stream, continuation) = AsyncStream<LifetimePurchaseResult>.makeStream()
    updates = stream
    listener = Task { [weak self] in
      defer { continuation.finish() }
      for await result in Transaction.updates {
        guard !Task.isCancelled else { return }
        guard let self else { return }
        // Ignore updates for other products, including their unverified payloads.
        guard result.unsafePayloadValue.productID == StoreKitLifetimeUnlock.productID else {
          continue
        }
        continuation.yield(verifiedResult(result))
      }
    }
  }

  deinit { listener?.cancel() }

  func products(for ids: [String]) async throws -> [Product] {
    try await Product.products(for: ids)
  }

  func currentEntitlements() async -> [LifetimeTransaction] {
    var entitlements: [LifetimeTransaction] = []
    for await result in Transaction.currentEntitlements {
      guard case .verified(let transaction) = result else { continue }
      entitlements.append(Self.metadata(transaction))
    }
    return entitlements
  }

  func purchase(_ product: Product) async throws -> LifetimePurchaseResult {
    switch try await product.purchase() {
    case .success(let result): return verifiedResult(result)
    case .userCancelled: return .cancelled
    case .pending: return .pending
    @unknown default: return .unverified
    }
  }

  func sync() async throws { try await AppStore.sync() }

  func finish(_ id: UInt64) async {
    guard let transaction = unfinished.removeValue(forKey: id) else { return }
    await transaction.finish()
  }

  private func verifiedResult(_ result: VerificationResult<Transaction>) -> LifetimePurchaseResult {
    guard case .verified(let transaction) = result else { return .unverified }
    unfinished[transaction.id] = transaction
    return .verified(Self.metadata(transaction))
  }

  private static func metadata(_ transaction: Transaction) -> LifetimeTransaction {
    LifetimeTransaction(
      id: transaction.id, productID: transaction.productID,
      revoked: transaction.revocationDate != nil)
  }
}
