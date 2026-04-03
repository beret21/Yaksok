import SwiftUI
import EventKit

/// 24-hour vertical timeline showing existing events and the new event being registered.
/// Displays conflict awareness — not conflict resolution.
struct DayTimelineView: View {
    let existingEvents: [EKEvent]
    let newStart: Date
    let newEnd: Date
    let isAllDay: Bool

    private let existingColor = Color.gray.opacity(0.35)
    private let existingTextColor = Color.primary.opacity(0.7)
    private let newEventGreen = Color.green.opacity(0.6)
    private let conflictRed = Color.red.opacity(0.6)

    // Layout: hours 0-7 compressed, 8-20 expanded, 21-24 compressed
    private let workStart = 8
    private let workEnd = 20
    private let totalHeight: CGFloat = 560  // Match form content height

    var body: some View {
        VStack(spacing: 0) {
            // All-day events bar
            allDayBar
                .frame(height: 20)

            // Timeline
            GeometryReader { geo in
                let height = geo.size.height
                ZStack(alignment: .topLeading) {
                    // Hour grid lines + labels
                    hourGrid(height: height)

                    // Existing events (gray)
                    ForEach(timedEvents, id: \.eventIdentifier) { event in
                        eventBlock(event: event, height: height)
                    }

                    // New event being registered (orange)
                    if !isAllDay {
                        newEventBlock(height: height)
                    }
                }
            }

            // Conflict summary
            conflictSummary
                .frame(height: 20)
        }
        .frame(width: 120)
        .padding(.vertical, 4)
    }

    // MARK: - All-Day Events

    private var allDayEvents: [EKEvent] {
        existingEvents.filter { $0.isAllDay }
    }

    private var timedEvents: [EKEvent] {
        existingEvents.filter { !$0.isAllDay }
    }

    @ViewBuilder
    private var allDayBar: some View {
        if !allDayEvents.isEmpty {
            HStack(spacing: 2) {
                ForEach(allDayEvents.prefix(3), id: \.eventIdentifier) { event in
                    Text(event.title ?? "")
                        .font(.system(size: 8))
                        .lineLimit(1)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.gray.opacity(0.25))
                        .cornerRadius(2)
                }
                if allDayEvents.count > 3 {
                    Text("+\(allDayEvents.count - 3)")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            Color.clear
        }
    }

    // MARK: - Hour Grid

    private func hourGrid(height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Background bands
            Rectangle()
                .fill(Color.gray.opacity(0.03))
                .frame(height: height)

            // Work hours highlight
            let workTop = yPosition(hour: workStart, height: height)
            let workBottom = yPosition(hour: workEnd, height: height)
            Rectangle()
                .fill(Color.gray.opacity(0.05))
                .frame(height: workBottom - workTop)
                .offset(y: workTop)

            // Hour labels + lines
            ForEach([0, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 24], id: \.self) { hour in
                let y = yPosition(hour: hour, height: height)
                HStack(spacing: 2) {
                    Text("\(hour)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 16, alignment: .trailing)
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 0.5)
                }
                .offset(y: y - 5)
            }
        }
    }

    // MARK: - Event Blocks

    private func eventBlock(event: EKEvent, height: CGFloat) -> some View {
        let startHour = hourFraction(from: event.startDate)
        let endHour = hourFraction(from: event.endDate)
        let top = yPosition(hour: startHour, height: height)
        let bottom = yPosition(hour: endHour, height: height)
        let blockHeight = max(bottom - top, 4)
        let hasConflict = overlapsNewEvent(event)

        return Text(event.title ?? "")
            .font(.system(size: 8))
            .lineLimit(1)
            .foregroundColor(existingTextColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 3)
            .frame(height: blockHeight, alignment: .top)
            .background(existingColor)
            .cornerRadius(3)
            .offset(x: 20, y: top)
            .help(event.title ?? "")
    }

    private func newEventBlock(height: CGFloat) -> some View {
        let startHour = hourFraction(from: newStart)
        let endHour = hourFraction(from: newEnd)
        let top = yPosition(hour: startHour, height: height)
        let bottom = yPosition(hour: endHour, height: height)
        let blockHeight = max(bottom - top, 6)
        let hasConflict = conflictCount > 0
        let fillColor = hasConflict ? conflictRed : newEventGreen
        let strokeColor = hasConflict ? Color.red : Color.green

        return Rectangle()
            .fill(fillColor)
            .frame(width: 80, height: blockHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(strokeColor, lineWidth: 1.5)
            )
            .cornerRadius(3)
            .offset(x: 20, y: top)
    }

    // MARK: - Conflict Summary

    private var conflictCount: Int {
        guard !isAllDay else { return 0 }
        return timedEvents.filter { overlapsNewEvent($0) }.count
    }

    @ViewBuilder
    private var conflictSummary: some View {
        if conflictCount > 0 {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                Text("\(conflictCount)건 충돌")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.red)
        } else if !isAllDay {
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                Text("충돌 없음")
                    .font(.system(size: 10))
            }
            .foregroundColor(.green)
        } else {
            Color.clear
        }
    }

    // MARK: - Helpers

    /// Convert hour (0-24) to Y position, compressing non-work hours
    private func yPosition(hour: Double, height: CGFloat) -> CGFloat {
        // 0-8: compressed (15% of height)
        // 8-20: expanded (70% of height)
        // 20-24: compressed (15% of height)
        let compressedTop: CGFloat = 0.15
        let expanded: CGFloat = 0.70
        let compressedBottom: CGFloat = 0.15

        let h = min(max(hour, 0), 24)

        if h <= Double(workStart) {
            return height * compressedTop * CGFloat(h) / CGFloat(workStart)
        } else if h <= Double(workEnd) {
            let offset = compressedTop * height
            let workHours = CGFloat(workEnd - workStart)
            return offset + height * expanded * CGFloat(h - Double(workStart)) / workHours
        } else {
            let offset = (compressedTop + expanded) * height
            let remainHours = CGFloat(24 - workEnd)
            return offset + height * compressedBottom * CGFloat(h - Double(workEnd)) / remainHours
        }
    }

    private func yPosition(hour: Int, height: CGFloat) -> CGFloat {
        yPosition(hour: Double(hour), height: height)
    }

    private func hourFraction(from date: Date) -> Double {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        return Double(hour) + Double(minute) / 60.0
    }

    private func overlapsNewEvent(_ event: EKEvent) -> Bool {
        guard !isAllDay else { return false }
        return event.startDate < newEnd && event.endDate > newStart
    }
}
