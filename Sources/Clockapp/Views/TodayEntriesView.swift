import SwiftUI

/// The "Entrées" tab: today's time entries, each expandable to edit times/description
/// or delete. Backed by Clockify (optimistic local updates, then resync).
struct TodayEntriesView: View {
    @EnvironmentObject private var state: AppState
    @State private var mergeGroups: [[TimeEntry]] = []
    @State private var showMergeConfirm = false
    @State private var mergeMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(state.t(.today)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(Format.hoursMinutes(state.todayTotal))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }

            if state.todayEntries.count >= 2 {
                Button { prepareMerge() } label: {
                    Label(state.t(.smartMerge), systemImage: "arrow.triangle.merge")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if state.todayEntries.isEmpty {
                Text(state.t(.noEntriesToday))
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(state.todayEntries) { entry in
                            EntryRow(
                                entry: entry,
                                project: state.project(for: entry.projectId),
                                isRunning: entry.id == state.currentEntry?.id,
                                onSave: { start, end, desc, pid in
                                    state.updateEntry(entry, start: start, end: end, description: desc, projectId: pid)
                                },
                                onDelete: { state.deleteEntry(entry) }
                            )
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .alert(state.t(.mergeTitle), isPresented: $showMergeConfirm) {
            if mergeGroups.isEmpty {
                Button("OK", role: .cancel) {}
            } else {
                Button(state.t(.cancel), role: .cancel) {}
                Button(state.t(.smartMerge)) { state.applySmartMerge(mergeGroups) }
            }
        } message: {
            Text(mergeMessage)
        }
    }

    private func prepareMerge() {
        let groups = state.smartMergeGroups()
        let deleted = MergeService.deletedCount(groups)
        if deleted == 0 {
            mergeGroups = []
            mergeMessage = state.t(.mergeNothing)
        } else {
            let before = state.todayEntries.filter { $0.end != nil }.count
            mergeGroups = groups
            mergeMessage = state.t(.mergeMsgFmt, before, before - deleted, deleted)
        }
        showMergeConfirm = true
    }
}

private struct EntryRow: View {
    @EnvironmentObject private var state: AppState
    let entry: TimeEntry
    let project: Project?
    let isRunning: Bool
    let onSave: (Date, Date?, String, String?) -> Void
    let onDelete: () -> Void

    @State private var expanded = false
    @State private var editStart = Date()
    @State private var editEnd = Date()
    @State private var editDesc = ""
    @State private var editProjectId: String?

    private static let hhmm: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) { summary }.buttonStyle(.plain)
            if expanded { editor }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    }

    private var summary: some View {
        HStack(spacing: 8) {
            Circle().fill(project?.color ?? .gray).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).lineLimit(1)
                Text(timeSummary).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if isRunning {
                Image(systemName: "record.circle").foregroundStyle(.red).font(.caption2)
            }
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var title: String {
        if !entry.description.isEmpty { return entry.description }
        return project?.name ?? state.t(.noDescription)
    }

    private var timeSummary: String {
        let s = Self.hhmm.string(from: entry.start)
        let e = entry.end.map { Self.hhmm.string(from: $0) } ?? "…"
        var parts = "\(s) – \(e)  ·  \(Format.hoursMinutes(entry.duration()))"
        if let name = project?.name, !entry.description.isEmpty { parts += "  ·  \(name)" }
        return parts
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(state.t(.description), text: $editDesc)
                .textFieldStyle(.roundedBorder)
            ProjectPicker(projects: state.projects, selection: $editProjectId,
                          label: state.t(.project))
            HStack(spacing: 8) {
                TimeField(date: $editStart)
                Text("→").foregroundStyle(.secondary)
                if isRunning {
                    Text(state.t(.runningLc)).font(.caption2).foregroundStyle(.secondary)
                } else {
                    TimeField(date: $editEnd)
                }
                Spacer()
            }
            HStack {
                Button(role: .destructive, action: onDelete) {
                    Label(state.t(.delete), systemImage: "trash")
                }
                Spacer()
                Button(state.t(.save)) {
                    let newStart = combine(day: entry.start, time: editStart)
                    let newEnd: Date? = isRunning ? nil : combine(day: entry.end ?? entry.start, time: editEnd)
                    onSave(newStart, newEnd, editDesc, editProjectId)
                    expanded = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func toggle() {
        if !expanded {
            editStart = entry.start
            editEnd = entry.end ?? Date()
            editDesc = entry.description
            editProjectId = entry.projectId
        }
        withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() }
    }

    /// Combine the entry's calendar day with the edited hour/minute.
    private func combine(day: Date, time: Date) -> Date {
        let cal = Calendar.current
        let d = cal.dateComponents([.year, .month, .day], from: day)
        let t = cal.dateComponents([.hour, .minute], from: time)
        var c = DateComponents()
        c.year = d.year; c.month = d.month; c.day = d.day; c.hour = t.hour; c.minute = t.minute
        return cal.date(from: c) ?? day
    }
}

/// AppKit NSDatePicker (text field + stepper, hour/minute) that sizes to its content —
/// SwiftUI's DatePicker keeps a fixed narrow field that truncates the time.
private struct TimeField: NSViewRepresentable {
    @Binding var date: Date

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.hourMinute]
        picker.font = .systemFont(ofSize: NSFont.systemFontSize)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        picker.dateValue = date
        picker.setContentHuggingPriority(.required, for: .horizontal)
        picker.setContentCompressionResistancePriority(.required, for: .horizontal)
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.date = $date
        if picker.dateValue != date { picker.dateValue = date }
    }

    // Without this, SwiftUI doesn't learn the NSView's intrinsic size and squeezes it.
    // fittingSize is measured too tight on recent macOS (text flush against the bezel),
    // so add breathing room between the time text and the stepper.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSDatePicker, context: Context) -> CGSize? {
        var s = nsView.fittingSize
        s.width += 5
        return s
    }

    func makeCoordinator() -> Coordinator { Coordinator(date: $date) }

    final class Coordinator: NSObject {
        var date: Binding<Date>
        init(date: Binding<Date>) { self.date = date }
        @objc func changed(_ sender: NSDatePicker) { date.wrappedValue = sender.dateValue }
    }
}
