import SwiftUI

/// Shows the first sentence of an explanation and expands the rest inline. Inline expansion,
/// not a sheet, because list footers are recycled and a sheet anchored there can detach.
struct InfoFooter: View {
  let summary: String
  var details: String?
  var identifier: String?
  @State private var isExpanded = false

  init(_ summary: String, details: String? = nil, identifier: String? = nil) {
    self.summary = summary
    self.details = details
    self.identifier = identifier
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(summary)
        .accessibilityIdentifier(ifPresent: identifier)
      if let details {
        if isExpanded {
          Text(details)
            .transition(.opacity)
        }
        Button(isExpanded ? "Show less" : "Learn more") {
          withAnimation(.snappy) { isExpanded.toggle() }
        }
        .font(.footnote.weight(.semibold))
        .buttonStyle(.borderless)
      }
    }
  }
}

#Preview("InfoFooter") {
  List {
    Section {
      Text("Row")
    } footer: {
      InfoFooter(
        "The selected interval is a requested best-effort cadence.",
        details: "iOS decides when background work actually runs.")
    }
  }
}
