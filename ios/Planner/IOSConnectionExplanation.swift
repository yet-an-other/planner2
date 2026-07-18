import SwiftUI

/// The first-connect explanation sheet.
///
/// Before any Google authorization UI appears, this compact native sheet
/// explains why Planner requests read-only Google Calendar access, assures
/// the user that Planner cannot modify Calendar data, and states the enabled
/// build's actual Calendar-data behavior — connection-only builds download
/// no Calendar data. Continue resumes the same Connect flow; Cancel or
/// dismissing the sheet cancels without opening Google UI. The Privacy
/// Policy action opens the configured HTTPS URL.
struct IOSConnectionExplanation: View {
    /// The configured HTTPS Privacy Policy URL.
    let privacyPolicyURL: URL

    /// Acknowledges the disclosure and resumes Connect.
    let onContinue: () -> Void

    /// Cancels Connect.
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(GoogleAccountConnectionCopy.explanationTitle)
                        .font(.title3.bold())
                        .foregroundStyle(PlannerPalette.ink)

                    Text(GoogleAccountConnectionCopy.explanationBody)
                        .font(.subheadline)
                        .foregroundStyle(PlannerPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Link(destination: privacyPolicyURL) {
                        Label(
                            GoogleAccountConnectionCopy.privacyPolicyAction,
                            systemImage: "safari"
                        )
                        .font(.subheadline.weight(.medium))
                    }
                    .tint(PlannerPalette.olive)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button(
                    GoogleAccountConnectionCopy.explanationCancel,
                    action: onCancel
                )

                Spacer(minLength: 0)

                Button(
                    GoogleAccountConnectionCopy.explanationContinue,
                    action: onContinue
                )
                .buttonStyle(.borderedProminent)
                .tint(PlannerPalette.olive)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PlannerPalette.canvas)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
