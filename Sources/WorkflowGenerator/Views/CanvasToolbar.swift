import SwiftUI
import AppKit

@MainActor
struct CanvasToolbar: View {
    @Bindable var store: AppStore
    let zoomScale: Double
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let resetView: () -> Void
    let fitContent: () -> Void
    private var copy: AppCopy { AppCopy(locale: store.configuration.language) }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                store.undoWorkflow()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 28, height: 28)
            }
            .disabled(!store.canUndo)
            .quickHelp("撤销 (\(store.undoCount)/\(store.undoMaxCount))")

            Button {
                store.redoWorkflow()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 28, height: 28)
            }
            .disabled(!store.canRedo)
            .quickHelp("重做 (\(store.redoCount)/\(store.undoMaxCount))")

            Divider().frame(height: 24)

            ToolButton(tool: .select, store: store)
            CanvasNavigationHelpButton(store: store)

            Divider().frame(height: 24)

            Menu {
                Button { store.uploadCanvasImage() } label: {
                    Label(copy.importImageToCanvas, systemImage: "photo.badge.plus")
                }
                Button { store.addConsistencyAssets(modality: .image) } label: {
                    Label(copy.imageAsReference, systemImage: "photo.on.rectangle")
                }
            } label: {
                Image(systemName: CanvasTool.image.symbolName).frame(width: 28, height: 28)
            }

            Menu {
                Button { store.uploadCanvasVideo() } label: {
                    Label(copy.importVideoToCanvas, systemImage: "video.badge.plus")
                }
                Button { store.addConsistencyAssets(modality: .video) } label: {
                    Label(copy.videoAsReference, systemImage: "film")
                }
            } label: {
                Image(systemName: CanvasTool.video.symbolName).frame(width: 28, height: 28)
            }

            Menu {
                Button { store.uploadCanvasAudio() } label: {
                    Label(copy.importAudioToCanvas, systemImage: "waveform.badge.plus")
                }
                Button { store.addConsistencyAssets(modality: .audio) } label: {
                    Label(copy.audioAsReference, systemImage: "waveform")
                }
            } label: {
                Image(systemName: CanvasTool.audio.symbolName).frame(width: 28, height: 28)
            }

            ColorToolMenu(
                title: "Artboard",
                saveTitle: copy.saveColor,
                symbolName: CanvasTool.grid.symbolName,
                colorHex: selectedElementColor(fallback: store.configuration.boardSettings.artboardColorHex),
                presets: store.configuration.boardSettings.colorPresets,
                isSelected: store.configuration.selectedCanvasTool == .grid,
                select: { store.selectCanvasTool(.grid) },
                updateColor: { store.updateArtboardColor($0) },
                savePreset: { store.saveColorPreset($0) },
                deletePreset: { store.deleteColorPreset($0) }
            )

            ShapeMenu(store: store)
            ColorToolMenu(
                title: "Pen",
                saveTitle: copy.saveColor,
                symbolName: CanvasTool.pen.symbolName,
                colorHex: store.configuration.boardSettings.penColorHex,
                presets: store.configuration.boardSettings.colorPresets,
                isSelected: store.configuration.selectedCanvasTool == .pen,
                select: { store.selectCanvasTool(.pen) },
                updateColor: { store.updatePenColor($0) },
                savePreset: { store.saveColorPreset($0) },
                deletePreset: { store.deleteColorPreset($0) }
            )

            Divider().frame(height: 24)

            ColorToolMenu(
                title: "Text",
                saveTitle: copy.saveColor,
                symbolName: "textformat",
                textLabel: "T",
                colorHex: store.configuration.boardSettings.textColorHex,
                presets: store.configuration.boardSettings.colorPresets,
                isSelected: store.configuration.selectedCanvasTool == .text,
                select: { store.selectCanvasTool(.text) },
                updateColor: { store.updateTextColor($0) },
                savePreset: { store.saveColorPreset($0) },
                deletePreset: { store.deleteColorPreset($0) }
            )

            if !store.configuration.workflow.selectedCanvasElementIds.isEmpty || !store.configuration.workflow.selectedNodeIds.isEmpty {
                Divider().frame(height: 24)
                Button(role: .destructive) {
                    DispatchQueue.main.async {
                        store.deleteSelectedCanvasItems()
                    }
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 28, height: 28)
                }
                .quickHelp("Delete selected canvas item")
            }

            Divider().frame(height: 24)

            ZoomControl(
                zoomScale: zoomScale,
                zoomIn: zoomIn,
                zoomOut: zoomOut,
                resetView: resetView,
                fitContent: fitContent
            )
        }
        .buttonStyle(.borderless)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.10))
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }

    private func selectedElementColor(fallback: String) -> String {
        guard let id = store.configuration.workflow.selectedCanvasElementId,
              let element = store.configuration.workflow.canvasElements.first(where: { $0.id == id }) else {
            return fallback
        }
        return element.colorHex
    }
}

@MainActor
struct ToolButton: View {
    let tool: CanvasTool
    @Bindable var store: AppStore
    @State private var isHovered = false

    var isSelected: Bool {
        store.configuration.selectedCanvasTool == tool
    }

    var body: some View {
        Button {
            store.selectCanvasTool(tool)
        } label: {
            Image(systemName: tool.symbolName)
                .frame(width: 28, height: 28)
                .foregroundStyle(isSelected ? Color(nsColor: .windowBackgroundColor) : Color.primary)
        }
        .background(toolBackground, in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var toolBackground: Color {
        if isSelected { return .accentColor }
        if isHovered { return .secondary.opacity(0.16) }
        return .clear
    }
}

@MainActor
struct CanvasNavigationHelpButton: View {
    @Bindable var store: AppStore
    @State private var isHovered = false
    @State private var isPresented = false

    private var isSelected: Bool {
        store.configuration.selectedCanvasTool == .move
    }

    private var usesChinese: Bool {
        store.configuration.language == .zhCN
    }

    var body: some View {
        Button {
            store.selectCanvasTool(.move)
            isPresented = true
        } label: {
            Image(systemName: "keyboard")
                .frame(width: 28, height: 28)
                .foregroundStyle(isSelected ? Color(nsColor: .windowBackgroundColor) : Color.primary)
        }
        .background(buttonBackground, in: RoundedRectangle(cornerRadius: 8))
        .buttonStyle(.borderless)
        .onHover { hovering in
            isHovered = hovering
            isPresented = hovering
        }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                Label(usesChinese ? "键盘移动画布" : "Keyboard Canvas Pan", systemImage: "keyboard")
                    .font(.headline)

                VStack(spacing: 4) {
                    HStack {
                        Spacer()
                        keycap("W")
                        Spacer()
                    }
                    HStack(spacing: 4) {
                        keycap("A")
                        keycap("S")
                        keycap("D")
                    }
                }
                .frame(maxWidth: .infinity)

                Text(usesChinese ? "鼠标拖动画布已经关闭。按住 W/A/S/D 连续平移视野，按住 Shift 可以更快移动。" : "Mouse canvas dragging is disabled. Hold W/A/S/D to smoothly pan the viewport, and hold Shift to move faster.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(usesChinese ? "鼠标拖拽现在只用于选择框、节点、资产和绘图工具。" : "Mouse dragging is reserved for selections, nodes, assets, and drawing tools.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 260)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
        }
    }

    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced().weight(.semibold))
            .frame(width: 34, height: 28)
            .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
    }

    private var buttonBackground: Color {
        if isSelected { return .accentColor }
        if isHovered || isPresented { return .secondary.opacity(0.16) }
        return .clear
    }
}

@MainActor
struct ZoomControl: View {
    let zoomScale: Double
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let resetView: () -> Void
    let fitContent: () -> Void
    @State private var isPresented = false
    @State private var isHovered = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                Text("\(Int((zoomScale * 100).rounded()))%")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .frame(width: 42, alignment: .trailing)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 28)
            .padding(.horizontal, 6)
            .background(isHovered || isPresented ? Color.secondary.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.borderless)
        .quickHelp("缩放和重置画布视图")
        .onHover { isHovered = $0 }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("画布视图", systemImage: "rectangle.dashed")
                        .font(.headline)
                    Spacer()
                    Text("\(Int((zoomScale * 100).rounded()))%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button(action: zoomOut) {
                        Image(systemName: "minus")
                            .frame(width: 34, height: 28)
                    }
                    Button(action: zoomIn) {
                        Image(systemName: "plus")
                            .frame(width: 34, height: 28)
                    }
                    Divider().frame(height: 24)
                    Button(action: fitContent) {
                        Label("适配内容", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }

                Button(action: resetView) {
                    Label("重置画布位置", systemImage: "scope")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)

                Text("缩放会围绕当前画布内容中心，避免多次缩放后找不到节点。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 260)
        }
    }
}

@MainActor
struct ColorToolMenu: View {
    let title: String
    let saveTitle: String
    let symbolName: String
    var textLabel: String?
    let colorHex: String
    let presets: [String]
    let isSelected: Bool
    let select: () -> Void
    let updateColor: (String) -> Void
    let savePreset: (String) -> Void
    let deletePreset: (String) -> Void
    @State private var isHovered = false
    @State private var isPresented = false
    @State private var draftColor: Color

    init(title: String, saveTitle: String, symbolName: String, textLabel: String? = nil, colorHex: String, presets: [String], isSelected: Bool, select: @escaping () -> Void, updateColor: @escaping (String) -> Void, savePreset: @escaping (String) -> Void, deletePreset: @escaping (String) -> Void) {
        self.title = title
        self.saveTitle = saveTitle
        self.symbolName = symbolName
        self.textLabel = textLabel
        self.colorHex = colorHex
        self.presets = presets
        self.isSelected = isSelected
        self.select = select
        self.updateColor = updateColor
        self.savePreset = savePreset
        self.deletePreset = deletePreset
        _draftColor = State(initialValue: Color(hex: colorHex))
    }

    var body: some View {
        Button {
            syncSystemColorPanelAppearance()
            select()
            draftColor = Color(hex: colorHex)
            isPresented.toggle()
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if let textLabel {
                    Text(textLabel)
                        .font(.callout.weight(.medium))
                } else {
                    Image(systemName: symbolName)
                }
                Circle()
                    .fill(Color(hex: colorHex))
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1))
                    .offset(x: 2, y: 2)
            }
            .frame(width: 28, height: 28)
            .foregroundStyle(isSelected ? Color(nsColor: .windowBackgroundColor) : Color.primary)
        }
        .background(buttonBackground, in: RoundedRectangle(cornerRadius: 8))
        .buttonStyle(.borderless)
        .onHover { hovering in
            isHovered = hovering
        }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            ColorPalettePopover(
                title: title,
                color: $draftColor,
                selectedHex: colorHex,
                presets: presets,
                saveTitle: saveTitle,
                applyColor: { updateColor($0) },
                savePreset: { savePreset($0) },
                deletePreset: { deletePreset($0) }
            )
        }
        .onChange(of: colorHex) { _, newValue in
            draftColor = Color(hex: newValue)
        }
    }

    private var buttonBackground: Color {
        if isSelected { return .accentColor }
        if isHovered { return .secondary.opacity(0.16) }
        return .clear
    }
}

@MainActor
struct ColorPalettePopover: View {
    let title: String
    @Binding var color: Color
    let selectedHex: String
    let presets: [String]
    let saveTitle: String
    let applyColor: (String) -> Void
    let savePreset: (String) -> Void
    let deletePreset: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            ColorPicker("Color", selection: Binding(
                get: { color },
                set: { newValue in
                    color = newValue
                    applyColor(newValue.hexString)
                }
            ), supportsOpacity: false)

            HStack {
                Circle()
                    .fill(Color(hex: selectedHex))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(Color.secondary.opacity(0.28)))
                Text(selectedHex.uppercased())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    savePreset(selectedHex)
                } label: {
                    Label(saveTitle, systemImage: "plus")
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 8), count: 5), spacing: 8) {
                ForEach(presets, id: \.self) { preset in
                    ZStack(alignment: .topTrailing) {
                        Button {
                            color = Color(hex: preset)
                            applyColor(preset)
                        } label: {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: preset))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(preset.caseInsensitiveCompare(selectedHex) == .orderedSame ? Color.accentColor : Color.secondary.opacity(0.28), lineWidth: 2)
                                }
                        }
                        .buttonStyle(.plain)

                        Button {
                            deletePreset(preset)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary, Color(nsColor: .windowBackgroundColor))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 5, y: -5)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 250)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1)
        }
        .preferredColorScheme(colorScheme)
    }
}

@MainActor
struct ShapeMenu: View {
    @Bindable var store: AppStore
    @State private var isHovered = false
    @State private var isPresented = false
    @State private var draftColor = Color(hex: "#111111")
    private let tools: [CanvasTool] = [.rectangle, .line, .arrow, .ellipse, .polygon, .star]
    private var copy: AppCopy { AppCopy(locale: store.configuration.language) }

    var activeShape: CanvasTool {
        tools.contains(store.configuration.selectedCanvasTool) ? store.configuration.selectedCanvasTool : .rectangle
    }

    var body: some View {
        Button {
            syncSystemColorPanelAppearance()
            draftColor = Color(hex: selectedElementColor(fallback: store.configuration.boardSettings.shapeColorHex))
            isPresented.toggle()
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: activeShape.symbolName)
                Circle()
                    .fill(Color(hex: selectedElementColor(fallback: store.configuration.boardSettings.shapeColorHex)))
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1))
                    .offset(x: 2, y: 2)
            }
            .frame(width: 28, height: 28)
            .foregroundStyle(tools.contains(store.configuration.selectedCanvasTool) ? Color(nsColor: .windowBackgroundColor) : Color.primary)
        }
        .background(shapeBackground, in: RoundedRectangle(cornerRadius: 8))
        .buttonStyle(.borderless)
        .onHover { hovering in
            isHovered = hovering
        }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                Text(copy.shape)
                    .font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 8), count: 3), spacing: 8) {
                    ForEach(tools) { tool in
                        Button {
                            store.selectCanvasTool(tool)
                        } label: {
                            Image(systemName: tool.symbolName)
                                .frame(width: 30, height: 30)
                                .background(store.configuration.selectedCanvasTool == tool ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                                    }
                }
                Divider()
                ColorPalettePopover(
                    title: "Shape Color",
                    color: $draftColor,
                    selectedHex: selectedElementColor(fallback: store.configuration.boardSettings.shapeColorHex),
                    presets: store.configuration.boardSettings.colorPresets,
                    saveTitle: copy.saveColor,
                    applyColor: { hex in
                        store.updateShapeColor(hex)
                    },
                    savePreset: { store.saveColorPreset($0) },
                    deletePreset: { store.deleteColorPreset($0) }
                )
                .frame(width: 250)
            }
            .padding(14)
            .frame(width: 280)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
        }
    }

    private var shapeBackground: Color {
        if tools.contains(store.configuration.selectedCanvasTool) { return .accentColor }
        if isHovered { return .secondary.opacity(0.16) }
        return .clear
    }

    private func selectedElementColor(fallback: String) -> String {
        guard let id = store.configuration.workflow.selectedCanvasElementId,
              let element = store.configuration.workflow.canvasElements.first(where: { $0.id == id }) else {
            return fallback
        }
        return element.colorHex
    }
}

private func syncSystemColorPanelAppearance() {
    NSColorPanel.shared.appearance = NSApp.appearance
}
