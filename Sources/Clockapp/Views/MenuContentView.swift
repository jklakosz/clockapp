import SwiftUI
import AppKit

/// The dropdown panel shown from the menubar, split into two tabs: Tracker & Entrées.
struct MenuContentView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedProjectId: String?
    @State private var draftDescription = ""
    @State private var tab: Tab = .tracker

    private enum Tab { case tracker, entries }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $tab) {
                Text(state.t(.tabTracker)).tag(Tab.tracker)
                Text(state.t(.tabEntries)).tag(Tab.entries)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab {
            case .tracker: trackerTab
            case .entries: TodayEntriesView()
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            selectedProjectId = state.effectiveDefaultProjectId
            draftDescription = state.currentEntry?.description ?? ""
        }
        .onChange(of: state.currentEntry?.id) { _ in
            draftDescription = state.currentEntry?.description ?? ""
        }
        // Mirror description edits coming from Clockify. The field itself refuses the
        // overwrite while focused, so typing in progress is never clobbered.
        .onChange(of: state.currentEntry?.description) { desc in
            if let desc { draftDescription = desc }
        }
        .onDisappear {
            if state.isTracking { state.updateCurrentDescription(draftDescription) }
        }
    }

    // MARK: - Tracker tab

    private var trackerTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            projectRow
            autoTrackRow
            Divider()
            totalsRow
            if state.goals.enabled { goalRow }
            if state.earnings.enabled && state.earnings.hourlyRate > 0 { earningsRow }
            Divider()
            heatmapSection
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.isTracking ? state.t(.statusRunning) : state.t(.statusStopped))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(Format.clock(state.elapsed))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                Button(action: toggle) {
                    Image(systemName: state.isTracking ? "stop.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(state.isTracking ? .red : .green)
            }

            if state.isTracking {
                MultilineDescriptionField(text: $draftDescription, placeholder: state.t(.descPlaceholder)) {
                    state.updateCurrentDescription(draftDescription)
                }
                .frame(height: 58)
                .frame(maxWidth: .infinity)
                if let p = state.project(for: state.currentEntry?.projectId) {
                    HStack(spacing: 4) {
                        Circle().fill(p.color).frame(width: 7, height: 7)
                        Text(p.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    private var projectRow: some View {
        Group {
            if state.projects.isEmpty {
                Label(state.t(.noProjects), systemImage: "folder")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ProjectPicker(projects: state.projects, selection: $selectedProjectId, label: state.t(.project))
                    .disabled(state.isTracking)
            }
        }
    }

    private var autoTrackRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { state.settings.autoTrackEnabled },
                set: { state.setAutoTrack($0) }
            )) {
                Label(state.t(.autotrack), systemImage: "lock.open")
            }
            .toggleStyle(.switch)

            if let w = state.activeWindow(at: state.now) {
                Text(state.t(.activeWindowFmt, w.name, w.timeRangeLabel))
                    .font(.caption2).foregroundStyle(.green)
            } else if state.settings.autoTrackEnabled {
                Text(state.t(.outOfWindow))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var totalsRow: some View {
        HStack(spacing: 0) {
            stat(state.t(.today), Format.hoursMinutes(state.todayTotal))
            stat(state.t(.week), Format.hoursMinutes(state.weekTotal))
            stat(state.t(.month), Format.hoursMinutes(state.monthTotal))
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private var goalRow: some View {
        let dayGoal = Double(state.goals.dailyMinutes * 60)
        return ProgressView(value: min(state.todayTotal, dayGoal), total: max(dayGoal, 1)) {
            Text(state.t(.dailyGoalFmt, Format.hoursMinutes(state.todayTotal), Format.hoursMinutes(state.goals.dailyMinutes)))
                .font(.caption2)
        }
    }

    private var earningsRow: some View {
        let showNet = state.earnings.urssafEnabled
        let amount = showNet ? state.monthNet : state.monthGross
        let label = showNet ? state.t(.net) : state.t(.gross)
        let converted = state.converted(amount)
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: "eurosign.circle").foregroundStyle(.secondary)
            Text(state.t(.earnedThisMonth)).font(.caption).foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                if let converted {
                    // Converted (target) currency is the headline; original is secondary.
                    Text(Format.money(converted, state.earnings.convertTo))
                        .font(.callout).monospacedDigit()
                        + Text(" \(label)").font(.caption2).foregroundColor(.secondary)
                    Text("= \(Format.money(amount, state.earnings.currency))")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    if let rate = state.rateDescription {
                        Text(rate).font(.system(size: 9)).foregroundStyle(.tertiary).monospacedDigit()
                    }
                } else {
                    Text(Format.money(amount, state.earnings.currency))
                        .font(.callout).monospacedDigit()
                        + Text(" \(label)").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
    }

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.t(.heatmapTitle))
                .font(.caption).foregroundStyle(.secondary)
            HeatmapView(grid: state.heatmap())
        }
    }

    // MARK: - Footer (shared)

    private var footer: some View {
        HStack {
            connectionBadge
            Spacer()
            if case .available(let v) = state.updateStatus {
                Button { state.openSettings?() } label: {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
                }
                .buttonStyle(.borderless)
                .help(state.t(.updAvailableFmt, v))
            }
            Button { state.openSettings?() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).help(state.t(.settings))
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(.borderless).help(state.t(.quit))
        }
    }

    private var connectionBadge: some View {
        HStack(spacing: 4) {
            switch state.connection {
            case .connected(let name):
                Circle().fill(.green).frame(width: 7, height: 7)
                Text(name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            case .connecting:
                Circle().fill(.yellow).frame(width: 7, height: 7)
                Text(state.t(.connConnecting)).font(.caption2).foregroundStyle(.secondary)
            case .failed:
                Circle().fill(.red).frame(width: 7, height: 7)
                Text(state.t(.connError)).font(.caption2).foregroundStyle(.secondary)
            case .disconnected:
                Circle().fill(.gray).frame(width: 7, height: 7)
                Text(state.t(.connOffline)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func toggle() {
        if state.isTracking {
            state.stop()
        } else {
            state.start(projectId: selectedProjectId)
        }
    }
}
