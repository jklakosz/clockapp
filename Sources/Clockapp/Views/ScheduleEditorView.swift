import SwiftUI

/// Editor for trackable windows (days + hours) that gate auto-tracking.
struct ScheduleEditorView: View {
    @EnvironmentObject private var state: AppState
    @State private var editing: TrackingWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(state.t(.trackableWindows)).font(.headline)
                Spacer()
                Button {
                    editing = TrackingWindow(name: state.t(.defaultWindowName),
                                             projectId: state.settings.defaultProjectId)
                } label: { Label(state.t(.add), systemImage: "plus") }
            }

            Text(state.t(.scheduleHelp))
                .font(.caption).foregroundStyle(.secondary)

            if state.windows.isEmpty {
                Spacer()
                Text(state.t(.noWindows))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(state.windows) { w in
                        row(w)
                    }
                    .onDelete { idx in
                        state.windows.remove(atOffsets: idx)
                        state.save()
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(item: $editing) { win in
            let exists = state.windows.contains { $0.id == win.id }
            WindowEditor(
                initial: win,
                projects: state.projects,
                onSave: { saved in
                    if let i = state.windows.firstIndex(where: { $0.id == saved.id }) {
                        state.windows[i] = saved
                    } else {
                        state.windows.append(saved)
                    }
                    state.save()
                },
                onDelete: exists ? {
                    state.windows.removeAll { $0.id == win.id }
                    state.save()
                } : nil
            )
        }
    }

    private func row(_ w: TrackingWindow) -> some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { w.enabled },
                set: { newValue in
                    if let i = state.windows.firstIndex(where: { $0.id == w.id }) {
                        state.windows[i].enabled = newValue
                        state.save()
                    }
                }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(w.name).font(.body)
                Text("\(weekdaysLabel(w))   ·   \(w.timeRangeLabel)")
                    .font(.caption).foregroundStyle(.secondary)
                if let p = state.project(for: w.projectId) {
                    HStack(spacing: 4) {
                        Circle().fill(p.color).frame(width: 7, height: 7)
                        Text(p.name).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Button { editing = w } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .help(state.t(.save))
            Button {
                state.windows.removeAll { $0.id == w.id }
                state.save()
            } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help(state.t(.delete))
        }
        .padding(.vertical, 2)
    }

    /// Localized "Lun Mar Mer …" for the window's weekdays (Monday-first).
    private func weekdaysLabel(_ w: TrackingWindow) -> String {
        Weekday.allCases
            .filter { w.weekdays.contains($0.calendarValue) }
            .map { state.weekdayShort($0.calendarValue) }
            .joined(separator: " ")
    }
}

/// Sheet to create / edit a single window.
private struct WindowEditor: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State var window: TrackingWindow
    let projects: [Project]
    let onSave: (TrackingWindow) -> Void
    let onDelete: (() -> Void)?

    init(initial: TrackingWindow, projects: [Project],
         onSave: @escaping (TrackingWindow) -> Void, onDelete: (() -> Void)?) {
        _window = State(initialValue: initial)
        self.projects = projects
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(state.t(.windowEditorTitle)).font(.headline)

            TextField(state.t(.name), text: $window.name)

            VStack(alignment: .leading, spacing: 6) {
                Text(state.t(.days)).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(Weekday.allCases) { day in
                        let on = window.weekdays.contains(day.calendarValue)
                        Button(state.weekdayShort(day.calendarValue)) {
                            if on { window.weekdays.remove(day.calendarValue) }
                            else { window.weekdays.insert(day.calendarValue) }
                        }
                        .buttonStyle(.bordered)
                        .tint(on ? .accentColor : .gray)
                    }
                }
            }

            HStack(spacing: 24) {
                timeStepper(state.t(.startLabel), value: $window.startMinutes)
                timeStepper(state.t(.endLabel), value: $window.endMinutes)
            }

            ProjectPicker(projects: projects, selection: $window.projectId,
                          noneTitle: state.t(.defaultProject), label: state.t(.project))

            HStack {
                if let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: { Label(state.t(.delete), systemImage: "trash") }
                }
                Spacer()
                Button(state.t(.cancel)) { dismiss() }
                Button(state.t(.save)) {
                    if window.endMinutes <= window.startMinutes {
                        window.endMinutes = min(window.startMinutes + 60, 24 * 60)
                    }
                    onSave(window)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(window.weekdays.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func timeStepper(_ label: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Stepper(TrackingWindow.hhmm(value.wrappedValue),
                    value: value, in: 0...(24 * 60), step: 15)
                .monospacedDigit()
        }
    }
}
