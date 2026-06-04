import SwiftUI

@MainActor
struct ResetSettingsView: View {
    @Bindable var store: AppStore

    private var copy: AppCopy {
        AppCopy(locale: store.configuration.language)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                resetPanel(
                    title: copy.resetWorkspaceTitle,
                    description: store.selectedWorkspace == nil ? copy.resetWorkspaceUnavailable : copy.resetWorkspaceDescription,
                    icon: "rectangle.3.group",
                    isDisabled: store.selectedWorkspace == nil
                ) {
                    store.resetCurrentWorkspace()
                }

                resetPanel(
                    title: copy.resetAppTitle,
                    description: copy.resetAppDescription,
                    icon: "trash",
                    isDisabled: false
                ) {
                    store.resetAppConfiguration()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    private func resetPanel(
        title: String,
        description: String,
        icon: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.title3.bold())
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(role: .destructive, action: action) {
                Label(title, systemImage: icon)
            }
            .disabled(isDisabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }
}
