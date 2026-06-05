import SwiftUI

@MainActor
struct CanvasElementView: View {
    let element: CanvasElement
    let isSelected: Bool
    let isHovered: Bool
    let isDraft: Bool
    let onTextChange: (String) -> Void
    let onSizeChange: (CanvasSize) -> Void
    let onBeginResize: () -> Void
    let onOpenAsset: () -> Void
    let onConfigureLogicEdge: () -> Void
    @State private var draftText: String
    @State private var resizeStart: CanvasSize?

    init(element: CanvasElement, isSelected: Bool, isHovered: Bool, isDraft: Bool, onTextChange: @escaping (String) -> Void, onSizeChange: @escaping (CanvasSize) -> Void, onBeginResize: @escaping () -> Void, onOpenAsset: @escaping () -> Void = {}, onConfigureLogicEdge: @escaping () -> Void = {}) {
        self.element = element
        self.isSelected = isSelected
        self.isHovered = isHovered
        self.isDraft = isDraft
        self.onTextChange = onTextChange
        self.onSizeChange = onSizeChange
        self.onBeginResize = onBeginResize
        self.onOpenAsset = onOpenAsset
        self.onConfigureLogicEdge = onConfigureLogicEdge
        _draftText = State(initialValue: element.text ?? "Text")
    }

    var body: some View {
        content
            .frame(width: element.size.width, height: element.size.height)
            .contentShape(CanvasElementHitShape(element: element))
            .overlay {
                selectionOverlay
            }
            .overlay(alignment: .topTrailing) {
                if isSelected, element.kind == .artboard, !isDraft {
                    ArtboardRatioPanel(currentSize: element.size, onSizeChange: onSizeChange)
                        .offset(x: 230, y: -4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isSelected, canResize, !isDraft {
                    ResizeHandle()
                        .offset(x: 7, y: 7)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let origin = resizeStart ?? element.size
                                    if resizeStart == nil {
                                        onBeginResize()
                                    }
                                    resizeStart = origin
                                    onSizeChange(CanvasSize(
                                        width: max(minimumSize.width, origin.width + value.translation.width),
                                        height: max(minimumSize.height, origin.height + value.translation.height)
                                    ))
                                }
                                .onEnded { _ in
                                    resizeStart = nil
                                }
                        )
                }
            }
            .overlay {
                if element.isLogicConnection, !edgeLabel.isEmpty {
                    Text(edgeLabel)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.secondary.opacity(0.18)))
                        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                }
            }
            .opacity(isDraft ? 0.58 : 1)
            .shadow(color: .black.opacity(isSelected ? 0.16 : (isHovered ? 0.10 : 0.08)), radius: isSelected ? 12 : 8, y: isSelected ? 3 : 2)
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        if element.isLogicConnection {
                            onConfigureLogicEdge()
                        } else if element.assetPath != nil {
                            onOpenAsset()
                        }
                    }
            )
            .onChange(of: element.text) { _, newValue in
                draftText = newValue ?? "Text"
            }
    }

    private var borderColor: Color {
        if isSelected { return .accentColor }
        if isHovered { return .secondary.opacity(0.38) }
        return .secondary.opacity(0.18)
    }

    private var edgeLabel: String {
        element.logicEdge?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var canResize: Bool {
        ![CanvasElementKind.line, .arrow, .pen].contains(element.kind)
    }

    @ViewBuilder
    private var selectionOverlay: some View {
        if element.usesPathHitTesting {
            CanvasElementHitShape(element: element)
                .stroke(borderColor, style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: isDraft ? [6, 5] : []))
                .opacity(isSelected || isHovered || isDraft ? 1 : 0)
                .allowsHitTesting(false)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: isDraft ? [6, 5] : []))
                .allowsHitTesting(false)
        }
    }

    private var minimumSize: CGSize {
        switch element.kind {
        case .text:
            CGSize(width: 120, height: 44)
        case .artboard:
            CGSize(width: 160, height: 120)
        case .image, .video, .audio, .file:
            CGSize(width: 120, height: 80)
        default:
            CGSize(width: 44, height: 44)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch element.kind {
        case .artboard:
            ArtboardElementView(element: element)
        case .rectangle:
            RoundedRectangle(cornerRadius: 8)
                .fill(.background.opacity(0.75))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: element.colorHex), lineWidth: element.strokeWidth))
        case .ellipse:
            Ellipse()
                .fill(.background.opacity(0.75))
                .overlay(Ellipse().stroke(Color(hex: element.colorHex), lineWidth: element.strokeWidth))
        case .line:
            ConnectorLineShape(points: element.pathPoints)
                .stroke(Color(hex: element.colorHex), lineWidth: element.strokeWidth)
        case .arrow:
            if element.isLogicConnection {
                LogicConnectorArrowShape(points: element.pathPoints)
                    .stroke(Color(hex: element.colorHex), style: StrokeStyle(lineWidth: element.strokeWidth, lineCap: .round, lineJoin: .round))
                    .modifier(BlinkingConnectionModifier())
            } else {
                ConnectorArrowShape(points: element.pathPoints)
                    .stroke(Color(hex: element.colorHex), style: StrokeStyle(lineWidth: element.strokeWidth, lineCap: .round, lineJoin: .round))
            }
        case .polygon:
            PolygonShape(sides: 3)
                .fill(.background.opacity(0.75))
                .overlay(PolygonShape(sides: 3).stroke(Color(hex: element.colorHex), lineWidth: element.strokeWidth))
                .padding(8)
        case .star:
            StarShape()
                .fill(.background.opacity(0.75))
                .overlay(StarShape().stroke(Color(hex: element.colorHex), lineWidth: element.strokeWidth))
                .padding(8)
        case .pen:
            PenStrokeShape(points: element.pathPoints)
                .stroke(Color(hex: element.colorHex), style: StrokeStyle(lineWidth: element.strokeWidth, lineCap: .round, lineJoin: .round))
                .padding(12)
        case .text:
            if let assetPath = element.assetPath {
                MediaPreview(path: assetPath, modality: MediaAsset.inferModality(path: assetPath))
            } else {
                TextField("Text", text: $draftText)
                    .font(.title3)
                    .foregroundStyle(Color(hex: element.colorHex))
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
                    .onSubmit {
                        onTextChange(draftText)
                    }
            }
        case .image:
            MediaPreview(path: element.assetPath, modality: .image)
        case .video:
            MediaPreview(path: element.assetPath, modality: .video)
        case .audio:
            MediaPreview(path: element.assetPath, modality: .audio)
        case .file:
            MediaPreview(path: element.assetPath, modality: .file)
        }
    }
}

private struct CanvasElementHitShape: Shape {
    let element: CanvasElement

    func path(in rect: CGRect) -> Path {
        guard element.usesPathHitTesting else {
            return Path(CGRect(origin: .zero, size: rect.size))
        }
        let strokeWidth = max(14, element.strokeWidth + 12)
        let style = StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
        switch element.kind {
        case .line:
            return ConnectorLineShape(points: element.pathPoints).path(in: rect).strokedPath(style)
        case .arrow:
            let basePath = element.isLogicConnection
                ? LogicConnectorArrowShape(points: element.pathPoints).path(in: rect)
                : ConnectorArrowShape(points: element.pathPoints).path(in: rect)
            return basePath.strokedPath(style)
        case .pen:
            return PenStrokeShape(points: element.pathPoints).path(in: rect).strokedPath(style)
        default:
            return Path(CGRect(origin: .zero, size: rect.size))
        }
    }
}

private extension CanvasElement {
    var usesPathHitTesting: Bool {
        kind == .line || kind == .arrow || kind == .pen
    }
}

@MainActor
struct ArtboardElementView: View {
    let element: CanvasElement

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(hex: element.colorHex).opacity(element.colorHex == "#FFFFFF" ? 0.92 : 0.10))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(hex: element.colorHex).opacity(0.65))
            }
            .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }
}

@MainActor
struct ArtboardRatioPanel: View {
    let currentSize: CanvasSize
    let onSizeChange: (CanvasSize) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(ArtboardPreset.allCases.filter { $0 != .custom }) { preset in
                let size = adjustedSize(for: preset)
                Button {
                    onSizeChange(size)
                } label: {
                    HStack {
                        Image(systemName: "rectangle")
                        Text(preset.title)
                        Text("\(Int(size.width))*\(Int(size.height))")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .frame(width: 210)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.18))
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
    }

    private func adjustedSize(for preset: ArtboardPreset) -> CanvasSize {
        let ratio = max(preset.size.width / preset.size.height, 0.01)
        let area = max(currentSize.width * currentSize.height, 1)
        let width = sqrt(area * ratio)
        let height = width / ratio
        return CanvasSize(width: width.rounded(), height: height.rounded())
    }
}

@MainActor
struct MediaPreview: View {
    let path: String?
    let modality: Modality

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.background.opacity(0.75))
            if modality == .image,
               let path,
               let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: mediaSymbol)
                        .font(modality == .file ? .system(size: 34, weight: .semibold) : .title)
                    Text(path.map { URL(filePath: $0).lastPathComponent } ?? modality.title)
                        .font(.caption)
                        .lineLimit(1)
                    if modality == .file, let path {
                        Text(isDirectory(path) ? "Folder" : "File")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.secondary)
                .padding(10)
            }
        }
    }

    private var mediaSymbol: String {
        switch modality {
        case .image:
            return "photo"
        case .video:
            return "play.rectangle"
        case .audio:
            return "waveform"
        case .file:
            if let path, isDirectory(path) {
                return "folder.fill"
            }
            return "doc"
        default:
            return "doc"
        }
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

@MainActor
struct ResizeHandle: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(nsColor: .windowBackgroundColor))
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.accentColor, lineWidth: 1.4)
            Image(systemName: "arrow.down.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 14, height: 14)
        .contentShape(Rectangle())
    }
}

struct GeneratedAssetSpawnModifier: ViewModifier {
    let isSettled: Bool
    let startOffset: CGSize

    func body(content: Content) -> some View {
        content
            .offset(isSettled ? .zero : startOffset)
            .scaleEffect(isSettled ? 1 : 0.36)
            .opacity(isSettled ? 1 : 0.1)
            .blur(radius: isSettled ? 0 : 1.4)
    }
}
