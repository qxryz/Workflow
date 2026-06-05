import SwiftUI

enum AgnesProviderVisuals {
    static func isAgnes(_ provider: ProviderConfig?) -> Bool {
        guard let provider else { return false }
        return isAgnes(providerName: provider.name)
    }

    static func isAgnes(providerName: String) -> Bool {
        ProviderEndpointCatalog.normalizedProviderName(providerName) == "agnes"
    }

    static func isAgnesRegistration(_ registration: RegisteredModelInterface) -> Bool {
        if let templateId = registration.templateId, templateId.hasPrefix("agnes.") {
            return true
        }
        return registration.title.localizedCaseInsensitiveContains("Agnes")
    }
}

private struct AgnesAccentLayer: View {
    let intensity: Double

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.17, blue: 0.46).opacity(0.22 * intensity),
                    Color(red: 0.98, green: 0.68, blue: 0.20).opacity(0.18 * intensity),
                    Color(red: 0.08, green: 0.63, blue: 0.86).opacity(0.20 * intensity)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            AgnesDiagonalStripes()
                .stroke(Color.white.opacity(0.18 * intensity), lineWidth: 0.8)

            AgnesDiagonalStripes(spacing: 18, inset: 4)
                .stroke(Color(red: 0.95, green: 0.17, blue: 0.46).opacity(0.16 * intensity), lineWidth: 0.7)
        }
    }
}

private struct AgnesDiagonalStripes: Shape {
    var spacing: CGFloat = 10
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let travel = rect.height + 24
        var x = rect.minX - travel + inset
        while x <= rect.maxX + travel {
            path.move(to: CGPoint(x: x, y: rect.maxY + 12))
            path.addLine(to: CGPoint(x: x + travel, y: rect.minY - 12))
            x += spacing
        }
        return path
    }
}

extension View {
    func agnesAccentBackground(
        enabled: Bool,
        isSelected: Bool = false,
        baseColor: Color,
        cornerRadius: CGFloat
    ) -> some View {
        background {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            ZStack {
                shape.fill(baseColor)
                if enabled {
                    AgnesAccentLayer(intensity: isSelected ? 1.0 : 0.72)
                        .clipShape(shape)
                }
            }
        }
    }

    func agnesAccentBorder(
        enabled: Bool,
        isSelected: Bool = false,
        fallbackColor: Color,
        cornerRadius: CGFloat
    ) -> some View {
        overlay {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            if enabled {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.17, blue: 0.46).opacity(isSelected ? 0.55 : 0.36),
                            Color(red: 0.08, green: 0.63, blue: 0.86).opacity(isSelected ? 0.50 : 0.30)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isSelected ? 1.2 : 0.9
                )
            } else {
                shape.strokeBorder(fallbackColor)
            }
        }
    }
}
