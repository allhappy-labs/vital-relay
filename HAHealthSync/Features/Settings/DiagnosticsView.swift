import HealthSyncCore
import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticsView: View {
  @Environment(AppModel.self) private var model

  @State private var document: DiagnosticFileDocument?
  @State private var isExporting = false
  @State private var isPreparing = false
  @State private var preparationFailed = false

  var body: some View {
    Form {
      Section("Included") {
        ForEach(Array(summaryRows.enumerated()), id: \.offset) { _, row in
          LabeledContent(row.label, value: row.value)
        }
      }

      Section {
        Label("Server URLs", systemImage: "link")
        Label("Entity IDs", systemImage: "tag")
        Label("Credentials", systemImage: "key")
        Label("Health values", systemImage: "heart.text.clipboard")
      } header: {
        Text("Never Included")
      } footer: {
        Text(
          "The exported file is limited to the summary above and is redacted again before export."
        )
        .accessibilityIdentifier("diagnostics-privacy-scope")
      }

      Section {
        Button {
          Task { await prepareExport() }
        } label: {
          HStack {
            Spacer()
            if isPreparing {
              ProgressView()
            } else {
              Label("Export Redacted Diagnostics", systemImage: "square.and.arrow.up")
            }
            Spacer()
          }
        }
        .disabled(isPreparing)
        .accessibilityIdentifier("diagnostics-export")
      }

      if preparationFailed || model.currentError != nil {
        Section("Current Issue") {
          Text(currentIssueDescription)
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("Diagnostics")
    .fileExporter(
      isPresented: $isExporting,
      document: document,
      contentType: .json,
      defaultFilename: "ha-health-sync-diagnostics"
    ) { result in
      if case .failure = result {
        preparationFailed = true
      }
      document = nil
    }
  }

  private var summaryRows: [DiagnosticsSummaryRow] {
    let info = Bundle.main.infoDictionary ?? [:]
    let failures =
      (model.lastReport?.failures.map(\.category) ?? [])
      + (model.lastInboundReport?.failures.map(\.category) ?? [])
      + (model.lastBackfillReport?.failures.map(\.category) ?? [])
      + [model.syncStatus.lastFailure?.category, model.currentError].compactMap { $0 }
    let registrationCount = model.syncStatus.registrations.values.filter {
      if case .registered = $0 { return true }
      return false
    }.count

    return DiagnosticsSummary.included(
      DiagnosticsSummaryInput(
        appVersion: info["CFBundleShortVersionString"] as? String ?? "Unknown",
        buildVersion: info["CFBundleVersion"] as? String ?? "Unknown",
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        integrationVersion: model.healthBridgeIntegrationVersion,
        backgroundSyncEnabled: model.backgroundSyncEnabled,
        backgroundSyncFrequency: model.backgroundSyncFrequency,
        historicalImportEnabled: model.experimentalBackfillEnabled,
        medicationSyncEnabled: model.medicationSyncEnabled,
        selectedMetricCount: model.selectedMetricCount,
        pairingCount: model.pairings.count,
        registrationCount: registrationCount,
        recentEventCount: model.syncStatus.recentEvents.count,
        lastAttemptedAt: model.syncStatus.lastAttemptedAt,
        lastSuccessfulAt: model.syncStatus.lastSuccessfulAt,
        failureCategories: failures
      )
    )
  }

  private var currentIssueDescription: String {
    if preparationFailed {
      return "Diagnostics could not be prepared."
    }
    guard let currentError = model.currentError else { return "No current issue." }
    return "The app most recently reported a \(currentError.rawValue) error."
  }

  private func prepareExport() async {
    isPreparing = true
    defer { isPreparing = false }
    do {
      let info = Bundle.main.infoDictionary ?? [:]
      let text = try await model.diagnosticsText(
        appVersion: info["CFBundleShortVersionString"] as? String ?? "Unknown",
        buildVersion: info["CFBundleVersion"] as? String ?? "Unknown",
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString
      )
      document = DiagnosticFileDocument(text: text)
      preparationFailed = false
      isExporting = true
    } catch {
      preparationFailed = true
    }
  }
}

private struct DiagnosticFileDocument: FileDocument {
  static let readableContentTypes: [UTType] = [.json]

  let text: String

  init(text: String) {
    self.text = text
  }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents,
      let text = String(data: data, encoding: .utf8)
    else { throw DiagnosticFileDocumentError.invalidData }
    self.text = text
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    guard let data = text.data(using: .utf8) else {
      throw DiagnosticFileDocumentError.invalidData
    }
    return FileWrapper(regularFileWithContents: data)
  }
}

private enum DiagnosticFileDocumentError: Error {
  case invalidData
}
