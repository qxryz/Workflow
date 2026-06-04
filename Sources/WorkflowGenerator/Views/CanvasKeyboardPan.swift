import AppKit

/// Holds the WASD-pan keyboard controller for `CanvasView`.
///
/// Owns the NSEvent monitors, the active-key set, and the 60 Hz panning timer.
/// Reports movement back through `onPan` so the view layer can stay focused
/// on rendering and viewport persistence.
@MainActor
final class CanvasKeyboardPanController {
    /// Pixel speed per second when no modifier is held.
    private static let baseSpeed: Double = 820
    /// Pixel speed per second when Shift is held.
    private static let shiftedSpeed: Double = 1800
    private static let panKeys: Set<String> = ["w", "a", "s", "d"]
    private static let timerInterval: TimeInterval = 1.0 / 60.0
    private static let maxElapsedSeconds: TimeInterval = 1.0 / 20.0

    var onPan: ((CGSize) -> Void)?
    /// Lets the view say "ignore keys" while a text field is focused.
    var isEditingText: () -> Bool = { false }

    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var activeKeys: Set<String> = []
    private var timer: Timer?
    private var lastTickUptime: TimeInterval?

    func install() {
        guard keyDownMonitor == nil else { return }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyUp(event)
        }
    }

    func remove() {
        if let keyDownMonitor { NSEvent.removeMonitor(keyDownMonitor) }
        if let keyUpMonitor { NSEvent.removeMonitor(keyUpMonitor) }
        keyDownMonitor = nil
        keyUpMonitor = nil
        stop()
    }

    /// Reset internal state. Call when the canvas view disappears.
    func stop() {
        timer?.invalidate()
        timer = nil
        activeKeys.removeAll()
        lastTickUptime = nil
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard shouldHandle(event), let key = panKey(from: event) else {
            if isEditingText() { stop() }
            return event
        }
        activeKeys.insert(key)
        startTimer()
        return nil
    }

    private func handleKeyUp(_ event: NSEvent) -> NSEvent? {
        guard let key = panKey(from: event) else { return event }
        activeKeys.remove(key)
        if activeKeys.isEmpty { stop() }
        return nil
    }

    private func shouldHandle(_ event: NSEvent) -> Bool {
        guard !event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.control),
              !event.modifierFlags.contains(.option),
              !isEditingText() else { return false }
        return true
    }

    private func panKey(from event: NSEvent) -> String? {
        guard let key = event.charactersIgnoringModifiers?.lowercased(),
              Self.panKeys.contains(key) else { return nil }
        return key
    }

    private func startTimer() {
        guard timer == nil else { return }
        lastTickUptime = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: Self.timerInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard !activeKeys.isEmpty, !isEditingText() else {
            stop()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(now - (lastTickUptime ?? now), Self.maxElapsedSeconds)
        lastTickUptime = now
        let speed = NSEvent.modifierFlags.contains(.shift) ? Self.shiftedSpeed : Self.baseSpeed
        let distance = speed * elapsed
        var x = (activeKeys.contains("a") ? distance : 0) - (activeKeys.contains("d") ? distance : 0)
        var y = (activeKeys.contains("w") ? distance : 0) - (activeKeys.contains("s") ? distance : 0)
        if x != 0, y != 0 {
            // Diagonal pan: normalize so √2 scaling doesn't overshoot.
            x *= 0.7071
            y *= 0.7071
        }
        onPan?(CGSize(width: x, height: y))
    }
}
