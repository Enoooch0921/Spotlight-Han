import SwiftUI

/// Presented only after the confirmed writer has returned success. Its animation
/// is local to this appearance; it never schedules writes or auto-dismisses.
struct TaskCreatedFeedback: View {
    let message: String
    @Environment(\.launcherMotionEnabled) private var motionEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32)).foregroundStyle(.green)
                .scaleEffect(!appeared && motionEnabled && !reduceMotion ? 0.97 : 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(L.text("已建立")).font(.title3.weight(.semibold))
                Text(message).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            withAnimation(LauncherMotion.feedback(enabled: motionEnabled, pressed: false)) { appeared = true }
        }
    }
}
