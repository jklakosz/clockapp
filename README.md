# Clockapp

A native macOS **menubar time tracker** in the spirit of Clockify's desktop app — with a
twist: it can **auto-track your time based on screen unlock/lock**, but only inside the
**time windows you define** (certain weekdays, certain hours).

Built with SwiftUI (`MenuBarExtra`) + Swift Package Manager. No Xcode required.

## Features

- ⏱️ **Menubar timer** — live elapsed time in the status bar, start/stop in one click.
- 🔒 **Auto-track on unlock/lock** — unlocking your Mac inside a *trackable window* starts
  the timer; locking it (or leaving the window) stops it. Gated by your schedule.
- 🗓️ **Trackable windows** — define plages by weekday + start/end time, each mapped to a
  Clockify project.
- ☁️ **Clockify sync** — pushes time entries to your real Clockify account via the API.
  Works offline and resyncs when reconnected. API key stored in the macOS Keychain.
- 🎯 **Goals** — daily / weekly hour targets with progress bars.
- 🔔 **Nudges** — optional notification when a trackable window begins.
- 📊 **Analytics** — a day × hour heatmap of when you actually work.

## Build & run

```bash
# Dev run (bare executable)
swift run

# Build the menubar .app bundle (recommended — enables notifications & no Dock icon)
./scripts/build-app.sh
open dist/Clockapp.app
```

The bundle is menubar-only (`LSUIElement`) and ad-hoc signed so notifications and Keychain work.

### Stop repeated Keychain prompts (stable signing)

Ad-hoc signatures change on every rebuild, so macOS keeps re-asking to access the
stored API key. Fix it once with a stable self-signed identity:

```bash
./scripts/create-signing-cert.sh   # one-time: creates "Clockapp Dev" in your login keychain
./scripts/build-app.sh             # now signs with that stable identity
```

On the next launch, click **Always Allow** on the Keychain prompt. Because the app now
has a stable *designated requirement*, that choice survives every future rebuild.

## First-time setup

1. Click the timer icon in the menu bar → gear (⚙️) → **Clockify** tab.
2. Paste your **Clockify API key** (clockify.me → Profile → Preferences → *Advanced* → API).
3. Pick a **default project**.
4. Go to the **Planning** tab and add one or more *trackable windows* (e.g. Lun–Ven 09:00–18:00).
5. Back in the menu, toggle **Auto-suivi (déverrouillage)** on.

Now, whenever you unlock your Mac inside a window, tracking starts automatically and syncs
to Clockify; locking it stops and pushes the entry.

## Architecture

```
Sources/Clockapp/
  App/
    ClockappApp.swift      @main — MenuBarExtra + Settings window, .accessory policy
    AppState.swift         central @MainActor store: timer engine, schedule logic, sync
  Models/                  TimeEntry, Project, TrackingWindow/Weekday, Settings, Goals
  Services/
    AutoTrackService.swift screen lock/unlock + sleep/wake → callbacks
    ClockifyClient.swift   async Clockify REST wrapper
    KeychainStore.swift    API key in the Keychain
    PersistenceStore.swift JSON state in ~/Library/Application Support/Clockapp
    NotificationService.swift  local nudges
    StatsService.swift     totals + day×hour heatmap
  Views/                   MenuBarLabel, MenuContentView, SettingsView, ScheduleEditorView, StatsView
  Support/Formatting.swift time formatters
```

### How auto-track works
`AutoTrackService` listens to `com.apple.screenIsLocked` / `screenIsUnlocked`
(DistributedNotificationCenter) and `NSWorkspace` sleep/wake. Every second, `AppState`
re-evaluates the schedule: *inside a window + unlocked + auto on* → start an `.auto` entry;
otherwise stop any running `.auto` entry. Manual entries are never auto-stopped.

## Notes / limits

- Screen-lock notifications are undocumented but stable across macOS versions.
- Windows don't span midnight (start < end). Split into two if you need that.
- Stats use entries kept locally (last 500); it does not backfill history from Clockify.
