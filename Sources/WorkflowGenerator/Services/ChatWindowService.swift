import AppKit
import SwiftUI

@MainActor
final class ChatWindowService {
    private var windows: [UUID: NSWindowController] = [:]

    func open(store: AppStore, nodeId: UUID) {
        if let controller = windows[nodeId] {
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let nodeTitle = store.configuration.workflow.nodes.first(where: { $0.id == nodeId })?.title ?? "Node Chat"
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(nodeTitle) Chat"
        window.center()
        applyAppearance(to: window, store: store)
        window.contentView = NSHostingView(rootView: hostedChatView(store: store, nodeId: nodeId))

        let controller = NSWindowController(window: window)
        windows[nodeId] = controller
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.windows[nodeId] = nil
            }
        }
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applyAppearance(store: AppStore) {
        for (nodeId, controller) in windows {
            guard let window = controller.window else { continue }
            applyAppearance(to: window, store: store)
            window.contentView = NSHostingView(rootView: hostedChatView(store: store, nodeId: nodeId))
        }
    }

    private func hostedChatView(store: AppStore, nodeId: UUID) -> some View {
        NodeChatWorkspaceView(store: store, nodeId: nodeId)
            .workflowAppearance(store.configuration.boardSettings)
    }

    private func applyAppearance(to window: NSWindow, store: AppStore) {
        window.appearance = store.configuration.boardSettings.nsAppearance
    }
}
