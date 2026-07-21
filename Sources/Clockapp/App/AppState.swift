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
    @Published var earnings = Earnings()
    @Published var settings = AppSettings()

    // Runtime status
    /// Session locked (password wall). Driven only by lock/unlock notifications.
    @Published var isScreenLocked = false
    /// Screen "covered": screensaver running, displays asleep, or system asleep.
    @Published var isScreenCovered = false
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

    // MCP local server
    @Published var mcpRunning = false
    @Published var mcpError: String?
    private var localServer: LocalAPIServer?
    private let mcpManager = MCPProcessManager()
    private let mcpToken = UUID().uuidString
    var mcpURL: String { "http://127.0.0.1:\(MCPProcessManager.mcpPort)/mcp" }

    private let store = PersistenceStore()
    private var autoTrack: AutoTrackService?
    private var ticker: Timer?
    private var lastNudgeMinute: Int = -1
    private var lastTotalsRefresh: Date?
    private var lastTrackerPoll: Date?
    /// Poll cadence for mirroring the running tracker from Clockify.
    private let trackerPollInterval: TimeInterval = 30
    private var lastFxRefresh: Date?
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
        earnings = state.earnings
        windows = state.windows
        projects = state.projects
        recentEntries = state.recentEntries

        // Seed the edge detector so simply launching inside a window does not auto-start;
        // tracking begins on the next real edge (unlock, window start, or toggle-on).
        wasInWindow = windows.contains { $0.contains(Date()) }

        clockify.apiKey = KeychainStore.shared.apiKey
        clockify.workspaceId = settings.workspaceId
        clockify.userId = settings.userId

        autoTrack = AutoTrackService { [weak self] event in
            self?.handleScreenEvent(event)
        }

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

        refreshExchangeRate()

        if settings.mcpEnabled { startMCP() }
    }

    // MARK: - MCP local server

    func setMCPEnabled(_ enabled: Bool) {
        settings.mcpEnabled = enabled
        save()
        if enabled { startMCP() } else { stopMCP() }
    }

    private func startMCP() {
        let server = LocalAPIServer(token: mcpToken) { [weak self] req in
            await self?.handleAPIRequest(req) ?? LocalAPIServer.Response(500, ["error": "app unavailable"])
        }
        do {
            try server.start { [weak self] apiPort in
                Task { @MainActor in
                    guard let self else { return }
                    let ok = self.mcpManager.start(appAPIPort: apiPort, token: self.mcpToken)
                    self.mcpRunning = ok
                    self.mcpError = ok ? nil : self.mcpManager.lastError
                }
            }
            localServer = server
        } catch {
            mcpError = error.localizedDescription
            mcpRunning = false
        }
    }

    private func stopMCP() {
        mcpManager.stop()
        localServer?.stop()
        localServer = nil
        mcpRunning = false
    }

    /// Called by AppDelegate on quit to avoid orphaning the child process.
    func shutdownMCP() { stopMCP() }

    // MARK: - Local API handlers (used by the MCP bridge)

    private func handleAPIRequest(_ req: LocalAPIServer.Request) async -> LocalAPIServer.Response {
        switch (req.method, req.path) {
        case ("GET", "/health"):
            return LocalAPIServer.Response(200, ["ok": true, "tracking": isTracking])
        case ("GET", "/current"):
            return LocalAPIServer.Response(200, currentEntrySnapshot())
        case ("GET", "/projects"):
            return LocalAPIServer.Response(200, ["projects": projectsSnapshot()])
        case ("PATCH", "/current"):
            return patchCurrent(req.body)
        default:
            return LocalAPIServer.Response(404, ["error": "not found"])
        }
    }

    private func patchCurrent(_ body: Data) -> LocalAPIServer.Response {
        guard currentEntry != nil else {
            return LocalAPIServer.Response(409, ["error": "no running entry"])
        }
        guard let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return LocalAPIServer.Response(400, ["error": "invalid json"])
        }
        if let desc = obj["description"] as? String {
            updateCurrentDescription(desc)
        }
        // projectId present → set it; explicit null clears it.
        if obj.keys.contains("projectId") {
            let pid = obj["projectId"] as? String
            setCurrentEntryProject(pid)
        }
        return LocalAPIServer.Response(200, currentEntrySnapshot())
    }

    private func currentEntrySnapshot() -> [String: Any] {
        guard let e = currentEntry else { return ["running": false] }
        let proj = project(for: e.projectId)
        return [
            "running": true,
            "id": e.id,
            "description": e.description,
            "projectId": e.projectId ?? NSNull(),
            "projectName": proj?.name ?? NSNull(),
            "clientName": proj?.clientName ?? NSNull(),
            "start": ISO8601DateFormatter().string(from: e.start),
            "elapsedSeconds": Int(elapsed),
        ]
    }

    private func projectsSnapshot() -> [[String: Any]] {
        projects.map { p in
            ["id": p.id, "name": p.name, "clientName": p.clientName ?? NSNull()]
        }
    }

    /// Sets the running entry's project (optimistic locally, then Clockify).
    private func setCurrentEntryProject(_ projectId: String?) {
        guard var cur = currentEntry, cur.projectId != projectId else { return }
        cur.projectId = projectId
        cur.billable = project(for: projectId)?.billable ?? cur.billable // adopt project default
        currentEntry = cur
        guard cur.syncState == .synced, clockify.isConfigured else { return }
        Task {
            try? await clockify.updateEntry(id: cur.id, description: cur.description,
                projectId: projectId, billable: cur.billable, start: cur.start, end: nil)
        }
    }

    // MARK: - Persistence

    func save() {
        var s = PersistedState()
        s.settings = settings
        s.goals = goals
        s.earnings = earnings
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
        // Mirror the running tracker from Clockify (start/stop/edits made over there).
        if clockify.isConfigured,
           lastTrackerPoll.map({ now.timeIntervalSince($0) > trackerPollInterval }) ?? true {
            lastTrackerPoll = now
            Task { await syncRunningEntryFromRemote() }
        }
        // Refresh the FX rate every 2 hours.
        if let last = lastFxRefresh, now.timeIntervalSince(last) > 2 * 3600 {
            refreshExchangeRate()
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
        // Inherit the project's default billability (Clockify sets this per project).
        let billable = project(for: pid)?.billable ?? false
        let entry = TimeEntry(start: Date(), description: description, projectId: pid,
                              billable: billable, source: source, syncState: .local)
        currentEntry = entry

        guard clockify.isConfigured, !settings.workspaceId.isEmpty else { return }
        let localId = entry.id
        Task {
            do {
                let remoteId = try await clockify.startEntry(
                    description: description, projectId: pid, billable: billable, start: entry.start)
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

    private func handleScreenEvent(_ event: ScreenEvent) {
        switch event {
        case .locked:
            // Locking gates future auto-starts but does NOT stop a running entry —
            // only screen sleep stops it (below).
            isScreenLocked = true
        case .coverStarted:
            // Screensaver / display sleep / system sleep — the ONLY auto-stop trigger.
            isScreenCovered = true
            if currentEntry?.source == .auto { stop() }
        case .unlocked:
            // Unlocking (arrival) is a start trigger, gated by the schedule.
            isScreenLocked = false
            isScreenCovered = false
            autoStartIfPossible()
        case .coverEnded:
            // Waking the screen must NOT restart the timer — just clear the flag.
            isScreenCovered = false
        }
    }

    /// Runs every tick. The schedule is used ONLY to *start* auto-tracking when a
    /// window opens — leaving a window never stops a running entry.
    private func evaluateSchedule() {
        guard settings.autoTrackEnabled else {
            wasInWindow = activeWindow(at: now) != nil
            return
        }
        let inWindow = activeWindow(at: now) != nil
        if !wasInWindow, inWindow {
            // Window just started → begin tracking if the user is present and idle.
            autoStartIfPossible()
        }
        wasInWindow = inWindow
    }

    /// Starts an `.auto` entry iff auto-track is on, the user is present (unlocked and
    /// screen not covered), we're inside a window, and nothing is already running.
    /// Called on genuine edges only.
    private func autoStartIfPossible() {
        guard settings.autoTrackEnabled, !isScreenLocked, !isScreenCovered,
              currentEntry == nil, let w = activeWindow(at: now) else { return }
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
        Task {
            await refreshTotals()
            await syncRunningEntryFromRemote()
        }
    }

    /// Reconciles the local timer with the entry actually running on Clockify, so
    /// starts/stops/edits made from the Clockify UI (or another device) show up here.
    func syncRunningEntryFromRemote() async {
        guard clockify.isConfigured, !settings.workspaceId.isEmpty, !settings.userId.isEmpty else { return }
        let remote: TimeEntry?
        do { remote = try await clockify.fetchRunningEntry() } catch { return }

        switch (currentEntry, remote) {
        case (nil, nil):
            break

        case (nil, .some(let r)):
            // Started from Clockify — adopt it. Skip if it's an entry we just stopped
            // locally (our stop push may still be in flight).
            guard !recentEntries.contains(where: { $0.id == r.id }) else { break }
            currentEntry = r

        case (.some(let local), nil):
            // Stopped from Clockify — finalize locally WITHOUT pushing a stop.
            // (If our entry never reached Clockify, remote nil says nothing — keep it.)
            guard local.syncState == .synced else { break }
            await refreshTotals(force: true)
            var finished = local
            finished.end = remoteEntries.first(where: { $0.id == local.id })?.end ?? Date()
            finished.syncState = .synced
            currentEntry = nil
            recentEntries.insert(finished, at: 0)
            recentEntries = Array(recentEntries.prefix(maxRecentEntries))
            save()

        case (.some(let local), .some(let r)):
            if local.id == r.id {
                // Same entry: mirror remote edits (description, project, start).
                var merged = local
                merged.description = r.description
                merged.projectId = r.projectId
                merged.start = r.start
                if merged != local { currentEntry = merged }
            } else {
                // A different entry is running on Clockify — Clockify wins.
                currentEntry = r
            }
        }
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
                if let release = try await UpdaterService.checkForUpdate(allowPrereleases: settings.receivePrereleases) {
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

    // Earnings for the current month, from tracked time.
    var monthGross: Double { earnings.gross(for: monthTotal) }
    var monthUrssaf: Double { earnings.urssaf(for: monthTotal) }
    var monthNet: Double { earnings.net(for: monthTotal) }

    /// Rate from the rate currency to the target currency (for the dual display). Nil until fetched.
    @Published var fxRate: Double?

    /// Converts an amount from the rate currency to the target currency, if applicable.
    func converted(_ amount: Double) -> Double? {
        guard earnings.convertsCurrency, let r = fxRate else { return nil }
        return amount * r
    }

    /// "1 € = 1.0823 $" for the current pair, or nil if no conversion / rate unknown.
    var rateDescription: String? {
        guard earnings.convertsCurrency, let r = fxRate else { return nil }
        return "1 \(earnings.currency.symbol) = \(String(format: "%.4f", r)) \(earnings.convertTo.symbol)"
    }

    func refreshExchangeRate() {
        lastFxRefresh = now
        let from = earnings.currency
        let to = earnings.convertTo
        Task {
            let rate = await ExchangeRateService.shared.rate(from: from, to: to)
            if earnings.currency == from, earnings.convertTo == to { fxRate = rate }
        }
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

    /// This week's entries (Clockify + the running one), most recent first.
    var weekEntries: [TimeEntry] {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: now) else { return [] }
        var list = remoteEntries.filter { $0.start >= interval.start && $0.start < interval.end }
        if let cur = currentEntry, cur.start >= interval.start, !list.contains(where: { $0.id == cur.id }) {
            list.append(cur)
        }
        return list.sorted { $0.start > $1.start }
    }

    /// This week's entries grouped by day (most recent day first), with each day's total.
    var weekEntriesByDay: [(day: Date, entries: [TimeEntry], total: TimeInterval)] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: weekEntries) { cal.startOfDay(for: $0.start) }
        return groups
            .map { (day: $0.key, entries: $0.value, total: StatsService.total(for: $0.value, on: $0.key, asOf: now)) }
            .sorted { $0.day > $1.day }
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

    /// Edits an existing entry's times/description/project (optimistic locally, then Clockify).
    func updateEntry(_ entry: TimeEntry, start: Date, end: Date?, description: String, projectId: String?) {
        // Changing project adopts the new project's default billability.
        let billable = projectId == entry.projectId ? entry.billable : (project(for: projectId)?.billable ?? entry.billable)
        if let i = remoteEntries.firstIndex(where: { $0.id == entry.id }) {
            remoteEntries[i].start = start
            remoteEntries[i].end = end
            remoteEntries[i].description = description
            remoteEntries[i].projectId = projectId
            remoteEntries[i].billable = billable
        }
        if currentEntry?.id == entry.id {
            currentEntry?.start = start
            currentEntry?.description = description
            currentEntry?.projectId = projectId
            currentEntry?.billable = billable
        }
        guard clockify.isConfigured else { return }
        Task {
            do {
                try await clockify.updateEntry(id: entry.id, description: description,
                    projectId: projectId, billable: billable, start: start, end: end)
                await refreshTotals(force: true)
            } catch { /* keep optimistic copy */ }
        }
    }

    // MARK: - Smart merge

    /// Chains of this week's entries that Smart merge would collapse (>= 2 each).
    /// MergeService never merges across a >10min gap, so day boundaries are safe.
    func smartMergeGroups() -> [[TimeEntry]] {
        MergeService.plan(weekEntries)
    }

    /// Applies a merge plan: extends the first entry of each chain and deletes the rest,
    /// both locally (optimistic) and on Clockify.
    func applySmartMerge(_ groups: [[TimeEntry]]) {
        guard clockify.isConfigured, !groups.isEmpty else { return }
        var merges: [TimeEntry] = []
        var deleteIds: [String] = []

        for chain in groups {
            let merged = MergeService.merged(from: chain)
            merges.append(merged)
            deleteIds.append(contentsOf: chain.dropFirst().map { $0.id })
            if let i = remoteEntries.firstIndex(where: { $0.id == merged.id }) {
                remoteEntries[i] = merged
            }
        }
        let delSet = Set(deleteIds)
        remoteEntries.removeAll { delSet.contains($0.id) }
        save()

        Task {
            for m in merges {
                try? await clockify.updateEntry(id: m.id, description: m.description,
                    projectId: m.projectId, billable: m.billable, start: m.start, end: m.end)
            }
            for id in deleteIds {
                try? await clockify.deleteEntry(id: id)
            }
            await refreshTotals(force: true)
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
