import AppKit
import SwiftUI

extension AppAppearanceMode {
    var colorScheme: ColorScheme {
        switch self {
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    var nsAppearanceName: NSAppearance.Name {
        switch self {
        case .light:
            .aqua
        case .dark:
            .darkAqua
        }
    }
}

extension CanvasBoardSettings {
    var accentColor: Color {
        Color(hex: themeAccentHex)
    }

    var nsAppearance: NSAppearance? {
        NSAppearance(named: appearanceMode.nsAppearanceName)
    }
}

extension View {
    func workflowAppearance(_ settings: CanvasBoardSettings) -> some View {
        self
            .preferredColorScheme(settings.appearanceMode.colorScheme)
            .tint(settings.accentColor)
            .accentColor(settings.accentColor)
    }
}

@MainActor
func applyWorkflowAppKitAppearance(_ settings: CanvasBoardSettings) {
    let appearance = settings.nsAppearance
    NSApp.appearance = appearance
    NSColorPanel.shared.appearance = appearance
}
