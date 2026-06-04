import SwiftUI

@MainActor
struct SettingsView: View {
    @Bindable var store: AppStore

    private var copy: AppCopy {
        AppCopy(locale: store.configuration.language)
    }

    var body: some View {
        TabView(selection: $store.settingsSelection.tab) {
            GeneralSettingsView(store: store)
                .tabItem { Label(copy.general, systemImage: "gearshape") }
                .tag(SettingsTab.general)

            AppearanceSettingsView(store: store)
                .tabItem { Label(copy.appearance, systemImage: "paintpalette") }
                .tag(SettingsTab.appearance)

            ProviderSettingsView(store: store)
                .tabItem { Label(copy.providers, systemImage: "network") }
                .tag(SettingsTab.providers)

            ModelSettingsView(store: store)
                .tabItem { Label(copy.models, systemImage: "cpu") }
                .tag(SettingsTab.models)

            WorkflowSettingsView(store: store)
                .tabItem { Label(store.configuration.language == .zhCN ? "工作流" : "Workflow", systemImage: "point.3.connected.trianglepath.dotted") }
                .tag(SettingsTab.workflow)

            AgentSettingsView(store: store)
                .tabItem { Label(copy.agents, systemImage: "terminal") }
                .tag(SettingsTab.agents)

            ResetSettingsView(store: store)
                .tabItem { Label(copy.reset, systemImage: "arrow.counterclockwise") }
                .tag(SettingsTab.reset)
        }
        .padding(.vertical, 8)
    }
}
