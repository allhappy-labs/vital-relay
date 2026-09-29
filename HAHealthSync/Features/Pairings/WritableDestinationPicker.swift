import HealthSyncCore
import SwiftUI

struct WritableDestinationPicker: View {
  @Binding var selection: HealthObjectTypeID

  var body: some View {
    Picker("Health destination", selection: $selection) {
      ForEach(WritableHealthRegistry.all) { destination in
        Text(destination.displayName).tag(destination.id)
      }
    }
    .accessibilityIdentifier("pairing-destination")
  }
}
