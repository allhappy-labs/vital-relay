import Foundation
import Testing

@testable import HealthSyncCore

@Suite("Archive progress")
struct ArchiveProgressTests {
  private func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }
  private func span(_ start: Double, _ end: Double) -> DateInterval {
    DateInterval(start: at(start), end: at(end))
  }

  private func checkpoint(
    metrics: Set<MetricID> = [.steps], earliest: [MetricID: Double] = [.steps: 100],
    requestedStart: Double? = nil, coverage: [DateInterval] = [], scanned: [DateInterval] = [],
    boundary: Double? = nil, reconciliationRequired: Bool = false
  ) -> ArchiveImportCheckpoint {
    var state = ArchiveImportCheckpoint()
    state.selection = ArchiveImportSelection(
      metrics: metrics, requestedStart: requestedStart.map(at))
    state.metricEarliestDates = earliest.mapValues(at)
    var type = ArchiveTypeCheckpoint()
    for interval in coverage { type.coverage.insert(interval) }
    for interval in scanned { type.scanned.insert(interval) }
    type.observedAuthorizationBoundary = boundary.map(at)
    type.reconciliationRequired = reconciliationRequired
    if let metric = metrics.first, let definition = MetricRegistry[metric] {
      state.types[definition.healthObjectType] = type
    }
    return state
  }

  @Test func halfCoveredRangeIsHalfDone() {
    let progress = ArchiveProgress.make(
      checkpoint: checkpoint(coverage: [span(100, 150)]), now: at(200))
    #expect(progress[.stepCount]?.range == span(100, 200))
    #expect(progress[.stepCount]?.fraction == 0.5)
    #expect(progress[.stepCount]?.isComplete == false)
  }

  @Test func coverageAndScannedAreUnioned() {
    let progress = ArchiveProgress.make(
      checkpoint: checkpoint(coverage: [span(100, 140)], scanned: [span(130, 160)]),
      now: at(200))
    #expect(progress[.stepCount]?.fraction == 0.6)
  }

  @Test func requestedStartClipsTheRange() {
    let progress = ArchiveProgress.make(
      checkpoint: checkpoint(requestedStart: 150, coverage: [span(100, 175)]), now: at(200))
    #expect(progress[.stepCount]?.range == span(150, 200))
    #expect(progress[.stepCount]?.fraction == 0.5)
  }

  @Test func laterAuthorizationBoundaryStartsTheRange() {
    let progress = ArchiveProgress.make(
      checkpoint: checkpoint(boundary: 180), now: at(200))
    #expect(progress[.stepCount]?.range == span(180, 200))
  }

  @Test func fullyCoveredTypeIsCompleteUnlessReconciliationIsRequired() {
    let done = ArchiveProgress.make(
      checkpoint: checkpoint(coverage: [span(100, 200)]), now: at(200))
    #expect(done[.stepCount]?.isComplete == true)
    let pending = ArchiveProgress.make(
      checkpoint: checkpoint(coverage: [span(100, 200)], reconciliationRequired: true),
      now: at(200))
    #expect(pending[.stepCount]?.fraction == 1)
    #expect(pending[.stepCount]?.isComplete == false)
  }

  @Test func zeroLengthRangeCountsAsDone() {
    let progress = ArchiveProgress.make(
      checkpoint: checkpoint(earliest: [.steps: 200]), now: at(200))
    #expect(progress[.stepCount]?.fraction == 1)
  }

  @Test func typeWithoutReadableMetricsHasNoRange() {
    let progress = ArchiveProgress.make(checkpoint: checkpoint(earliest: [:]), now: at(200))
    #expect(progress[.stepCount]?.range == nil)
    #expect(progress[.stepCount]?.fraction == 0)
  }

  @Test func sharedTypeUsesItsEarliestMetric() {
    let progress = ArchiveProgress.make(
      checkpoint: checkpoint(
        metrics: [.sleepDuration, .sleepREM], earliest: [.sleepDuration: 150, .sleepREM: 100]),
      now: at(200))
    #expect(progress.count == 1)
    #expect(progress[.sleepAnalysis]?.range == span(100, 200))
  }

  @Test func overallIsMeanOfReadableTypes() {
    var report = ArchiveImportReport()
    report.typeProgress = [
      .stepCount: .init(range: span(0, 1), fraction: 1, isComplete: true),
      .bodyMass: .init(range: span(0, 1), fraction: 0.5, isComplete: false),
      .sleepAnalysis: .init(range: nil, fraction: 0, isComplete: false),
    ]
    #expect(report.overallFraction == 0.75)
  }

  @Test func overallIsNilWithoutReadableTypes() {
    var report = ArchiveImportReport()
    report.typeProgress = [.stepCount: .init(range: nil, fraction: 0, isComplete: false)]
    #expect(report.overallFraction == nil)
  }

  @Test func noSelectionMeansNoProgress() {
    #expect(ArchiveProgress.make(checkpoint: ArchiveImportCheckpoint(), now: at(200)).isEmpty)
  }

  @Test func restoredCompletedTypeStaysCompleteLongAfterItsRun() {
    let progress = ArchiveProgress.restored(
      checkpoint: checkpoint(coverage: [span(100, 200)]), now: at(5000))
    #expect(progress[.stepCount]?.fraction == 1)
    #expect(progress[.stepCount]?.isComplete == true)
  }

  @Test func restoredPausedTypeMeasuresAgainstItsRunEnd() {
    var state = checkpoint(coverage: [span(100, 150)])
    state.types[.stepCount]?.scanInterval = span(150, 200)
    let progress = ArchiveProgress.restored(checkpoint: state, now: at(5000))
    #expect(progress[.stepCount]?.fraction == 0.5)
  }

  @Test func restoredUnstartedTypeUsesTheCurrentTime() {
    let progress = ArchiveProgress.restored(checkpoint: checkpoint(), now: at(5000))
    #expect(progress[.stepCount]?.range == span(100, 5000))
    #expect(progress[.stepCount]?.fraction == 0)
  }
}
