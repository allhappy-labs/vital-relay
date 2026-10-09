import Foundation

public enum ArchiveProgress {
  /// Per-type progress from committed checkpoint state only. `coverage` and `scanned` both hold
  /// windows whose batches Home Assistant acknowledged, so their union is archived time.
  /// During a run, pass the run's scan end as `now`.
  public static func make(checkpoint: ArchiveImportCheckpoint, now: Date)
    -> [HealthObjectTypeID: ArchiveTypeProgress]
  {
    progress(checkpoint: checkpoint) { _ in now }
  }

  /// Progress for a checkpoint restored after relaunch. Each type is measured against the end of
  /// its last run (its scan window, or its archived time), so a finished archive still reads
  /// complete days later. A type no run has reached yet is measured against `now`.
  public static func restored(checkpoint: ArchiveImportCheckpoint, now: Date)
    -> [HealthObjectTypeID: ArchiveTypeProgress]
  {
    progress(checkpoint: checkpoint) { type in
      let intervals =
        type.coverage.intervals + type.scanned.intervals + [type.scanInterval].compactMap { $0 }
      return intervals.map(\.end).max() ?? now
    }
  }

  private static func progress(
    checkpoint: ArchiveImportCheckpoint, end: (ArchiveTypeCheckpoint) -> Date
  ) -> [HealthObjectTypeID: ArchiveTypeProgress] {
    guard let selection = checkpoint.selection else { return [:] }
    var metricsByType: [HealthObjectTypeID: [MetricID]] = [:]
    for metric in selection.metrics {
      guard let definition = MetricRegistry[metric] else { continue }
      metricsByType[definition.healthObjectType, default: []].append(metric)
    }
    var result: [HealthObjectTypeID: ArchiveTypeProgress] = [:]
    for (type, metrics) in metricsByType {
      let typeCheckpoint = checkpoint.types[type] ?? ArchiveTypeCheckpoint()
      guard let earliest = metrics.compactMap({ checkpoint.metricEarliestDates[$0] }).min()
      else {
        result[type] = ArchiveTypeProgress(range: nil, fraction: 0, isComplete: false)
        continue
      }
      let start =
        [earliest, selection.requestedStart, typeCheckpoint.observedAuthorizationBoundary]
        .compactMap { $0 }.max() ?? earliest
      let range = DateInterval(start: start, end: max(start, end(typeCheckpoint)))
      var covered = typeCheckpoint.coverage
      for interval in typeCheckpoint.scanned.intervals { covered.insert(interval) }
      let fraction: Double
      if range.duration == 0 {
        fraction = 1
      } else {
        let missing = covered.gaps(in: range).reduce(0) { $0 + $1.duration }
        fraction = min(max(1 - missing / range.duration, 0), 1)
      }
      result[type] = ArchiveTypeProgress(
        range: range, fraction: fraction,
        isComplete: fraction >= 1 && !typeCheckpoint.reconciliationRequired)
    }
    return result
  }
}
