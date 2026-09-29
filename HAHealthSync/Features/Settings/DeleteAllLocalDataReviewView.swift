import SwiftUI

struct DeleteAllLocalDataReviewView: View {
  var body: some View {
    DestructiveActionReviewView(
      presentation: .deleteAll,
      actionIdentifier: "delete-all-data",
      scopeIdentifier: "delete-all-scope-description"
    ) { model in
      await model.deleteAllLocalApplicationData()
      return "All local app data was deleted."
    }
  }
}
