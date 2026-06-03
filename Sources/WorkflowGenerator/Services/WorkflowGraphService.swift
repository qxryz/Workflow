import Foundation

struct WorkflowGraphEdge: Identifiable, Hashable {
    var id: UUID
    var elementId: UUID
    var sourceNodeId: UUID
    var targetNodeId: UUID
    var sourceAnchor: CanvasAnchorRef
    var targetAnchor: CanvasAnchorRef
    var configuration: WorkflowLogicEdgeConfiguration
}

struct WorkflowGraph {
    var nodeIds: Set<UUID>
    var edges: [WorkflowGraphEdge]
    var spatialRoutes: [SpatialArtifactRoute]
    var startNodeIds: [UUID]
    var nodeLevels: [UUID: Int]
    var levels: [Int: [UUID]]

    var orderedLevels: [Int] {
        levels.keys.sorted()
    }

    var incoming: [UUID: Set<UUID>] {
        var map = Dictionary(uniqueKeysWithValues: nodeIds.map { ($0, Set<UUID>()) })
        for edge in edges {
            map[edge.targetNodeId, default: []].insert(edge.sourceNodeId)
        }
        return map
    }

    var outgoing: [UUID: [UUID]] {
        var map: [UUID: [UUID]] = [:]
        for edge in edges {
            map[edge.sourceNodeId, default: []].append(edge.targetNodeId)
        }
        return map
    }

    var incomingEdges: [UUID: [WorkflowGraphEdge]] {
        var map: [UUID: [WorkflowGraphEdge]] = [:]
        for edge in edges {
            map[edge.targetNodeId, default: []].append(edge)
        }
        return map
    }

    var outgoingEdges: [UUID: [WorkflowGraphEdge]] {
        var map: [UUID: [WorkflowGraphEdge]] = [:]
        for edge in edges {
            map[edge.sourceNodeId, default: []].append(edge)
        }
        return map
    }

    var incomingSpatialRoutes: [UUID: [SpatialArtifactRoute]] {
        var map: [UUID: [SpatialArtifactRoute]] = [:]
        for route in spatialRoutes where route.enabled {
            map[route.targetNodeId, default: []].append(route)
        }
        return map
    }

    var outgoingSpatialRoutes: [UUID: [SpatialArtifactRoute]] {
        var map: [UUID: [SpatialArtifactRoute]] = [:]
        for route in spatialRoutes where route.enabled {
            map[route.sourceNodeId, default: []].append(route)
        }
        return map
    }
}

enum WorkflowGraphError: LocalizedError {
    case emptyWorkflow
    case cycleDetected

    var errorDescription: String? {
        switch self {
        case .emptyWorkflow:
            "Workflow has no nodes."
        case .cycleDetected:
            "Workflow execution requires a DAG. Break the loop before running; start and end nodes are inferred from dependencies."
        }
    }
}

struct WorkflowGraphService {
    func build(from workflow: WorkflowDocument, spatialRoutes: [SpatialArtifactRoute] = []) throws -> WorkflowGraph {
        let nodeIds = Set(workflow.nodes.map(\.id))
        let nodesById = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        guard !nodeIds.isEmpty else { throw WorkflowGraphError.emptyWorkflow }

        let edges = workflow.canvasElements.compactMap { element -> WorkflowGraphEdge? in
            guard element.isLogicConnection,
                  let startAnchor = element.startAnchor,
                  let endAnchor = element.endAnchor,
                  startAnchor.targetKind == .node,
                  endAnchor.targetKind == .node,
                  startAnchor.targetId != endAnchor.targetId,
                  nodeIds.contains(startAnchor.targetId),
                  nodeIds.contains(endAnchor.targetId),
                  nodesById[startAnchor.targetId]?.kind != .consistency else {
                return nil
            }
            var configuration = element.logicEdge ?? WorkflowLogicEdgeConfiguration(id: element.id)
            configuration.id = element.id
            configuration.sourceNodeId = startAnchor.targetId
            configuration.targetNodeId = endAnchor.targetId
            guard configuration.enabled else { return nil }
            return WorkflowGraphEdge(
                id: element.id,
                elementId: element.id,
                sourceNodeId: startAnchor.targetId,
                targetNodeId: endAnchor.targetId,
                sourceAnchor: startAnchor,
                targetAnchor: endAnchor,
                configuration: configuration
            )
        }

        let dependencySpatialRoutes = spatialRoutes.filter {
            $0.enabled && $0.createsDependency && nodeIds.contains($0.sourceNodeId) && nodeIds.contains($0.targetNodeId)
        }

        var indegree = Dictionary(uniqueKeysWithValues: nodeIds.map { ($0, 0) })
        var children: [UUID: [UUID]] = [:]
        for edge in edges {
            indegree[edge.targetNodeId, default: 0] += 1
            children[edge.sourceNodeId, default: []].append(edge.targetNodeId)
        }
        for route in dependencySpatialRoutes {
            indegree[route.targetNodeId, default: 0] += 1
            children[route.sourceNodeId, default: []].append(route.targetNodeId)
        }

        var queue = workflow.nodes.map(\.id).filter { indegree[$0, default: 0] == 0 }
        guard !queue.isEmpty else { throw WorkflowGraphError.cycleDetected }

        var processed: [UUID] = []
        var nodeLevels = Dictionary(uniqueKeysWithValues: nodeIds.map { ($0, 0) })
        while !queue.isEmpty {
            let nodeId = queue.removeFirst()
            processed.append(nodeId)
            for child in children[nodeId, default: []] {
                nodeLevels[child] = max(nodeLevels[child, default: 0], nodeLevels[nodeId, default: 0] + 1)
                indegree[child, default: 0] -= 1
                if indegree[child, default: 0] == 0 {
                    queue.append(child)
                }
            }
        }

        guard processed.count == nodeIds.count else { throw WorkflowGraphError.cycleDetected }

        let levels = Dictionary(grouping: workflow.nodes.map(\.id), by: { nodeLevels[$0, default: 0] })
        let targets = Set(edges.map(\.targetNodeId) + dependencySpatialRoutes.map(\.targetNodeId))
        let startNodeIds = workflow.nodes.map(\.id).filter { !targets.contains($0) }

        return WorkflowGraph(
            nodeIds: nodeIds,
            edges: edges,
            spatialRoutes: spatialRoutes.filter { nodeIds.contains($0.sourceNodeId) && nodeIds.contains($0.targetNodeId) },
            startNodeIds: startNodeIds,
            nodeLevels: nodeLevels,
            levels: levels
        )
    }
}
