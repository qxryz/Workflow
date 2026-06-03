import AppKit
import QuickLook
import SwiftUI

@MainActor
struct CanvasView: View {
    @Bindable var store: AppStore
    let inspectorExpanded: Bool
    var onTapEmptyCanvas: (() -> Void)? = nil
    @State private var dragOrigins: [UUID: CanvasPoint] = [:]
    @State private var elementDragOrigins: [UUID: CanvasPoint] = [:]
    @State private var hoveredElementId: UUID?
    @State private var draftElement: CanvasElement?
    @State private var draftStart: CGPoint?
    @State private var selectionRect: CGRect?
    @State private var selectionStart: CGPoint?
    @State private var penPoints: [CGPoint] = []
    @State private var lastBatchTranslation: CGSize = .zero
    @State private var canvasOffset = CGSize(width: 10000, height: 10000)
    @State private var pendingConnection: CanvasAnchorRef?
    @State private var pendingConnectionMode: ConnectionMode = .logic
    @State private var hoverCanvasPoint: CGPoint?
    @State private var zoomScale: Double = 1
    @State private var viewportSize: CGSize = .zero
    @State private var isDraggingCanvasItem = false
    @State private var previewURL: URL?
    @State private var spawnedElementIds: Set<UUID> = []
    @State private var absorbingNodeId: UUID?
    @State private var fileDropTargetNodeId: UUID?
    @State private var keyboardPan = CanvasKeyboardPanController()
    @State private var shortcutKeyDownMonitor: Any?
    @State private var editingLogicEdgeId: UUID?
    @State private var loadedViewportWorkflowId: UUID?
    private let canvasSize = CGSize(width: 20000, height: 20000)
    private var canvasOrigin: CGPoint {
        CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
    }

    private var spatialPreviewRoutes: [SpatialArtifactRoute] {
        store.previewSpatialArtifactRoutes()
    }

    private var spatialRouteCountByNodeId: [UUID: Int] {
        Dictionary(grouping: spatialPreviewRoutes, by: \.targetNodeId)
            .mapValues(\.count)
    }

    // MARK: - Viewport Culling

    private var viewportRect: CGRect {
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return CGRect(x: -50000, y: -50000, width: 100000, height: 100000)
        }
        let scale = max(zoomScale, 0.01)
        return CGRect(
            x: canvasOrigin.x - canvasOffset.width / scale,
            y: canvasOrigin.y - canvasOffset.height / scale,
            width: viewportSize.width / scale,
            height: viewportSize.height / scale
        )
    }

    private var cullingRect: CGRect {
        viewportRect.insetBy(dx: -600, dy: -600)
    }

    private var visibleNodes: [WorkflowNode] {
        let rect = cullingRect
        return store.configuration.workflow.nodes.filter { node in
            rect.intersects(nodeBounds(node))
        }
    }

    private var visibleElements: [CanvasElement] {
        let rect = cullingRect
        return store.configuration.workflow.canvasElements.filter { element in
            rect.intersects(elementBounds(element))
        }
    }

    private func nodeBounds(_ node: WorkflowNode) -> CGRect {
        let w: CGFloat = node.kind == .consistency ? 340 : 260
        let h: CGFloat = node.kind == .consistency ? 340 : 150
        return CGRect(x: node.position.x - w / 2, y: node.position.y - h / 2, width: w, height: h)
    }

    private func elementBounds(_ element: CanvasElement) -> CGRect {
        CGRect(
            x: element.position.x - element.size.width / 2,
            y: element.position.y - element.size.height / 2,
            width: element.size.width,
            height: element.size.height
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                CanvasPatternBackground(
                    settings: store.configuration.boardSettings,
                    showsPattern: store.configuration.showsCanvasGrid,
                    zoomScale: zoomScale,
                    offset: gridOffset
                )
                .equatable()
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(viewportCanvasGesture)
                canvasContent
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
            .overlay(alignment: .bottom) {
                CanvasToolbar(
                    store: store,
                    zoomScale: zoomScale,
                    zoomIn: { setZoom(zoomScale + 0.1) },
                    zoomOut: { setZoom(zoomScale - 0.1) },
                    resetView: { resetCanvasView() },
                    fitContent: { fitCanvasContent() }
                )
                .padding(.bottom, 18)
                .padding(.trailing, inspectorExpanded ? 386 : 0)
                .animation(.snappy(duration: 0.22), value: inspectorExpanded)
                .zIndex(20)
            }
            .overlay(alignment: .center) {
                if store.configuration.workflow.nodes.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "rectangle.3.group")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary.opacity(0.5))
                        Text("画布为空")
                            .font(.title2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("⌘N 放置模型节点   ⇧⌘N 放置 Agent 节点")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .monospaced()
                    }
                    .padding(40)
                    .background(.regularMaterial.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let element = editingLogicEdgeElement {
                    LogicEdgeConfigurationCard(
                        element: element,
                        sourceTitle: nodeTitle(for: element.startAnchor?.targetId),
                        targetTitle: nodeTitle(for: element.endAnchor?.targetId),
                        onSave: { configuration in
                            store.updateLogicEdgeConfiguration(id: element.id, configuration: configuration)
                            editingLogicEdgeId = nil
                        },
                        onCancel: {
                            editingLogicEdgeId = nil
                        }
                    )
                    .padding(.top, 18)
                    .padding(.trailing, inspectorExpanded ? 398 : 18)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(80)
                }
            }
            .onAppear {
                viewportSize = proxy.size
                loadCanvasViewport(force: true)
                installKeyboardHandlers()
            }
            .onDisappear {
                persistCanvasViewport()
                removeKeyboardHandlers()
            }
            .onChange(of: proxy.size) { _, newValue in
                viewportSize = newValue
            }
            .onChange(of: store.configuration.workflow.id) { _, _ in
                loadCanvasViewport(force: true)
            }
            .dropDestination(for: URL.self) { urls, location in
                guard fileDropTargetNodeId == nil else { return true }
                let point = snappedCanvasPoint(canvasPoint(from: location))
                store.addDroppedFilesToCanvas(urls, at: point)
                playCanvasFeedback(named: "Pop")
                return true
            }
        }
        .background(Color(hex: store.configuration.boardSettings.effectiveCanvasBackgroundHex))
        .quickLookPreview($previewURL)
    }

    private var canvasContent: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: canvasSize.width, height: canvasSize.height)
                .contentShape(Rectangle())
                .gesture(canvasGesture)
                .contextMenu {
                    canvasContextMenu()
                }
                .onContinuousHover(coordinateSpace: .local) { phase in
                    if case .active(let location) = phase {
                        hoverCanvasPoint = snappedCanvasPoint(location)
                    }
                }

            if let pendingConnection,
               let start = anchorPoint(for: pendingConnection),
               let end = hoverCanvasPoint {
                ConnectorArrowShape(points: [
                    CanvasPoint(x: start.x, y: start.y),
                    CanvasPoint(x: end.x, y: end.y)
                ])
                .stroke(pendingConnectionMode == .logic ? Color(hex: store.configuration.boardSettings.penColorHex) : Color(hex: store.configuration.boardSettings.shapeColorHex), style: StrokeStyle(lineWidth: pendingConnectionMode == .logic ? 3 : 2.4, lineCap: .round, lineJoin: .round))
                .modifier(PendingConnectionPreviewModifier(isLogic: pendingConnectionMode == .logic))
                .allowsHitTesting(false)
                .zIndex(60)
            }

            ForEach(spatialPreviewRoutes) { route in
                if let endpoints = spatialRouteEndpoints(route) {
                    ConnectorArrowShape(points: [
                        CanvasPoint(x: endpoints.start.x, y: endpoints.start.y),
                        CanvasPoint(x: endpoints.end.x, y: endpoints.end.y)
                    ])
                    .stroke(Color.accentColor.opacity(0.32), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round, dash: [5, 7]))
                    .shadow(color: Color.accentColor.opacity(0.16), radius: 8)
                    .allowsHitTesting(false)
                    .zIndex(38)
                }
            }

            if let draftElement {
                CanvasElementView(
                    element: draftElement,
                    isSelected: true,
                    isHovered: true,
                    isDraft: true,
                    onTextChange: { _ in },
                    onSizeChange: { _ in },
                    onBeginResize: { }
                )
                .position(x: draftElement.position.x, y: draftElement.position.y)
                .allowsHitTesting(false)
                .zIndex(45)
            }

            if let selectionRect {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay(Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .position(x: selectionRect.midX, y: selectionRect.midY)
                    .allowsHitTesting(false)
                    .zIndex(50)
            }

            ForEach(visibleElements) { element in
                CanvasElementView(
                    element: element,
                    isSelected: store.configuration.workflow.selectedCanvasElementIds.contains(element.id),
                    isHovered: !isDraggingCanvasItem && hoveredElementId == element.id,
                    isDraft: false,
                    onTextChange: { text in
                        store.updateCanvasElementText(id: element.id, text: text)
                    },
                    onSizeChange: { size in
                        store.updateCanvasElementSize(id: element.id, size: size)
                    },
                    onBeginResize: {
                        store.recordUndoSnapshot()
                    },
                    onOpenAsset: {
                        openAssetPreview(path: element.assetPath)
                    },
                    onConfigureLogicEdge: {
                        editingLogicEdgeId = element.id
                    }
                )
                .modifier(GeneratedAssetSpawnModifier(
                    isSettled: spawnedElementIds.contains(element.id) || element.sourceNodeId == nil,
                    startOffset: spawnStartOffset(for: element)
                ))
                .position(x: element.position.x, y: element.position.y)
                .gesture(elementDragGesture(for: element))
                .onTapGesture {
                    store.selectCanvasElement(element.id)
                }
                .contextMenu {
                    canvasElementContextMenu(element)
                }
                .onHover { hovering in
                    guard !isDraggingCanvasItem else { return }
                    hoveredElementId = hovering ? element.id : nil
                }
                .onAppear {
                    animateSpawnIfNeeded(element)
                }
                .zIndex(element.isLogicConnection ? 40 : 0)

                if !isDraggingCanvasItem && shouldShowPorts(for: element) {
                    ConnectionPortOverlay(targetKind: .element, targetId: element.id, pendingAnchor: pendingConnection) { anchor, mode in
                        handleConnectionPort(anchor, mode: mode)
                    }
                    .frame(width: element.size.width, height: element.size.height)
                    .position(x: element.position.x, y: element.position.y)
                    .zIndex(55)
                }
            }

            ForEach(visibleNodes) { node in
                if shouldShowBlackHole(for: node) {
                    BlackHoleZoneView(
                        radius: node.blackHoleRadius,
                        isActive: absorbingNodeId == node.id || fileDropTargetNodeId == node.id || (spatialRouteCountByNodeId[node.id] ?? 0) > 0,
                        isEnabled: node.blackHoleEnabled
                    )
                    .position(x: node.position.x, y: node.position.y)
                    .allowsHitTesting(false)
                    .zIndex(5)
                }

                if store.configuration.workflow.selectedNodeIds.contains(node.id) {
                    EjectionFanPreview(
                        angleDegrees: node.ejectionAngleDegrees,
                        spreadDegrees: node.ejectionSpreadDegrees,
                        force: node.ejectionForce,
                        color: Color(hex: store.configuration.boardSettings.themeAccentHex)
                    )
                    .frame(width: 780, height: 780)
                    .position(x: node.position.x, y: node.position.y)
                    .allowsHitTesting(false)
                    .zIndex(8)
                }

                NodeCardView(
                    node: node,
                    isSelected: store.configuration.workflow.selectedNodeIds.contains(node.id),
                    isActiveTarget: absorbingNodeId == node.id || fileDropTargetNodeId == node.id,
                    modelName: store.modelName(for: node.modelId),
                    runStatus: workflowRunStatus(for: node.id),
                    incomingSpatialRouteCount: spatialRouteCountByNodeId[node.id] ?? 0,
                    consistencyAssetCount: store.consistencyAssetCount(for: node.id)
                )
                .position(x: node.position.x, y: node.position.y)
                .gesture(nodeDragGesture(for: node))
                .dropDestination(for: URL.self) { urls, _ in
                    store.attachFileURLs(urls, to: node.id)
                    playCanvasFeedback(named: "Pop")
                    return true
                } isTargeted: { isTargeted in
                    fileDropTargetNodeId = isTargeted ? node.id : (fileDropTargetNodeId == node.id ? nil : fileDropTargetNodeId)
                }
                .onTapGesture {
                    store.selectNode(node.id)
                }
                .contextMenu {
                    nodeContextMenu(node)
                }
                .zIndex(10)

                if (!isDraggingCanvasItem && store.configuration.workflow.selectedNodeIds.contains(node.id) && node.kind != .consistency) || pendingConnection != nil {
                    ConnectionPortOverlay(targetKind: .node, targetId: node.id, pendingAnchor: pendingConnection) { anchor, mode in
                        handleConnectionPort(anchor, mode: mode)
                    }
                    .frame(width: 260, height: 150)
                    .position(x: node.position.x, y: node.position.y)
                    .zIndex(55)
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .scaleEffect(zoomScale, anchor: .center)
        .offset(x: canvasOffset.width - canvasOrigin.x, y: canvasOffset.height - canvasOrigin.y)
        .transaction { transaction in
            if isDraggingCanvasItem || store.configuration.selectedCanvasTool == .move || store.configuration.selectedCanvasTool == .select {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var canvasGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                handleCanvasGestureChanged(start: value.startLocation, current: value.location, translation: value.translation)
            }
            .onEnded { value in
                handleCanvasGestureEnded(start: value.startLocation, current: value.location)
            }
    }

    private var viewportCanvasGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let start = canvasPoint(from: value.startLocation)
                let current = canvasPoint(from: value.location)
                handleCanvasGestureChanged(start: start, current: current, translation: value.translation)
            }
            .onEnded { value in
                let start = canvasPoint(from: value.startLocation)
                let current = canvasPoint(from: value.location)
                handleCanvasGestureEnded(start: start, current: current)
            }
    }

    private func handleCanvasGestureChanged(start: CGPoint, current: CGPoint, translation: CGSize) {
        withoutDragAnimation {
            if store.configuration.selectedCanvasTool == .select {
                let start = selectionStart ?? snapped(start)
                selectionStart = start
                selectionRect = normalizedRect(from: start, to: snapped(current))
                return
            }
            if store.configuration.selectedCanvasTool == .pen {
                appendPenPoint(current, start: start)
                draftElement = makePenDraft(points: penPoints)
                return
            }
            let tool = store.configuration.selectedCanvasTool
            guard let kind = draftKind(for: tool) else {
                if translation.width == 0, translation.height == 0 {
                    store.configuration.workflow.selectedCanvasElementId = nil
                }
                return
            }
            let start = draftStart ?? toolPoint(start, for: tool)
            draftStart = start
            draftElement = makeDraftElement(kind: kind, from: start, to: toolPoint(current, for: tool))
        }
    }

    private func handleCanvasGestureEnded(start: CGPoint, current: CGPoint) {
        if store.configuration.selectedCanvasTool == .select {
            if let selectionRect, selectionRect.width > 4 || selectionRect.height > 4 {
                store.selectItems(in: selectionRect)
            } else {
                store.clearCanvasSelection()
                onTapEmptyCanvas?()
            }
            selectionStart = nil
            self.selectionRect = nil
            return
        }
        if store.configuration.selectedCanvasTool == .pen {
            store.createPenElement(points: penPoints)
            penPoints = []
            draftElement = nil
            return
        }
        guard draftElement != nil else {
            draftStart = nil
            return
        }
        let tool = store.configuration.selectedCanvasTool
        let start = draftStart ?? toolPoint(start, for: tool)
        store.createCanvasElement(tool: tool, from: start, to: toolPoint(current, for: tool))
        draftStart = nil
        draftElement = nil
    }

    @ViewBuilder
    private func nodeContextMenu(_ node: WorkflowNode) -> some View {
        Button {
            store.copyCanvasItems(fallbackNodeId: node.id)
        } label: {
            Label(menuText("复制节点", "Copy Node"), systemImage: "doc.on.doc")
        }
        Button {
            store.cutCanvasItems(fallbackNodeId: node.id)
        } label: {
            Label(menuText("剪切节点", "Cut Node"), systemImage: "scissors")
        }
        Button {
            store.pasteCanvasItems(at: node.position)
        } label: {
            Label(menuText("粘贴到这里", "Paste Here"), systemImage: "doc.on.clipboard")
        }
        .disabled(!store.canPasteCanvasItems)
        Divider()
        Button(role: .destructive) {
            store.cutCanvasItems(fallbackNodeId: node.id)
        } label: {
            Label(menuText("删除节点", "Delete Node"), systemImage: "trash")
        }
    }

    @ViewBuilder
    private func canvasElementContextMenu(_ element: CanvasElement) -> some View {
        if element.isLogicConnection {
            Button {
                editingLogicEdgeId = element.id
            } label: {
                Label(menuText("配置逻辑箭头", "Configure Logic Edge"), systemImage: "slider.horizontal.3")
            }
            Divider()
        }
        Button {
            store.copyCanvasItems(fallbackElementId: element.id)
        } label: {
            Label(menuText("复制资产/元件", "Copy Item"), systemImage: "doc.on.doc")
        }
        Button {
            store.cutCanvasItems(fallbackElementId: element.id)
        } label: {
            Label(menuText("剪切资产/元件", "Cut Item"), systemImage: "scissors")
        }
        Button {
            store.pasteCanvasItems(at: element.position)
        } label: {
            Label(menuText("粘贴到这里", "Paste Here"), systemImage: "doc.on.clipboard")
        }
        .disabled(!store.canPasteCanvasItems)
        Divider()
        Button(role: .destructive) {
            store.cutCanvasItems(fallbackElementId: element.id)
        } label: {
            Label(menuText("删除资产/元件", "Delete Item"), systemImage: "trash")
        }
    }

    @ViewBuilder
    private func canvasContextMenu() -> some View {
        Button {
            store.pasteCanvasItems(at: hoverPastePoint())
        } label: {
            Label(menuText("粘贴", "Paste"), systemImage: "doc.on.clipboard")
        }
        .disabled(!store.canPasteCanvasItems)
        if !store.configuration.workflow.selectedNodeIds.isEmpty || !store.configuration.workflow.selectedCanvasElementIds.isEmpty {
            Divider()
            Button {
                store.copyCanvasItems()
            } label: {
                Label(menuText("复制所选", "Copy Selection"), systemImage: "doc.on.doc")
            }
            Button {
                store.cutCanvasItems()
            } label: {
                Label(menuText("剪切所选", "Cut Selection"), systemImage: "scissors")
            }
        }
    }

    private func hoverPastePoint() -> CanvasPoint {
        let point = hoverCanvasPoint ?? visibleCanvasCenter()
        return CanvasPoint(x: point.x, y: point.y)
    }

    private func menuText(_ zh: String, _ en: String) -> String {
        store.configuration.language == .zhCN ? zh : en
    }

    private func elementDragGesture(for element: CanvasElement) -> some Gesture {
        DragGesture()
            .onChanged { value in
                withoutDragAnimation {
                    if store.configuration.workflow.selectedCanvasElementIds.contains(element.id) {
                        beginCanvasItemDrag()
                        if lastBatchTranslation == .zero {
                            store.recordUndoSnapshot()
                        }
                        let delta = canvasDelta(from: value.translation, previous: lastBatchTranslation)
                        lastBatchTranslation = value.translation
                        store.moveSelectedItems(nodeDelta: delta, elementDelta: delta)
                        if element.assetPath != nil {
                            let projected = CanvasPoint(x: element.position.x + value.translation.width / max(zoomScale, 0.01), y: element.position.y + value.translation.height / max(zoomScale, 0.01))
                            absorbingNodeId = store.absorbingNodeId(for: projected, excluding: element.sourceNodeId)
                        }
                        return
                    }
                    let origin = elementDragOrigins[element.id] ?? element.position
                    if elementDragOrigins[element.id] == nil {
                        beginCanvasItemDrag()
                        store.recordUndoSnapshot()
                    }
                    elementDragOrigins[element.id] = origin
                    store.setCanvasElementPosition(
                        id: element.id,
                        position: CanvasPoint(
                            x: origin.x + value.translation.width / zoomScale,
                            y: origin.y + value.translation.height / zoomScale
                        ),
                        persist: false
                    )
                    if element.assetPath != nil {
                        let projected = CanvasPoint(x: origin.x + value.translation.width / max(zoomScale, 0.01), y: origin.y + value.translation.height / max(zoomScale, 0.01))
                        absorbingNodeId = store.absorbingNodeId(for: projected, excluding: element.sourceNodeId)
                    }
                }
            }
            .onEnded { _ in
                endCanvasItemDrag()
                lastBatchTranslation = .zero
                let ids = store.configuration.workflow.selectedCanvasElementIds.contains(element.id) ? store.configuration.workflow.selectedCanvasElementIds : [element.id]
                snapSelectedItemsIfNeeded()
                if store.absorbCanvasAssetsIfNeeded(ids: ids) {
                    playCanvasFeedback(named: "Submarine")
                } else {
                    store.save()
                }
                absorbingNodeId = nil
                elementDragOrigins[element.id] = nil
            }
    }

    private func nodeDragGesture(for node: WorkflowNode) -> some Gesture {
        DragGesture()
            .onChanged { value in
                withoutDragAnimation {
                    if store.configuration.workflow.selectedNodeIds.contains(node.id) {
                        beginCanvasItemDrag()
                        if lastBatchTranslation == .zero {
                            store.recordUndoSnapshot()
                        }
                        let delta = canvasDelta(from: value.translation, previous: lastBatchTranslation)
                        lastBatchTranslation = value.translation
                        store.moveSelectedItems(nodeDelta: delta, elementDelta: delta)
                        return
                    }
                    let origin = dragOrigins[node.id] ?? node.position
                    if dragOrigins[node.id] == nil {
                        beginCanvasItemDrag()
                        store.recordUndoSnapshot()
                    }
                    dragOrigins[node.id] = origin
                    store.setNodePosition(
                        id: node.id,
                        position: CanvasPoint(
                            x: origin.x + value.translation.width / zoomScale,
                            y: origin.y + value.translation.height / zoomScale
                        ),
                        persist: false
                    )
                }
            }
            .onEnded { _ in
                endCanvasItemDrag()
                lastBatchTranslation = .zero
                snapSelectedItemsIfNeeded()
                store.save()
                dragOrigins[node.id] = nil
            }
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    private func canvasDelta(from translation: CGSize, previous: CGSize) -> CGSize {
        CGSize(
            width: (translation.width - previous.width) / max(zoomScale, 0.01),
            height: (translation.height - previous.height) / max(zoomScale, 0.01)
        )
    }

    private func beginCanvasItemDrag() {
        if !isDraggingCanvasItem {
            isDraggingCanvasItem = true
            hoveredElementId = nil
        }
    }

    private func endCanvasItemDrag() {
        isDraggingCanvasItem = false
    }

    private func snapped(_ point: CGPoint) -> CGPoint {
        return snappedCanvasPoint(point)
    }

    private func toolPoint(_ point: CGPoint, for tool: CanvasTool) -> CGPoint {
        switch tool {
        case .line, .arrow, .pen:
            point
        default:
            snapped(point)
        }
    }

    private func snappedCanvasPoint(_ point: CGPoint) -> CGPoint {
        guard store.configuration.boardSettings.snapToGrid else { return point }
        let grid = max(store.configuration.boardSettings.gridSize, 1)
        return CGPoint(x: (point.x / grid).rounded() * grid, y: (point.y / grid).rounded() * grid)
    }

    private var gridOffset: CGSize {
        CGSize(
            width: canvasOffset.width - canvasOrigin.x * zoomScale,
            height: canvasOffset.height - canvasOrigin.y * zoomScale
        )
    }

    private func snapSelectedItemsIfNeeded() {
        guard store.configuration.boardSettings.snapToGrid else { return }
        store.snapSelectedItemsToGrid(gridSize: store.configuration.boardSettings.gridSize, persist: false)
    }

    private func canvasPoint(from viewportPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: canvasOrigin.x + (viewportPoint.x - canvasOffset.width) / max(zoomScale, 0.01),
            y: canvasOrigin.y + (viewportPoint.y - canvasOffset.height) / max(zoomScale, 0.01)
        )
    }

    private func installKeyboardHandlers() {
        keyboardPan.isEditingText = { self.isEditingTextInput }
        keyboardPan.onPan = { self.panCanvas(by: $0) }
        keyboardPan.install()
        installShortcutMonitor()
    }

    private func installShortcutMonitor() {
        // Shortcuts are intentionally separate from the pan monitor so each
        // can own a single keyDown/keyUp subscription and avoid
        // intermingling consume semantics.
        if shortcutKeyDownMonitor == nil {
            shortcutKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                self.handleShortcutKeyDown(event) ? nil : event
            }
        }
    }

    private func removeShortcutMonitor() {
        if let shortcutKeyDownMonitor { NSEvent.removeMonitor(shortcutKeyDownMonitor) }
        shortcutKeyDownMonitor = nil
    }

    private func handleShortcutKeyDown(_ event: NSEvent) -> Bool {
        guard !isEditingTextInput else { return false }
        let cmd = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if cmd, shift, chars == "n" { store.addNode(kind: .agent); return true }
        if cmd, !shift, chars == "n" { store.addNode(kind: .model); return true }
        if cmd, chars == "r" { store.startWorkflowRun(); return true }
        if event.keyCode == 51 || event.keyCode == 117 { store.deleteSelectedCanvasItems(); return true }
        if event.keyCode == 53 {
            store.configuration.workflow.selectedNodeId = nil
            store.configuration.workflow.selectedNodeIds.removeAll()
            store.configuration.workflow.selectedCanvasElementId = nil
            store.configuration.workflow.selectedCanvasElementIds.removeAll()
            return true
        }

        let toolKeys: [String: CanvasTool] = ["1": .select, "2": .move, "3": .rectangle, "4": .ellipse, "5": .line, "6": .arrow, "7": .pen, "8": .text, "9": .image]
        if let tool = toolKeys[chars], !cmd, !shift {
            store.configuration.selectedCanvasTool = tool
            return true
        }
        return false
    }

    private func removeKeyboardHandlers() {
        keyboardPan.remove()
        removeShortcutMonitor()
    }

    private var isEditingTextInput: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }

    private func panCanvas(by delta: CGSize) {
        withoutDragAnimation {
            canvasOffset = CGSize(
                width: canvasOffset.width + delta.width,
                height: canvasOffset.height + delta.height
            )
        }
        persistCanvasViewport()
    }

    private func openAssetPreview(path: String?) {
        guard let path else { return }
        previewURL = URL(filePath: path)
        playCanvasFeedback(named: "Pop")
    }

    private func animateSpawnIfNeeded(_ element: CanvasElement) {
        guard element.sourceNodeId != nil, !spawnedElementIds.contains(element.id) else { return }
        playCanvasFeedback(named: "Pop")
        withAnimation(.interpolatingSpring(stiffness: 132, damping: 15)) {
            _ = spawnedElementIds.insert(element.id)
        }
    }

    private func spawnStartOffset(for element: CanvasElement) -> CGSize {
        guard let sourceNodeId = element.sourceNodeId,
              let node = store.configuration.workflow.nodes.first(where: { $0.id == sourceNodeId }) else {
            return .zero
        }
        return CGSize(
            width: node.position.x - element.position.x,
            height: node.position.y - element.position.y
        )
    }

    private func shouldShowBlackHole(for node: WorkflowNode) -> Bool {
        node.blackHoleEnabled && (
            isDraggingCanvasItem ||
            store.configuration.workflow.selectedNodeIds.contains(node.id) ||
            absorbingNodeId == node.id ||
            fileDropTargetNodeId == node.id
        )
    }

    private func workflowRunStatus(for nodeId: UUID) -> WorkflowNodeRunStatus? {
        store.configuration.workflow.runState.records.first { $0.nodeId == nodeId }?.status
    }

    private func spatialRouteEndpoints(_ route: SpatialArtifactRoute) -> (start: CGPoint, end: CGPoint)? {
        guard let source = store.configuration.workflow.nodes.first(where: { $0.id == route.sourceNodeId }),
              let target = store.configuration.workflow.nodes.first(where: { $0.id == route.targetNodeId }) else {
            return nil
        }
        let radians = source.ejectionAngleDegrees * .pi / 180
        let start = CGPoint(
            x: source.position.x + cos(radians) * 130,
            y: source.position.y + sin(radians) * 75
        )
        return (start, CGPoint(x: target.position.x, y: target.position.y))
    }

    private func playCanvasFeedback(named name: String) {
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.play()
        } else {
            NSSound(named: "Pop")?.play()
        }
    }

    private var editingLogicEdgeElement: CanvasElement? {
        guard let editingLogicEdgeId else { return nil }
        return store.configuration.workflow.canvasElements.first { $0.id == editingLogicEdgeId && $0.isLogicConnection }
    }

    private func nodeTitle(for id: UUID?) -> String {
        guard let id,
              let node = store.configuration.workflow.nodes.first(where: { $0.id == id }) else {
            return "Unknown"
        }
        return node.title
    }

    private func setZoom(_ value: Double) {
        let nextZoom = min(2.5, max(0.35, value))
        let focus = contentBounds()?.center ?? visibleCanvasCenter()
        zoomScale = nextZoom
        centerCanvas(on: focus, zoom: nextZoom)
        persistCanvasViewport(saveToDisk: true)
    }

    private func resetCanvasView() {
        zoomScale = 1
        centerCanvas(on: contentBounds()?.center ?? CGPoint(x: 520, y: 360), zoom: 1)
        persistCanvasViewport(saveToDisk: true)
    }

    private func fitCanvasContent() {
        guard let bounds = contentBounds(), viewportSize.width > 1, viewportSize.height > 1 else {
            resetCanvasView()
            return
        }
        let padding = 160.0
        let widthScale = (viewportSize.width - padding) / max(bounds.width, 1)
        let heightScale = (viewportSize.height - padding) / max(bounds.height, 1)
        let nextZoom = min(1.4, max(0.35, min(widthScale, heightScale)))
        zoomScale = nextZoom
        centerCanvas(on: bounds.center, zoom: nextZoom)
        persistCanvasViewport(saveToDisk: true)
    }

    private func centerCanvas(on point: CGPoint, zoom: Double) {
        let viewportCenter = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        canvasOffset = CGSize(
            width: viewportCenter.x - (point.x - canvasOrigin.x) * zoom,
            height: viewportCenter.y - (point.y - canvasOrigin.y) * zoom
        )
    }

    private func loadCanvasViewport(force: Bool = false) {
        let workflowId = store.configuration.workflow.id
        guard force || loadedViewportWorkflowId != workflowId else { return }
        let viewport = store.configuration.workflow.canvasViewport
        zoomScale = min(2.5, max(0.35, viewport.zoomScale))
        canvasOffset = CGSize(width: viewport.offsetX, height: viewport.offsetY)
        loadedViewportWorkflowId = workflowId
    }

    private func persistCanvasViewport(saveToDisk: Bool = false) {
        guard loadedViewportWorkflowId == store.configuration.workflow.id else { return }
        store.updateCanvasViewport(offset: canvasOffset, zoomScale: zoomScale, persist: saveToDisk)
    }

    private func visibleCanvasCenter() -> CGPoint {
        CGPoint(
            x: canvasOrigin.x + (viewportSize.width / 2 - canvasOffset.width) / max(zoomScale, 0.01),
            y: canvasOrigin.y + (viewportSize.height / 2 - canvasOffset.height) / max(zoomScale, 0.01)
        )
    }

    private func contentBounds() -> CGRect? {
        var rect = CGRect.null
        for node in store.configuration.workflow.nodes {
            rect = rect.union(CGRect(x: node.position.x - 130, y: node.position.y - 75, width: 260, height: 150))
        }
        for element in store.configuration.workflow.canvasElements {
            rect = rect.union(CGRect(
                x: element.position.x - element.size.width / 2,
                y: element.position.y - element.size.height / 2,
                width: element.size.width,
                height: element.size.height
            ))
        }
        return rect.isNull ? nil : rect
    }

    private func handleConnectionPort(_ anchor: CanvasAnchorRef, mode: ConnectionMode) {
        if let pendingConnection {
            guard !isConsistencyNodeAnchor(pendingConnection) else {
                self.pendingConnection = nil
                return
            }
            switch pendingConnectionMode {
            case .logic:
                store.createLogicConnection(from: pendingConnection, to: anchor)
            case .regular:
                store.createAttachedArrowConnection(from: pendingConnection, to: anchor)
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            self.pendingConnection = nil
        } else {
            guard !isConsistencyNodeAnchor(anchor) else { return }
            pendingConnectionMode = mode
            pendingConnection = anchor
            hoverCanvasPoint = anchorPoint(for: anchor)
        }
    }

    private func isConsistencyNodeAnchor(_ anchor: CanvasAnchorRef) -> Bool {
        guard anchor.targetKind == .node,
              let node = store.configuration.workflow.nodes.first(where: { $0.id == anchor.targetId }) else {
            return false
        }
        return node.kind == .consistency
    }

    private func shouldShowPorts(for element: CanvasElement) -> Bool {
        guard ![CanvasElementKind.line, .arrow, .pen].contains(element.kind) else { return false }
        return store.configuration.workflow.selectedCanvasElementIds.contains(element.id) || hoveredElementId == element.id || pendingConnection != nil
    }

    private func anchorPoint(for ref: CanvasAnchorRef) -> CGPoint? {
        switch ref.targetKind {
        case .node:
            guard let node = store.configuration.workflow.nodes.first(where: { $0.id == ref.targetId }) else { return nil }
            return anchorPoint(center: node.position, size: CanvasSize(width: 260, height: 150), side: ref.side)
        case .element:
            guard let element = store.configuration.workflow.canvasElements.first(where: { $0.id == ref.targetId }) else { return nil }
            return anchorPoint(center: element.position, size: element.size, side: ref.side)
        }
    }

    private func anchorPoint(center: CanvasPoint, size: CanvasSize, side: CanvasAnchorSide) -> CGPoint {
        switch side {
        case .top:
            CGPoint(x: center.x, y: center.y - size.height / 2)
        case .right:
            CGPoint(x: center.x + size.width / 2, y: center.y)
        case .bottom:
            CGPoint(x: center.x, y: center.y + size.height / 2)
        case .left:
            CGPoint(x: center.x - size.width / 2, y: center.y)
        }
    }

    private func draftKind(for tool: CanvasTool) -> CanvasElementKind? {
        switch tool {
        case .grid: .artboard
        case .rectangle: .rectangle
        case .line: .line
        case .arrow: .arrow
        case .ellipse: .ellipse
        case .polygon: .polygon
        case .star: .star
        case .text: .text
        default: nil
        }
    }

    private func makePenDraft(points: [CGPoint]) -> CanvasElement {
        let rect = points.reduce(CGRect.null) { partial, point in
            partial.union(CGRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        let width = max(rect.width, 28)
        let height = max(rect.height, 28)
        let local = points.map { CanvasPoint(x: $0.x - rect.minX, y: $0.y - rect.minY) }
        return CanvasElement(kind: .pen, position: CanvasPoint(x: rect.midX, y: rect.midY), size: CanvasSize(width: width, height: height), pathPoints: local, strokeWidth: 3, colorHex: store.configuration.boardSettings.penColorHex)
    }

    private func appendPenPoint(_ point: CGPoint, start: CGPoint) {
        if penPoints.isEmpty {
            penPoints = [start]
        }
        guard let last = penPoints.last else {
            penPoints.append(point)
            return
        }
        let minimumDistance = max(0.8, store.configuration.boardSettings.penWidth * 0.35)
        guard hypot(point.x - last.x, point.y - last.y) >= minimumDistance else { return }
        penPoints.append(point)
    }

    private func withoutDragAnimation(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.animation = nil
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }

    private func makeDraftElement(kind: CanvasElementKind, from start: CGPoint, to end: CGPoint) -> CanvasElement {
        if kind == .line || kind == .arrow {
            return makeConnectorDraft(kind: kind, from: start, to: end)
        }
        var width = abs(end.x - start.x)
        var height = abs(end.y - start.y)
        let minWidth = kind == .text ? 160.0 : 28.0
        let minHeight = kind == .text ? 48.0 : 28.0
        width = max(width, minWidth)
        height = max(height, minHeight)
        let x = min(start.x, end.x) + width / 2
        let y = min(start.y, end.y) + height / 2
        return CanvasElement(
            kind: kind,
            position: CanvasPoint(x: x, y: y),
            size: CanvasSize(width: width, height: height),
            text: kind == .text ? "Text" : nil,
            assetPath: nil,
            colorHex: kind == .text ? store.configuration.boardSettings.textColorHex : "#111111"
        )
    }

    private func makeConnectorDraft(kind: CanvasElementKind, from start: CGPoint, to end: CGPoint) -> CanvasElement {
        let frame = connectorFrame(from: start, to: end)
        return CanvasElement(
            kind: kind,
            position: CanvasPoint(x: frame.midX, y: frame.midY),
            size: CanvasSize(width: frame.width, height: frame.height),
            pathPoints: localConnectorPoints(from: start, to: end, in: frame),
            strokeWidth: 2.4,
            colorHex: store.configuration.boardSettings.shapeColorHex
        )
    }

    private func connectorFrame(from start: CGPoint, to end: CGPoint) -> CGRect {
        let inset = 20.0
        let minX = min(start.x, end.x) - inset
        let minY = min(start.y, end.y) - inset
        let width = max(abs(end.x - start.x) + inset * 2, 44)
        let height = max(abs(end.y - start.y) + inset * 2, 44)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    private func localConnectorPoints(from start: CGPoint, to end: CGPoint, in frame: CGRect) -> [CanvasPoint] {
        [
            CanvasPoint(x: start.x - frame.minX, y: start.y - frame.minY),
            CanvasPoint(x: end.x - frame.minX, y: end.y - frame.minY)
        ]
    }
}

@MainActor
private struct LogicEdgeConfigurationCard: View {
    let element: CanvasElement
    let sourceTitle: String
    let targetTitle: String
    let onSave: (WorkflowLogicEdgeConfiguration) -> Void
    let onCancel: () -> Void
    @State private var draft: WorkflowLogicEdgeConfiguration

    init(
        element: CanvasElement,
        sourceTitle: String,
        targetTitle: String,
        onSave: @escaping (WorkflowLogicEdgeConfiguration) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.element = element
        self.sourceTitle = sourceTitle
        self.targetTitle = targetTitle
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: element.logicEdge ?? WorkflowLogicEdgeConfiguration(id: element.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("逻辑箭头")
                            .font(.headline)
                        HelpBadge(text: "逻辑箭头同时表达执行依赖和数据传递：父节点完成后，按这里的策略、条件和映射把文本、JSON、资产传给子节点。")
                    }
                    Text("\(sourceTitle) -> \(targetTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }

            Toggle("启用这条执行关系", isOn: $draft.enabled)
                .quickHelp("关闭后这条线仍可留在画布上，但不会参与 DAG Level 计算或运行输入拼装。")

            TextField("线上显示名称", text: $draft.displayName)
                .quickHelp("显示在箭头线上，适合写“参考图”“脚本草稿”“人工确认后继续”这类短名称。")
            TextField("说明", text: $draft.description, axis: .vertical)
                .lineLimit(2...4)
                .quickHelp("解释这条边为什么存在、传什么内容，方便调试和交接。")

            HStack {
                Picker("运行策略", selection: $draft.runPolicy) {
                    ForEach(WorkflowEdgeRunPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                Picker("依赖策略", selection: $draft.dependencyPolicy) {
                    ForEach(WorkflowDependencyPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
            }
            .quickHelp("运行策略控制这条边是否总是流动、按条件流动或等待人工确认；依赖策略控制多父节点时子节点何时可以运行。")

            TextField("条件 condition", text: $draft.condition)
                .quickHelp("当运行策略为 Condition 时，会在父节点输出文本、JSON 和日志里查找这段条件文本。")

            HStack {
                TextField("sourcePort", text: $draft.sourcePort)
                TextField("targetPort", text: $draft.targetPort)
            }
            HStack {
                TextField("sourceHandle", text: $draft.sourceHandle)
                TextField("targetHandle", text: $draft.targetHandle)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("传递内容")
                        .font(.caption.weight(.semibold))
                    HelpBadge(text: payloadMappingHelp)
                    Button("填入示例") {
                        draft.payloadMapping = Self.payloadMappingTemplate
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                TextEditor(text: $draft.payloadMapping)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 70)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("传递资产")
                        .font(.caption.weight(.semibold))
                    HelpBadge(text: artifactMappingHelp)
                    Button("填入示例") {
                        draft.artifactMapping = Self.artifactMappingTemplate
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                TextEditor(text: $draft.artifactMapping)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 70)
            }

            HStack {
                Button("取消", action: onCancel)
                Spacer()
                Button {
                    onSave(draft)
                } label: {
                    Label("保存", systemImage: "checkmark")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(16)
        .frame(width: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.16))
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
        .onChange(of: element.id) { _, _ in
            draft = element.logicEdge ?? WorkflowLogicEdgeConfiguration(id: element.id)
        }
    }

    private var payloadMappingHelp: String {
        """
        写清楚这条箭头要把父节点输出里的哪部分交给子节点。留空或 {} 表示传完整文本。
        推荐格式：
        {
          "text": "summary",
          "json": {
            "title": "$.title",
            "scene": "$.scene"
          }
        }
        """
    }

    private var artifactMappingHelp: String {
        """
        写清楚要传哪些资产类型。留空或 {} 表示传全部资产。
        推荐格式：
        {
          "include": ["image", "video"],
          "extensions": ["png", "mp4"],
          "role": "reference"
        }
        """
    }

    private static let payloadMappingTemplate = """
    {
      "text": "summary",
      "json": {
        "title": "$.title",
        "scene": "$.scene"
      }
    }
    """

    private static let artifactMappingTemplate = """
    {
      "include": ["image", "video"],
      "extensions": ["png", "mp4"],
      "role": "reference"
    }
    """
}

@MainActor
private struct BlackHoleZoneView: View {
    let radius: Double
    let isActive: Bool
    let isEnabled: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.accentColor.opacity(isActive ? 0.22 : 0.08),
                            Color.black.opacity(isActive ? 0.10 : 0.04),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: radius
                    )
                )
            Circle()
                .stroke(
                    Color.accentColor.opacity(isActive ? 0.75 : 0.26),
                    style: StrokeStyle(lineWidth: isActive ? 2.2 : 1.1, dash: isActive ? [] : [6, 7])
                )
                .scaleEffect(pulse && isActive ? 1.035 : 1)
        }
        .frame(width: radius * 2, height: radius * 2)
        .opacity(isEnabled ? 1 : 0)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

@MainActor
private struct EjectionFanPreview: View {
    let angleDegrees: Double
    let spreadDegrees: Double
    let force: Double
    let color: Color

    private var radius: Double {
        max(92, min(force, 720)) * 0.46
    }

    var body: some View {
        ZStack {
            EjectionFanShape(angleDegrees: angleDegrees, spreadDegrees: spreadDegrees, radius: radius)
                .fill(
                    AngularGradient(
                        colors: [color.opacity(0.02), color.opacity(0.22), color.opacity(0.04)],
                        center: .center
                    )
                )
                .overlay {
                    EjectionFanShape(angleDegrees: angleDegrees, spreadDegrees: spreadDegrees, radius: radius)
                        .stroke(color.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [7, 7]))
                }

            EjectionRayShape(angleDegrees: angleDegrees, radius: radius)
                .stroke(color.opacity(0.82), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .offset(x: cos(angleDegrees * .pi / 180) * radius, y: sin(angleDegrees * .pi / 180) * radius)
                .shadow(color: color.opacity(0.7), radius: 10)
        }
        .compositingGroup()
        .shadow(color: color.opacity(0.25), radius: 18)
        .animation(.snappy(duration: 0.14), value: angleDegrees)
        .animation(.snappy(duration: 0.14), value: spreadDegrees)
        .animation(.snappy(duration: 0.14), value: force)
    }
}

private struct EjectionFanShape: Shape {
    let angleDegrees: Double
    let spreadDegrees: Double
    let radius: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(angleDegrees - spreadDegrees / 2),
            endAngle: .degrees(angleDegrees + spreadDegrees / 2),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct EjectionRayShape: Shape {
    let angleDegrees: Double
    let radius: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radians = angleDegrees * .pi / 180
        let end = CGPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)
        var path = Path()
        path.move(to: center)
        path.addLine(to: end)
        return path
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
