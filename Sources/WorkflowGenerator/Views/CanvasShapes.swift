import SwiftUI

enum ConnectionMode: String, CaseIterable {
    case logic
    case regular

    var title: String {
        switch self {
        case .logic: "逻辑箭头"
        case .regular: "普通箭头"
        }
    }

    var symbolName: String {
        switch self {
        case .logic: "bolt.horizontal.circle"
        case .regular: "arrow.up.right"
        }
    }
}

struct ConnectorLineShape: Shape {
    let points: [CanvasPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = point(at: 0, fallback: CGPoint(x: rect.minX, y: rect.maxY))
        let end = point(at: 1, fallback: CGPoint(x: rect.maxX, y: rect.minY))
        path.move(to: start)
        path.addLine(to: end)
        return path
    }

    private func point(at index: Int, fallback: CGPoint) -> CGPoint {
        guard points.indices.contains(index) else { return fallback }
        return CGPoint(x: points[index].x, y: points[index].y)
    }
}

struct ConnectorArrowShape: Shape {
    let points: [CanvasPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = point(at: 0, fallback: CGPoint(x: rect.minX, y: rect.maxY))
        let end = point(at: 1, fallback: CGPoint(x: rect.maxX, y: rect.minY))
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = 16.0
        let spread = 0.72
        path.move(to: start)
        path.addLine(to: end)
        path.move(to: CGPoint(x: end.x - cos(angle - spread) * length, y: end.y - sin(angle - spread) * length))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: end.x - cos(angle + spread) * length, y: end.y - sin(angle + spread) * length))
        return path
    }

    private func point(at index: Int, fallback: CGPoint) -> CGPoint {
        guard points.indices.contains(index) else { return fallback }
        return CGPoint(x: points[index].x, y: points[index].y)
    }
}

struct BlinkingConnectorArrowShape: Shape {
    let points: [CanvasPoint]

    func path(in rect: CGRect) -> Path {
        ConnectorArrowShape(points: points).path(in: rect)
    }
}

struct LogicConnectorArrowShape: Shape {
    let points: [CanvasPoint]

    func path(in rect: CGRect) -> Path {
        let start = point(at: 0, fallback: CGPoint(x: rect.minX, y: rect.maxY))
        let end = point(at: 1, fallback: CGPoint(x: rect.maxX, y: rect.minY))
        let control = controls(from: start, to: end)
        let tangent = CGPoint(x: end.x - control.second.x, y: end.y - control.second.y)
        let angle = atan2(tangent.y, tangent.x)
        let length = 17.0
        let spread = 0.68

        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: control.first, control2: control.second)
        path.move(to: CGPoint(x: end.x - cos(angle - spread) * length, y: end.y - sin(angle - spread) * length))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: end.x - cos(angle + spread) * length, y: end.y - sin(angle + spread) * length))
        return path
    }

    private func controls(from start: CGPoint, to end: CGPoint) -> (first: CGPoint, second: CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let horizontalBias = max(52, min(abs(dx) * 0.48, 220))
        let verticalBias = max(36, min(abs(dy) * 0.28, 160))
        if abs(dx) >= abs(dy) {
            let direction = dx >= 0 ? 1.0 : -1.0
            return (
                CGPoint(x: start.x + horizontalBias * direction, y: start.y + dy * 0.12),
                CGPoint(x: end.x - horizontalBias * direction, y: end.y - dy * 0.12)
            )
        } else {
            let direction = dy >= 0 ? 1.0 : -1.0
            return (
                CGPoint(x: start.x + dx * 0.16, y: start.y + verticalBias * direction),
                CGPoint(x: end.x - dx * 0.16, y: end.y - verticalBias * direction)
            )
        }
    }

    private func point(at index: Int, fallback: CGPoint) -> CGPoint {
        guard points.indices.contains(index) else { return fallback }
        return CGPoint(x: points[index].x, y: points[index].y)
    }
}

struct BlinkingConnectionModifier: ViewModifier {
    @State private var phase: Bool = false

    func body(content: Content) -> some View {
        content
            .opacity(phase ? 1.0 : 0.55)
            .shadow(color: .accentColor.opacity(phase ? 1.0 : 0.55), radius: 7)
            .onAppear {
                withAnimation(.linear(duration: 0.63).repeatForever(autoreverses: true)) {
                    phase = true
                }
            }
    }
}

struct PendingConnectionPreviewModifier: ViewModifier {
    let isLogic: Bool

    func body(content: Content) -> some View {
        if isLogic {
            content.modifier(BlinkingConnectionModifier())
        } else {
            content
        }
    }
}

struct PolygonShape: Shape {
    let sides: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for index in 0..<max(sides, 3) {
            let angle = (Double(index) / Double(max(sides, 3)) * 2 * .pi) - .pi / 2
            let point = CGPoint(x: center.x + Darwin.cos(angle) * radius, y: center.y + sin(angle) * radius)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.42
        var path = Path()
        for index in 0..<10 {
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = (Double(index) / 10 * 2 * .pi) - .pi / 2
            let point = CGPoint(x: center.x + Darwin.cos(angle) * radius, y: center.y + sin(angle) * radius)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

struct PenStrokeShape: Shape {
    let points: [CanvasPoint]

    func path(in rect: CGRect) -> Path {
        if points.count > 1 {
            var path = Path()
            let cgPoints = points.map { CGPoint(x: $0.x, y: $0.y) }
            path.move(to: cgPoints[0])
            guard cgPoints.count > 2 else {
                path.addLine(to: cgPoints[1])
                return path
            }
            for index in 1..<(cgPoints.count - 1) {
                let current = cgPoints[index]
                let next = cgPoints[index + 1]
                let midpoint = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
                path.addQuadCurve(to: midpoint, control: current)
            }
            path.addLine(to: cgPoints[cgPoints.count - 1])
            return path
        }
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY),
            control2: CGPoint(x: rect.minX + rect.width * 0.65, y: rect.maxY)
        )
        return path
    }
}
