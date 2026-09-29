import Foundation

public enum MetricFreshnessStoreError: Error, Equatable, Sendable {
  case unsupportedVersion
  case corruptedData
}

public struct MetricFreshnessSnapshot: Codable, Sendable, Equatable {
  public var lastCheckedAt: [MetricID: Date]
  public var lastSentAt: [MetricID: Date]
  public var lastFullSweepAt: Date?
  public var rotationOffset: Int

  public init(
    lastCheckedAt: [MetricID: Date] = [:],
    lastSentAt: [MetricID: Date] = [:],
    lastFullSweepAt: Date? = nil,
    rotationOffset: Int = 0
  ) {
    self.lastCheckedAt = lastCheckedAt
    self.lastSentAt = lastSentAt
    self.lastFullSweepAt = lastFullSweepAt
    self.rotationOffset = rotationOffset
  }

  /// Applies everything one run changed, so the store can write the result once.
  public mutating func apply(_ update: MetricFreshnessUpdate) {
    for metric in update.checked { lastCheckedAt[metric] = update.at }
    for metric in update.sent { lastSentAt[metric] = update.at }
    if let offset = update.rotationOffset { rotationOffset = offset }
    if let completedSweepAt = update.completedSweepAt { lastFullSweepAt = completedSweepAt }
    lastCheckedAt = lastCheckedAt.filter { update.selected.contains($0.key) }
    lastSentAt = lastSentAt.filter { update.selected.contains($0.key) }
  }
}

/// Everything a single run changes about freshness. One run produces one update, which the store
/// applies in one write: three separate writes on the tightest-budget path would cost three
/// encrypted file rewrites, and a failure between them would leave half of the run recorded.
public struct MetricFreshnessUpdate: Sendable, Equatable {
  /// Metrics the run resolved: their value reached Health Bridge, or they genuinely had nothing
  /// to send. A metric the run collected a value for and could not send is not one of them — it
  /// stays stale, because its data has not arrived anywhere yet.
  public var checked: Set<MetricID>
  /// Metrics Health Bridge accepted a value for.
  public var sent: Set<MetricID>
  /// When the run finished. Both sets are recorded at this date.
  public var at: Date
  /// The current selection. Entries for anything outside it are dropped by the same write.
  public var selected: Set<MetricID>
  /// Where the next full sweep starts, or `nil` to leave the offset where it is. A truncated
  /// sweep still moves it, so the next one continues past what this one collected.
  public var rotationOffset: Int?
  /// When the full sweep completed, or `nil` when this run did not complete one.
  public var completedSweepAt: Date?

  public init(
    checked: Set<MetricID> = [],
    sent: Set<MetricID> = [],
    at: Date,
    selected: Set<MetricID>,
    rotationOffset: Int? = nil,
    completedSweepAt: Date? = nil
  ) {
    self.checked = checked
    self.sent = sent
    self.at = at
    self.selected = selected
    self.rotationOffset = rotationOffset
    self.completedSweepAt = completedSweepAt
  }

  /// Whether applying this update to `snapshot` would change anything, so a run that learned
  /// nothing can skip the write. A locked-device wake checks nothing, sends nothing, rotates
  /// nothing and sweeps nothing; writing it would cost an encrypted read-modify-write for a
  /// document that ends up identical, on the tightest-budget path there is.
  public func changes(_ snapshot: MetricFreshnessSnapshot) -> Bool {
    var applied = snapshot
    applied.apply(self)
    return applied != snapshot
  }
}

public protocol MetricFreshnessStore: Sendable {
  func snapshot() async throws -> MetricFreshnessSnapshot
  /// Applies one run's update in a single write.
  ///
  /// Implementations must record what they are given even when the task is cancelled. A run iOS
  /// cut short has still checked metrics, sent values and moved the rotation offset, and
  /// discarding that would restart the next sweep where this one started — the starvation the
  /// rotation exists to prevent. Nothing here can outlive the run's truth: a cancelled run never
  /// claims a completed sweep, because the coordinator leaves `completedSweepAt` nil for it.
  func record(_ update: MetricFreshnessUpdate) async throws
  func reset() async throws
}

public enum MetricFreshnessCodec: Sendable {
  private static let currentVersion = 1

  public static func encode(_ snapshot: MetricFreshnessSnapshot) throws -> Data {
    let document = Document(
      version: currentVersion,
      lastCheckedAt: Dictionary(
        uniqueKeysWithValues: snapshot.lastCheckedAt.map { ($0.key.rawValue, $0.value) }),
      lastSentAt: Dictionary(
        uniqueKeysWithValues: snapshot.lastSentAt.map { ($0.key.rawValue, $0.value) }),
      lastFullSweepAt: snapshot.lastFullSweepAt,
      rotationOffset: snapshot.rotationOffset
    )
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      encoder.dateEncodingStrategy = .secondsSince1970
      return try encoder.encode(document)
    } catch {
      throw MetricFreshnessStoreError.corruptedData
    }
  }

  public static func decode(_ data: Data) throws -> MetricFreshnessSnapshot {
    do {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .secondsSince1970
      let header = try decoder.decode(Header.self, from: data)
      guard header.version == currentVersion else {
        throw MetricFreshnessStoreError.unsupportedVersion
      }
      let document = try decoder.decode(Document.self, from: data)
      return MetricFreshnessSnapshot(
        lastCheckedAt: try metricKeyed(document.lastCheckedAt),
        lastSentAt: try metricKeyed(document.lastSentAt),
        lastFullSweepAt: document.lastFullSweepAt,
        rotationOffset: document.rotationOffset
      )
    } catch let error as MetricFreshnessStoreError {
      throw error
    } catch {
      throw MetricFreshnessStoreError.corruptedData
    }
  }

  private static func metricKeyed(_ raw: [String: Date]) throws -> [MetricID: Date] {
    var result: [MetricID: Date] = [:]
    for (key, value) in raw {
      guard let metric = MetricID(rawValue: key) else {
        throw MetricFreshnessStoreError.corruptedData
      }
      result[metric] = value
    }
    return result
  }

  private struct Header: Decodable {
    let version: Int
  }

  private struct Document: Codable {
    let version: Int
    let lastCheckedAt: [String: Date]
    let lastSentAt: [String: Date]
    let lastFullSweepAt: Date?
    let rotationOffset: Int

    init(
      version: Int,
      lastCheckedAt: [String: Date],
      lastSentAt: [String: Date],
      lastFullSweepAt: Date?,
      rotationOffset: Int
    ) {
      self.version = version
      self.lastCheckedAt = lastCheckedAt
      self.lastSentAt = lastSentAt
      self.lastFullSweepAt = lastFullSweepAt
      self.rotationOffset = rotationOffset
    }

    private enum CodingKeys: String, CodingKey {
      case version
      case lastCheckedAt
      case lastSentAt
      case lastFullSweepAt
      case rotationOffset
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      version = try container.decode(Int.self, forKey: .version)
      lastCheckedAt =
        try container.decodeIfPresent([String: Date].self, forKey: .lastCheckedAt) ?? [:]
      lastSentAt =
        try container.decodeIfPresent([String: Date].self, forKey: .lastSentAt) ?? [:]
      lastFullSweepAt = try container.decodeIfPresent(Date.self, forKey: .lastFullSweepAt)
      rotationOffset = try container.decodeIfPresent(Int.self, forKey: .rotationOffset) ?? 0
    }
  }
}

public actor InMemoryMetricFreshnessStore: MetricFreshnessStore {
  private var storedSnapshot: MetricFreshnessSnapshot

  public init(snapshot: MetricFreshnessSnapshot = MetricFreshnessSnapshot()) {
    storedSnapshot = snapshot
  }

  public func snapshot() -> MetricFreshnessSnapshot {
    storedSnapshot
  }

  public func record(_ update: MetricFreshnessUpdate) {
    storedSnapshot.apply(update)
  }

  public func reset() throws {
    try Task.checkCancellation()
    storedSnapshot = MetricFreshnessSnapshot()
  }
}
