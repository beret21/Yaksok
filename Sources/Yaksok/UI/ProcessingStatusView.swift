import SwiftUI

/// Popover content showing processing status below menu bar icon.
/// Uses TimelineView instead of Timer to avoid timer leaks when NSPopover
/// is dismissed without triggering onDisappear.
struct ProcessingStatusView: View {
    let provider: String
    let model: String

    private let startDate = Date()

    var body: some View {
        TimelineView(.periodic(from: startDate, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(startDate))
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)

                VStack(alignment: .leading, spacing: 2) {
                    Text("분석 중...", comment: "Processing status")
                        .font(.callout.weight(.medium))
                    Text("\(provider) · \(elapsed)초", comment: "Provider and elapsed time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}
