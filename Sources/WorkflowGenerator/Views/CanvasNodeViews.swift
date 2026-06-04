import AppKit
import SwiftUI

@MainActor
struct InfiniteCanvasGrid: View {
    let spacing: Double
    let opacity: Double
    let offset: CGSize

    var body: some View {
        Canvas { context, size in
            let spacing = CGFloat(max(spacing, 4))
            let xPhase = phase(offset.width, spacing: spacing)
            let yPhase = phase(offset.height, spacing: spacing)
            var path = Path()

            stride(from: xPhase - spacing, through: size.width + spacing, by: spacing).forEach { x in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }

            stride(from: yPhase - spacing, through: size.height + spacing, by: spacing).forEach { y in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }

            context.stroke(path, with: .color(.secondary.opacity(opacity)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    private func phase(_ value: CGFloat, spacing: CGFloat) -> CGFloat {
        let remainder = value.truncatingRemainder(dividingBy: spacing)
        return remainder >= 0 ? remainder : remainder + spacing
    }
}

struct CanvasPatternBackground: View, Equatable {
    let settings: CanvasBoardSettings
    let showsPattern: Bool
    let zoomScale: Double
    let offset: CGSize

    static func == (lhs: CanvasPatternBackground, rhs: CanvasPatternBackground) -> Bool {
        lhs.settings == rhs.settings &&
        lhs.showsPattern == rhs.showsPattern &&
        lhs.zoomScale == rhs.zoomScale &&
        lhs.offset == rhs.offset
    }

    var body: some View {
        ZStack {
            Color(hex: settings.effectiveCanvasBackgroundHex)
            if showsPattern {
                switch settings.canvasPattern {
                case .grid:
                    InfiniteCanvasGrid(
                        spacing: settings.gridSize * zoomScale,
                        opacity: settings.gridOpacity,
                        offset: offset
                    )
                case .dots:
                    InfiniteCanvasDots(
                        spacing: settings.gridSize * zoomScale,
                        opacity: settings.gridOpacity,
                        offset: offset
                    )
                case .blueprint:
                    InfiniteCanvasGrid(
                        spacing: settings.gridSize * zoomScale,
                        opacity: settings.gridOpacity * 1.25,
                        offset: offset
                    )
                    InfiniteCanvasGrid(
                        spacing: settings.gridSize * zoomScale * 4,
                        opacity: settings.gridOpacity * 1.8,
                        offset: offset
                    )
                    .tint(Color(hex: settings.themeAccentHex))
                case .none:
                    EmptyView()
                }
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

@MainActor
private struct InfiniteCanvasDots: View {
    let spacing: Double
    let opacity: Double
    let offset: CGSize

    var body: some View {
        Canvas { context, size in
            let spacing = CGFloat(max(spacing, 6))
            let xPhase = phase(offset.width, spacing: spacing)
            let yPhase = phase(offset.height, spacing: spacing)

            for x in stride(from: xPhase - spacing, through: size.width + spacing, by: spacing) {
                for y in stride(from: yPhase - spacing, through: size.height + spacing, by: spacing) {
                    let dot = Path(ellipseIn: CGRect(x: x - 1.25, y: y - 1.25, width: 2.5, height: 2.5))
                    context.fill(dot, with: .color(.secondary.opacity(opacity * 1.8)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func phase(_ value: CGFloat, spacing: CGFloat) -> CGFloat {
        let remainder = value.truncatingRemainder(dividingBy: spacing)
        return remainder >= 0 ? remainder : remainder + spacing
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: cleaned)
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)
        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }

    var hexString: String {
        let nsColor = NSColor(self).usingColorSpace(.deviceRGB) ?? .black
        let red = Int((nsColor.redComponent * 255).rounded())
        let green = Int((nsColor.greenComponent * 255).rounded())
        let blue = Int((nsColor.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

@MainActor
struct NodeCardView: View {
    let node: WorkflowNode
    let isSelected: Bool
    let isActiveTarget: Bool
    let modelName: String
    var runStatus: WorkflowNodeRunStatus?
    @State private var pulsePhase: Double = 0
    var incomingSpatialRouteCount: Int = 0
    var consistencyAssetCount: Int = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(node.title, systemImage: nodeSymbol)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if let runStatus {
                    Image(systemName: runStatusSymbol(runStatus))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(runStatusColor(runStatus))
                        .help(runStatus.rawValue)
                }
                if let url = normalizedNodeURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "link")
                            .font(.caption.weight(.semibold))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open node URL")
                }
                Text(node.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(node.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(nodeDetailText)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                if incomingSpatialRouteCount > 0 {
                    Label("\(incomingSpatialRouteCount)", systemImage: "arrow.down.to.line.compact")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .help("Receives assets through fan-to-blackhole routes")
                }
            }

            HStack {
                ModalityRow(title: "In", modalities: node.inputModalities)
                Spacer()
                if node.kind == .consistency {
                    Label("\(consistencyAssetCount)", systemImage: "archivebox")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .help("Consistency assets created by this node")
                } else {
                    ModalityRow(title: "Out", modalities: node.outputModalities)
                }
            }
        }
        .padding(12)
        .frame(width: 260, height: 150)
        .background {
            node.visualStyle.backgroundView()
                .clipShape(RoundedRectangle(cornerRadius: node.visualStyle.cornerRadius))
        }
        .overlay {
            RoundedRectangle(cornerRadius: node.visualStyle.cornerRadius)
                .stroke(node.visualStyle.strokeColor(isSelected: isSelected, isActiveTarget: isActiveTarget), lineWidth: isSelected ? 2 : node.visualStyle.strokeWidth)
        }
        .compositingGroup()
        .shadow(color: node.visualStyle.glowColor(isSelected: isSelected, isActiveTarget: isActiveTarget), radius: runStatus == .running ? node.visualStyle.glowRadius(isSelected: true, isActiveTarget: true) * (1.2 + 0.6 * sin(pulsePhase * 2 * .pi)) : node.visualStyle.glowRadius(isSelected: isSelected, isActiveTarget: isActiveTarget))
        .shadow(color: .black.opacity(isSelected ? 0.16 : 0.08), radius: isSelected ? 14 : node.visualStyle.baseShadowRadius, y: isSelected ? 4 : 3)
        .environment(\.colorScheme, node.visualStyle.preferredColorScheme ?? colorScheme)
        .animation(nil, value: isActiveTarget)
        .animation(nil, value: isSelected)
        .onAppear {
            if runStatus == .running {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulsePhase = 1
                }
            }
        }
        .onChange(of: runStatus) { _, newStatus in
            if newStatus == .running {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulsePhase = 1
                }
            } else {
                withAnimation(.default) {
                    pulsePhase = 0
                }
            }
        }
    }

    private var nodeSymbol: String {
        switch node.kind {
        case .model: "cpu"
        case .agent: "terminal"
        case .consistency: "scope"
        }
    }

    private var nodeDetailText: String {
        switch node.kind {
        case .model:
            modelName
        case .agent:
            node.agentExecutable ?? "No agent"
        case .consistency:
            "参考资料库"
        }
    }

    private var normalizedNodeURL: URL? {
        let trimmed = node.referenceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

    private func runStatusSymbol(_ status: WorkflowNodeRunStatus) -> String {
        switch status {
        case .pending: "clock"
        case .waiting: "hourglass"
        case .running: "play.circle.fill"
        case .succeeded: "checkmark.circle.fill"
        case .waitingForReview: "person.crop.circle.badge.questionmark"
        case .failed: "xmark.octagon.fill"
        case .skipped: "forward.end.circle"
        case .cancelled: "stop.circle.fill"
        }
    }

    private func runStatusColor(_ status: WorkflowNodeRunStatus) -> Color {
        switch status {
        case .pending: .secondary
        case .waiting: .orange
        case .running: .accentColor
        case .succeeded: .green
        case .waitingForReview: .orange
        case .failed: .red
        case .skipped: .secondary
        case .cancelled: .red
        }
    }
}

extension NodeVisualStyle {
    var cornerRadius: Double {
        switch self {
        case .glass: 9
        case .signal: 12
        case .paper: 8
        case .terminal: 7
        }
    }

    var strokeWidth: Double {
        switch self {
        case .signal: 1.4
        default: 1
        }
    }

    var baseShadowRadius: Double {
        switch self {
        case .glass: 10
        case .signal: 14
        case .paper: 8
        case .terminal: 12
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .paper: .light
        case .terminal: .dark
        default: nil
        }
    }

    @ViewBuilder
    func backgroundView() -> some View {
        switch self {
        case .glass:
            Rectangle().fill(.regularMaterial)
        case .signal:
            ZStack {
                Rectangle().fill(.regularMaterial)
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.18), Color.clear, Color.accentColor.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        case .paper:
            Rectangle().fill(Color(nsColor: .controlBackgroundColor).opacity(0.96))
        case .terminal:
            ZStack {
                Rectangle().fill(Color.black.opacity(0.74))
                LinearGradient(
                    colors: [Color.white.opacity(0.10), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    func strokeColor(isSelected: Bool, isActiveTarget: Bool) -> Color {
        if isSelected { return .accentColor }
        if isActiveTarget { return .yellow.opacity(0.72) }
        switch self {
        case .signal:
            return Color.accentColor.opacity(0.38)
        case .paper:
            return Color.black.opacity(0.12)
        case .terminal:
            return Color.white.opacity(0.20)
        case .glass:
            return Color.secondary.opacity(0.25)
        }
    }

    func glowColor(isSelected: Bool, isActiveTarget: Bool) -> Color {
        if isActiveTarget && !isSelected { return .yellow.opacity(0.44) }
        if self == .signal { return .accentColor.opacity(isSelected ? 0.30 : 0.18) }
        return .clear
    }

    func glowRadius(isSelected: Bool, isActiveTarget: Bool) -> Double {
        if isActiveTarget && !isSelected { return 18 }
        if self == .signal { return isSelected ? 18 : 10 }
        return 0
    }
}

@MainActor
struct AnchorDots: View {
    var body: some View {
        GeometryReader { proxy in
            let points = anchorPoints(in: proxy.size)
            ForEach(points.indices, id: \.self) { index in
                ZStack {
                    Circle()
                        .fill(Color(nsColor: .windowBackgroundColor))
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 4, height: 4)
                }
                .frame(width: 12, height: 12)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .position(points[index])
            }
        }
        .allowsHitTesting(false)
    }

    private func anchorPoints(in size: CGSize) -> [CGPoint] {
        [
            CGPoint(x: size.width / 2, y: 0),
            CGPoint(x: size.width, y: size.height / 2),
            CGPoint(x: size.width / 2, y: size.height),
            CGPoint(x: 0, y: size.height / 2)
        ]
    }
}

@MainActor
struct ConnectionPortOverlay: View {
    let targetKind: CanvasAnchorTargetKind
    let targetId: UUID
    let pendingAnchor: CanvasAnchorRef?
    let onSelect: (CanvasAnchorRef, ConnectionMode) -> Void

    var body: some View {
        GeometryReader { proxy in
            ForEach(CanvasAnchorSide.allCases, id: \.self) { side in
                let anchor = CanvasAnchorRef(targetKind: targetKind, targetId: targetId, side: side)
                portControl(anchor: anchor)
                    .position(point(for: side, in: proxy.size))
            }
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func portControl(anchor: CanvasAnchorRef) -> some View {
        if pendingAnchor == nil {
            Menu {
                ForEach(ConnectionMode.allCases, id: \.rawValue) { mode in
                    Button {
                        onSelect(anchor, mode)
                    } label: {
                        Label(mode.title, systemImage: mode.symbolName)
                    }
                }
            } label: {
                ConnectionPort(isPending: false)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
        } else {
            ConnectionPort(isPending: pendingAnchor == anchor)
                .onTapGesture {
                    onSelect(anchor, .logic)
                }
        }
    }

    private func point(for side: CanvasAnchorSide, in size: CGSize) -> CGPoint {
        switch side {
        case .top:
            CGPoint(x: size.width / 2, y: 0)
        case .right:
            CGPoint(x: size.width, y: size.height / 2)
        case .bottom:
            CGPoint(x: size.width / 2, y: size.height)
        case .left:
            CGPoint(x: 0, y: size.height / 2)
        }
    }
}

@MainActor
struct ConnectionPort: View {
    let isPending: Bool
    @State private var isHovered = false
    @State private var glowPhase: CGFloat = 0

    var body: some View {
        let glow = isPending ? 0.45 + 0.55 * glowPhase : 0
        ZStack {
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor))
            Circle()
                .stroke(Color.accentColor, lineWidth: isHovered || isPending ? 2.6 : 1.8)
            Circle()
                .fill(Color.accentColor)
                .frame(width: isHovered || isPending ? 7 : 4, height: isHovered || isPending ? 7 : 4)
        }
        .frame(width: isHovered || isPending ? 20 : 14, height: isHovered || isPending ? 20 : 14)
        .contentShape(Circle())
        .shadow(color: .accentColor.opacity(glow), radius: 8)
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            if isPending {
                withAnimation(.linear(duration: 0.45).repeatForever(autoreverses: true)) {
                    glowPhase = 1
                }
            }
        }
        .onChange(of: isPending) { _, pending in
            if pending {
                withAnimation(.linear(duration: 0.45).repeatForever(autoreverses: true)) {
                    glowPhase = 1
                }
            } else {
                withAnimation(.default) {
                    glowPhase = 0
                }
            }
        }
    }
}

@MainActor
struct ModalityRow: View {
    let title: String
    let modalities: Set<Modality>

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(Array(modalities).sorted { $0.rawValue < $1.rawValue }) { modality in
                Image(systemName: modality.symbolName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
