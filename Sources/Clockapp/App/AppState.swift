import Foundation
import Combine
import AppKit
import ServiceManagement

/// Central observable state: timer engine, schedule/auto-track logic, Clockify sync.
@MainActor
final class AppState: ObservableObject {
    // Live timer
    @Published var currentEntry: TimeEntry?
    @Published var now = Date()

    // Data
    @Published var projects: [Project] = []
    @Published var windows: [TrackingWindow] = []
    @Published var recentEntries: [TimeEntry] = []
    /// Entries for the current week fetched from Clockify — the source of truth for totals.
    @Published var remoteEntries: [TimeEntry] = []
    @Published var goals = Goals()
    @Published var settings = AppSettings()

    // Runtime status
    @Published var isScreenLocked = false
    @Published var connection: Connection = .disconnected
    @Published var updateStatus: UpdateStatus = .idle

    enum UpdateStatus: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case installing
        case failed(String)
    }

    enum Connection: Equatable {
        case disconnected
        case connecting
        case connected(name: String)
        case failed(String)
    }

    let clockify = ClockifyClient()
    /// Set by AppDelegate; lets views request the settings window without SwiftUI scenes.
    var openSettings: (() -> Void)?
    private let store = PersistenceStore()
    private var autoTrack: AutoTrackService?
    private var ticker: Timer?
    private var lastNudgeMinute: Int = -1
    private var lastTotalsRefresh: Date?
    private let maxRecentEntries = 500
    /// Tracks window membership across ticks so we can act on *transitions* (edges)
    /// rather than the continuous "we're inside a window" condition — which would
    /// re-start tracking the instant after a manual stop.
    private var wasInWindow = false

    // MARK: - Lifecycle

    init() {
        let state = store.load()
        settings = state.settings
        goals = state.goals
        windows = state.windows
        projects = state.projects
        recentEntries = state.recentEntries

        // Seed the edge detector so simply launching inside a window does not auto-start;
        // tracking begins on the next real edge (unlock, window start, or toggle-on).
        wasInWindow = windows.contains { $0.contains(Date()) }

        clockify.apiKey = KeychainStore.shared.apiKey
        clockify.workspaceId = settings.workspaceId
        clockify.userId = settings.userId

        autoTrack = AutoTrackService(
            onLockOrSleep: { [weak self] in self?.handleScreenLocked() },
            onUnlockOrWake: { [weak self] in self?.handleScreenUnlocked() }
        )

        startTicker()

        if settings.nudgesEnabled {
            NotificationService.shared.requestAuthorizationIfNeeded()
        }
        if clockify.isConfigured {
            Task { await connect() }
        }

        // Silent update check shortly after launch.
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            checkForUpdates(silent: true)
        }
    }

    // MARK: - Persistence

    func save() {
        var s = PersistedState()
        s.settings = settings
        s.goals = goals
        s.windows = windows
        s.projects = projects
        s.recentEntries = Array(recentEntries.prefix(maxRecentEntries))
        store.save(s)
    }

    var storageLocation: URL { store.storageLocation }

    // MARK: - Timer engine

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        now = Date()
        evaluateSchedule()
        maybeNudge()
        // Periodically re-pull totals from Clockify (catches edits from other devices).
        if let last = lastTotalsRefresh, now.timeIntervalSince(last) > 300 {
            Task { await refreshTotals() }
        }
    }

    var isTracking: Bool { currentEntry != nil }

    var elapsed: TimeInterval { currentEntry?.duration(asOf: now) ?? 0 }

    func toggle() {
        if isTracking { stop() } else { start() }
    }

    /// The default project applied when starting without an explicit one:
    /// the most recently tracked project when that option is on, else the fixed default.
    var effectiveDefaultProjectId: String? {
        settings.useLastProjectAsDefault ? settings.lastUsedProjectId : settings.defaultProjectId
    }

    func start(projectId: String? = nil, source: TimeEntry.Source = .manual, description: String = "") {
        guard currentEntry == nil else { return }
        let pid = projectId ?? effectiveDefaultProjectId
        if let pid, pid != settings.lastUsedProjectId {
            settings.lastUsedProjectId = pid
            save()
        }
        let entry = TimeEntry(start: Date(), description: description, projectId: pid, source: source, syncState: .local)
        currentEntry = entry

        guard clockify.isConfigured, !settings.workspaceId.isEmpty else { return }
        let localId = entry.id
        Task {
            do {
                let remoteId = try await clockify.startEntry(
                    description: description, projectId: pid, billable: false, start: entry.start)
                if self.currentEntry?.id == localId {
                    self.currentEntry?.id = remoteId
                    self.currentEntry?.syncState = .synced
                }
            } catch {
                if self.currentEntry?.id == localId {
                    self.currentEntry?.syncState = .failed
                }
            }
            await self.refreshTotals(force: true)
        }
    }

    func stop() {
        guard var entry = currentEntry else { return }
        entry.end = Date()
        currentEntry = nil
        recentEntries.insert(entry, at: 0)
        recentEntries = Array(recentEntries.prefix(maxRecentEntries))
        save()
        Task {
            await syncStop(entry)
            await refreshTotals(force: true)
        }
    }

    /// Push the end of a finished entry to Clockify (or create it whole if it never synced).
    private func syncStop(_ entry: TimeEntry) async {
        guard clockify.isConfigured, !settings.workspaceId.isEmpty, let end = entry.end else { return }
        do {
            if entry.syncState == .synced {
                try await clockify.stopRunningEntry(end: end)
            } else {
                _ = try await clockify.createCompletedEntry(
                    description: entry.description, projectId: entry.projectId,
                    billable: entry.billable, start: entry.start, end: end)
            }
            updateSyncState(of: entry.id, to: .synced)
        } catch {
            updateSyncState(of: entry.id, to: .pending)
        }
    }

    private func updateSyncState(of id: String, to state: TimeEntry.SyncState) {
        if let idx = recentEntries.firstIndex(where: { $0.id == id }) {
            recentEntries[idx].syncState = state
            save()
        }
    }

    /// Retry pushing entries that failed to sync earlier.
    func syncPending() {
        guard clockify.isConfigured else { return }
        let pending = recentEntries.filter {
            $0.syncState == .pending || $0.syncState == .failed || $0.syncState == .local
        }
        for entry in pending {
            Task { await syncStop(entry) }
        }
    }

    // MARK: - Auto-track (screen lock/unlock gated by schedule)

    private func handleScreenLocked() {
        isScreenLocked = true
        // Locking/sleeping stops an auto entry (edge).
        if currentEntry?.source == .auto { stop() }
    }

    private func handleScreenUnlocked() {
        isScreenLocked = false
        // Unlocking/waking starts tracking (edge) — but only inside a window and if idle.
        autoStartIfPossible()
    }

    /// Runs every tick. Only acts on window *transitions* (edges), never on the mere
    /// fact of being inside a window — so a manual stop is not instantly undone.
    private func evaluateSchedule() {
        guard settings.autoTrackEnabled else {
            wasInWindow = activeWindow(at: now) != nil
            return
        }
        let inWindow = activeWindow(at: now) != nil

        if wasInWindow, !inWindow {
            // Window just ended → stop only auto-started entries.
            if currentEntry?.source == .auto { stop() }
        } else if !wasInWindow, inWindow {
            // Window just started → begin tracking if unlocked and idle.
            autoStartIfPossible()
        }
        wasInWindow = inWindow
    }

    /// Starts an `.auto` entry iff auto-track is on, screen unlocked, we're inside a
    /// window, and nothing is already running. Called on genuine edges only.
    private func autoStartIfPossible() {
        guard settings.autoTrackEnabled, !isScreenLocked, currentEntry == nil,
              let w = activeWindow(at: now) else { return }
        start(projectId: w.projectId, source: .auto, description: w.name)
    }

    /// Enabling/disabling auto-track is itself an edge.
    func setAutoTrack(_ enabled: Bool) {
        settings.autoTrackEnabled = enabled
        save()
        wasInWindow = activeWindow(at: now) != nil
        if enabled {
            autoStartIfPossible()
        } else if currentEntry?.source == .auto {
            stop()
        }
    }

    func activeWindow(at date: Date) -> TrackingWindow? {
        windows.first { $0.contains(date) }
    }

    // MARK: - Nudges

    private func maybeNudge() {
        guard settings.nudgesEnabled else { return }
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: now)
        guard let h = comps.hour, let m = comps.minute else { return }
        let minuteOfDay = h * 60 + m
        guard minuteOfDay != lastNudgeMinute else { return }

        // At each window start, nudge if not already tracking.
        for w in windows where w.enabled {
            if w.weekdays.contains(cal.component(.weekday, from: now)),
               minuteOfDay == w.startMinutes, !isTracking {
                lastNudgeMinute = minuteOfDay
                NotificationService.shared.notify(
                    title: t(.nudgeTitle),
                    body: t(.nudgeBodyFmt, w.name))
            }
        }
    }

    // MARK: - Clockify connection

    func setAPIKey(_ key: String) {
        KeychainStore.shared.apiKey = key
        clockify.apiKey = key
        Task { await connect() }
    }

    func connect() async {
        guard clockify.isConfigured else { connection = .disconnected; return }
        connection = .connecting
        do {
            let user = try await clockify.fetchUser()
            settings.userId = user.id
            clockify.userId = user.id
            if settings.workspaceId.isEmpty {
                settings.workspaceId = user.activeWorkspace ?? user.defaultWorkspace ?? ""
            }
            clockify.workspaceId = settings.workspaceId
            if !settings.workspaceId.isEmpty {
                projects = try await clockify.fetchProjects(workspaceId: settings.workspaceId)
            }
            connection = .connected(name: user.name ?? user.email ?? "Clockify")
            save()
            syncPending()
            await refreshTotals(force: true)
            // Seed "last used project" from Clockify (covers cross-device / cross-month).
            if let pid = try? await clockify.fetchMostRecentProjectId(), pid != settings.lastUsedProjectId {
                settings.lastUsedProjectId = pid
                save()
            }
        } catch {
            connection = .failed((error as? ClockifyError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Pulls this week's entries from Clockify to drive the totals & heatmap.
    /// Throttled to avoid hammering the API; pass `force` to bypass the throttle.
    func refreshTotals(force: Bool = false) async {
        guard clockify.isConfigured, !settings.workspaceId.isEmpty, !settings.userId.isEmpty else { return }
        if !force, let last = lastTotalsRefresh, now.timeIntervalSince(last) < 15 { return }
        lastTotalsRefresh = now

        // Fetch a range covering both the current month and the current week (the week
        // can spill past a month boundary) so today/week/month totals are all correct.
        let cal = Calendar.current
        guard let month = cal.dateInterval(of: .month, for: now),
              let week = cal.dateInterval(of: .weekOfYear, for: now) else { return }
        let start = min(month.start, week.start)
        let end = max(month.end, week.end)
        do {
            remoteEntries = try await clockify.fetchTimeEntries(start: start, end: end)
            updateLastUsedFromRemote()
        } catch {
            // Keep the last known totals on failure.
        }
    }

    /// Keeps "last used project" in sync with the most recent Clockify entry we fetched.
    private func updateLastUsedFromRemote() {
        let mostRecent = remoteEntries
            .filter { $0.projectId != nil }
            .max(by: { $0.start < $1.start })
        if let pid = mostRecent?.projectId, pid != settings.lastUsedProjectId {
            settings.lastUsedProjectId = pid
            save()
        }
    }

    /// Called by AppDelegate when the menubar panel opens, for fresh numbers.
    func onPanelOpened() {
        Task { await refreshTotals() }
    }

    // MARK: - Derived stats

    func project(for id: String?) -> Project? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    // MARK: - Updates

    private var pendingRelease: UpdaterService.Release?

    var appVersion: String { UpdaterService.currentVersion ?? "dev" }

    /// silent: only surfaces "available" (used at launch); a manual check shows everything.
    func checkForUpdates(silent: Bool = false) {
        if !silent { updateStatus = .checking }
        Task {
            do {
                if let release = try await UpdaterService.checkForUpdate() {
                    pendingRelease = release
                    updateStatus = .available(version: release.version)
                } else if !silent {
                    updateStatus = .upToDate
                }
            } catch {
                if !silent { updateStatus = .failed(error.localizedDescription) }
            }
        }
    }

    func installUpdate() {
        guard let release = pendingRelease else { return }
        updateStatus = .installing
        Task {
            do {
                let appURL = try await UpdaterService.downloadAndInstall(release)
                UpdaterService.relaunch(appURL)
            } catch {
                updateStatus = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Launch at login

    /// Live system status — macOS is the source of truth, nothing to persist.
    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Fails for the bare `swift run` executable (no bundle); harmless.
        }
        objectWillChange.send()
    }

    // MARK: - Localization

    /// Localized string for the current language. Pass args for `%@`/`%d` templates.
    func t(_ key: LocKey, _ args: CVarArg...) -> String {
        let s = Localization.string(key, settings.language)
        return args.isEmpty ? s : String(format: s, arguments: args)
    }

    func weekdayShort(_ calendarValue: Int) -> String {
        Localization.weekdayShort(calendarValue, settings.language)
    }

    /// Clockify's week entries are the source of truth. The running entry is added only
    /// if Clockify hasn't returned it yet (just started, or offline) — avoids double count.
    private var statsEntries: [TimeEntry] {
        var list = remoteEntries
        if let cur = currentEntry, !list.contains(where: { $0.id == cur.id }) {
            list.append(cur)
        }
        return list
    }

    var todayTotal: TimeInterval {
        StatsService.total(for: statsEntries, on: now, asOf: now)
    }

    var weekTotal: TimeInterval {
        StatsService.weekTotal(for: statsEntries, containing: now, asOf: now)
    }

    var monthTotal: TimeInterval {
        StatsService.monthTotal(for: statsEntries, containing: now, asOf: now)
    }

    func heatmap() -> [[TimeInterval]] {
        StatsService.heatmap(for: statsEntries, asOf: now)
    }

    /// Today's entries (Clockify + the running one), most recent first.
    var todayEntries: [TimeEntry] {
        let dayStart = Calendar.current.startOfDay(for: now)
        var list = remoteEntries.filter { $0.start >= dayStart }
        if let cur = currentEntry, cur.start >= dayStart, !list.contains(where: { $0.id == cur.id }) {
            list.append(cur)
        }
        return list.sorted { $0.start > $1.start }
    }

    // MARK: - Entry editing

    /// Live-edits the running entry's description; pushes to Clockify only once it's synced.
    func updateCurrentDescription(_ text: String) {
        guard var cur = currentEntry, cur.description != text else { return }
        cur.description = text
        currentEntry = cur
        guard cur.syncState == .synced, clockify.isConfigured else { return }
        Task {
            try? await clockify.updateEntry(id: cur.id, description: text, projectId: cur.projectId,
                                            billable: cur.billable, start: cur.start, end: nil)
        }
    }

    /// Edits an existing entry's times/description (optimistic locally, then Clockify).
    func updateEntry(_ entry: TimeEntry, start: Date, end: Date?, description: String) {
        if let i = remoteEntries.firstIndex(where: { $0.id == entry.id }) {
            remoteEntries[i].start = start
            remoteEntries[i].end = end
            remoteEntries[i].description = description
        }
        if currentEntry?.id == entry.id {
            currentEntry?.start = start
            currentEntry?.description = description
        }
        guard clockify.isConfigured else { return }
        Task {
            do {
                try await clockify.updateEntry(id: entry.id, description: description,
                    projectId: entry.projectId, billable: entry.billable, start: start, end: end)
                await refreshTotals(force: true)
            } catch { /* keep optimistic copy */ }
        }
    }

    func deleteEntry(_ entry: TimeEntry) {
        if currentEntry?.id == entry.id { currentEntry = nil }
        remoteEntries.removeAll { $0.id == entry.id }
        recentEntries.removeAll { $0.id == entry.id }
        save()
        guard clockify.isConfigured else { return }
        Task {
            try? await clockify.deleteEntry(id: entry.id)
            await refreshTotals(force: true)
        }
    }
}
