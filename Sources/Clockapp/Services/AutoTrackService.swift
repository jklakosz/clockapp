import Foundation
import AppKit

/// A user-presence transition derived from system notifications.
enum ScreenEvent {
    case locked        // session locked
    case unlocked      // session unlocked
    case coverStarted  // screensaver started, displays slept, or system going to sleep
    case coverEnded    // screensaver stopped, displays woke, or system woke
}

/// Bridges macOS lock/unlock, sleep/wake and screensaver notifications into
/// `ScreenEvent`s. These drive auto start/stop of tracking, gated by the schedule.
final class AutoTrackService {
    private let onEvent: (ScreenEvent) -> Void
    private var observers: [NSObjectProtocol] = []

    init(onEvent: @escaping (ScreenEvent) -> Void) {
        self.onEvent = onEvent
        subscribe()
    }

    private func subscribe() {
        // Session lock/unlock — undocumented but stable distributed notifications.
        let dc = DistributedNotificationCenter.default()
        observe(dc, "com.apple.screenIsLocked", .locked)
        observe(dc, "com.apple.screenIsUnlocked", .unlocked)
        // Screensaver — the display stays on, so display-sleep events never fire.
        observe(dc, "com.apple.screensaver.didstart", .coverStarted)
        observe(dc, "com.apple.screensaver.didstop", .coverEnded)

        // Sleep / wake — documented workspace notifications.
        let wc = NSWorkspace.shared.notificationCenter
        observe(wc, NSWorkspace.willSleepNotification, .coverStarted)
        observe(wc, NSWorkspace.didWakeNotification, .coverEnded)
        observe(wc, NSWorkspace.screensDidSleepNotification, .coverStarted)
        observe(wc, NSWorkspace.screensDidWakeNotification, .coverEnded)
    }

    private func observe(_ center: NotificationCenter, _ name: NSNotification.Name, _ event: ScreenEvent) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            self?.onEvent(event)
        })
    }

    private func observe(_ center: DistributedNotificationCenter, _ name: String, _ event: ScreenEvent) {
        observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
            self?.onEvent(event)
        })
    }

    deinit {
        let dc = DistributedNotificationCenter.default()
        let wc = NSWorkspace.shared.notificationCenter
        for o in observers {
            dc.removeObserver(o)
            wc.removeObserver(o)
        }
    }
}
