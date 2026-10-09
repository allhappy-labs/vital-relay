import SwiftUI

enum StepGoal {
  static let target: Double = 10_000

  static func progress(_ steps: Double) -> Double {
    min(max(steps / target, 0), 1)
  }

  static func percentText(_ steps: Double) -> String {
    let percent = Int((progress(steps) * 100).rounded(.down))
    return "\(percent)% of \(Int(target).formatted(.number.locale(Locale(identifier: "en_US"))))"
  }
}

struct GoalRing: View {
  let progress: Double
  let tint: Color

  var body: some View {
    ZStack {
      Circle().stroke(tint.opacity(0.2), lineWidth: 5)
      Circle()
        .trim(from: 0, to: progress)
        .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }
    .frame(width: 34, height: 34)
    .accessibilityHidden(true)
  }
}

/// A dashboard card: category-tinted title, large rounded value, optional trailing accessory.
/// Title and value stay separate static texts; the UI tests query each one.
struct MetricTile<Accessory: View>: View {
  let title: String
  let value: String
  let tint: Color
  let symbol: String
  /// Extra spoken context for the value, such as goal progress. The tile itself is a
  /// non-focusable container, so this has to sit on the value text.
  var valueDescription: String?
  private let accessory: Accessory

  init(
    title: String, value: String, tint: Color, symbol: String,
    valueDescription: String? = nil,
    @ViewBuilder accessory: () -> Accessory
  ) {
    self.title = title
    self.value = value
    self.tint = tint
    self.symbol = symbol
    self.valueDescription = valueDescription
    self.accessory = accessory()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: symbol)
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
      HStack(alignment: .bottom) {
        Text(value)
          .font(.title2.weight(.semibold))
          .fontDesign(.rounded)
          .monospacedDigit()
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityValue(valueDescription ?? "")
        Spacer(minLength: 4)
        accessory
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
    .background(
      Color(uiColor: .secondarySystemGroupedBackground),
      in: .rect(cornerRadius: DesignTokens.cardCornerRadius - 4)
    )
    .accessibilityElement(children: .contain)
  }
}

extension MetricTile where Accessory == EmptyView {
  init(title: String, value: String, tint: Color, symbol: String) {
    self.init(title: title, value: value, tint: tint, symbol: symbol) { EmptyView() }
  }
}

#Preview("Tiles") {
  LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
    MetricTile(title: "Daily Steps", value: "8,412", tint: .orange, symbol: "figure.walk") {
      GoalRing(progress: 0.84, tint: .orange)
    }
    MetricTile(title: "Flights Climbed", value: "11", tint: .orange, symbol: "stairs")
  }
  .padding()
  .background(Color(uiColor: .systemGroupedBackground))
}
