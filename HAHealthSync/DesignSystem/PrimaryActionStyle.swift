import SwiftUI

extension View {
  /// The app's prominent button: a near-black (light) or near-white (dark) fill with an
  /// inverted label.
  @ViewBuilder
  func primaryActionStyle() -> some View {
    let styled =
      self
      .controlSize(.large)
      .modifier(PrimaryActionLabelColor())
      .tint(DesignTokens.primaryActionTint)
    if #available(iOS 26.0, *) {
      styled.buttonStyle(.glassProminent)
    } else {
      styled.buttonStyle(.borderedProminent)
    }
  }

  /// A full-width primary action pinned in a bottom safe-area inset.
  @ViewBuilder
  func primaryActionBar() -> some View {
    if #available(iOS 26.0, *) {
      primaryActionStyle().padding()
    } else {
      primaryActionStyle().padding().background(.bar)
    }
  }
}

/// Inverts the label against the accent only while enabled. A disabled prominent button gets a
/// light grey fill in light mode, where an inverted (white) label would be unreadable.
private struct PrimaryActionLabelColor: ViewModifier {
  @Environment(\.isEnabled) private var isEnabled

  func body(content: Content) -> some View {
    content.foregroundStyle(
      isEnabled ? Color(uiColor: .systemBackground) : Color(uiColor: .secondaryLabel))
  }
}

#Preview("Primary action") {
  VStack {
    Button {
    } label: {
      Text("Continue").frame(maxWidth: .infinity)
    }
    .primaryActionStyle()
  }
  .padding()
}
