import Foundation
import AppKit

/// Bridges macOS screen-lock and sleep/wake events into simple callbacks.
///
/// - Lock  (`com.apple.screenIsLocked`) and Sleep (`NSWorkspace.willSleep`) → `onLockOrSleep`
/// - Unlock (`com.apple.screenIsUnlocked`) and Wake (`NSWorkspace.didWake`)  → `onUnlockOrWake`
///
/// These are the signals used to auto start/stop tracking, gated by the schedule.
final class AutoTrackService {
    private let onLockOrSleep: () -> Void
    private let onUnlockOrWake: () -> Void
    private var observers: [NSObjectProtocol] = []

    init(onLockOrSleep: @escaping () -> Void,
         onUnlockOrWake: @escaping () -> Void) {
        self.onLockOrSleep = onLockOrSleep
        self.onUnlockOrWake = onUnlockOrWake
        subscribe()
    }

    private func subscribe() {
        // Screen lock / unlock — undocumented but stable distributed notifications.
        let dc = DistributedNotificationCenter.default()
        observers.append(dc.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] _ in self?.onLockOrSleep() })
        observers.append(dc.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil, queue: .main) { [weak self] _ in self?.onUnlockOrWake() })

        // Sleep / wake — documented workspace notifications.
        let wc = NSWorkspace.shared.notificationCenter
        observers.append(wc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in self?.onLockOrSleep() })
        observers.append(wc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.onUnlockOrWake() })
        observers.append(wc.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil, queue: .main) { [weak self] _ in self?.onLockOrSleep() })
        observers.append(wc.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.onUnlockOrWake() })
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
