import SwiftUI

@MainActor
struct HelpBadge: View {
    let text: String
    @State private var isPresented = false

    var body: some View {
        Image(systemName: "questionmark.circle")
            .foregroundStyle(.secondary)
            .id(text)
            .onHover { hovering in
                isPresented = hovering
            }
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(width: 260, alignment: .leading)
            }
    }
}

private struct QuickHelpModifier: ViewModifier {
    let text: String
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isPresented = hovering
            }
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(width: 240, alignment: .leading)
            }
    }
}

extension View {
    func quickHelp(_ text: String) -> some View {
        modifier(QuickHelpModifier(text: text))
    }
}
