import SwiftUI

/// An iPhone Settings-style rounded square holding a white symbol.
struct IconTile: View {
  let systemImage: String
  let tint: Color
  @ScaledMetric(relativeTo: .body) private var size = DesignTokens.iconTileSize

  init(systemImage: String, tint: Color) {
    self.systemImage = systemImage
    self.tint = tint
  }

  var body: some View {
    Image(systemName: systemImage)
      .font(.system(size: size * 0.55, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(tint.gradient, in: .rect(cornerRadius: DesignTokens.tileCornerRadius))
      .accessibilityHidden(true)
  }
}

/// A `Label` with an icon tile. As a native label, list separators align to its text.
struct TileLabel: View {
  let title: String
  var subtitle: String?
  let systemImage: String
  let tint: Color
  var identifier: String?

  init(
    _ title: String, subtitle: String? = nil, systemImage: String, tint: Color,
    identifier: String? = nil
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    self.identifier = identifier
  }

  var body: some View {
    Label {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .accessibilityIdentifier(ifPresent: identifier.map { "\($0)-title" })
        if let subtitle {
          Text(subtitle)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(ifPresent: identifier.map { "\($0)-subtitle" })
        }
      }
    } icon: {
      IconTile(systemImage: systemImage, tint: tint)
    }
  }
}

extension View {
  /// Applies an accessibility identifier only when one is given.
  @ViewBuilder
  func accessibilityIdentifier(ifPresent identifier: String?) -> some View {
    if let identifier {
      accessibilityIdentifier(identifier)
    } else {
      self
    }
  }
}

#Preview("TileLabel") {
  List {
    TileLabel("Background Sync", systemImage: "arrow.triangle.2.circlepath", tint: .green)
    TileLabel(
      "Home Assistant Connection", subtitle: "homeassistant.local", systemImage: "house.fill",
      tint: .blue)
    Toggle(isOn: .constant(true)) {
      TileLabel("Steps", systemImage: "flame.fill", tint: .orange)
    }
  }
}
