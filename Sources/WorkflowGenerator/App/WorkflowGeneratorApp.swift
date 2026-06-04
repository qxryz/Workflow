import AppKit
import SwiftUI

@main
struct WorkflowGeneratorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup("Workflow Generator") {
            ContentView(store: store)
                .frame(minWidth: 1360, minHeight: 860)
                .workflowAppearance(store.configuration.boardSettings)
                .onAppear {
                    applyAppKitAppearance()
                    setupTerminationObserver()
                }
                .onChange(of: store.configuration.boardSettings.appearanceMode) { _, _ in
                    applyAppKitAppearance()
                }
                .onChange(of: store.configuration.boardSettings.themeAccentHex) { _, _ in
                    store.applyAppearanceToChatWindows()
                }
        }
        .defaultSize(width: 1500, height: 960)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Place Model Node") {
                    store.addNode(kind: .model)
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Place Agent Node") {
                    store.addNode(kind: .agent)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Place Consistency Node") {
                    store.addNode(kind: .consistency)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView(store: store)
                .frame(minWidth: 1040, idealWidth: 1120, minHeight: 700, idealHeight: 760)
                .workflowAppearance(store.configuration.boardSettings)
                .onAppear {
                    applyAppKitAppearance()
                }
                .onChange(of: store.configuration.boardSettings.appearanceMode) { _, _ in
                    applyAppKitAppearance()
                }
        }
    }

    private func applyAppKitAppearance() {
        applyWorkflowAppKitAppearance(store.configuration.boardSettings)
        store.applyAppearanceToChatWindows()
    }

    private func setupTerminationObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                store.flushPendingSave()
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
