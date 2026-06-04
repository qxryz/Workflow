import Foundation

struct SpatialArtifactRouteResolver {
    func resolve(nodes: [WorkflowNode], mode: WorkflowAssetPropagationMode) -> [SpatialArtifactRoute] {
        guard mode == .bigMouth else { return [] }
        let sources = nodes.filter { $0.kind != .consistency }
        let targets = nodes.filter(\.blackHoleEnabled)
        var routes: [SpatialArtifactRoute] = []
        for source in sources {
            for target in targets where target.id != source.id {
                guard fanHitsBlackhole(source: source, target: target) else { continue }
                let acceptedTypes = target.kind == .consistency ? target.consistencyConfig.acceptedArtifactTypes : Set(Modality.allCases)
                routes.append(SpatialArtifactRoute(
                    sourceNodeId: source.id,
                    targetNodeId: target.id,
                    sourceFan: SpatialFanSnapshot(
                        angle: source.ejectionAngleDegrees,
                        radius: clampedFanRadius(source.ejectionForce),
                        spreadDegrees: clampedSpread(source.ejectionSpreadDegrees)
                    ),
                    targetBlackhole: SpatialBlackholeSnapshot(
                        receiverId: target.id,
                        radius: clampedBlackholeRadius(target.blackHoleRadius)
                    ),
                    acceptedTypes: acceptedTypes
                ))
            }
        }
        return routes
    }

    func fanHitsBlackhole(source: WorkflowNode, target: WorkflowNode) -> Bool {
        let dx = target.position.x - source.position.x
        let dy = target.position.y - source.position.y
        let distance = hypot(dx, dy)
        guard distance <= clampedFanRadius(source.ejectionForce) + clampedBlackholeRadius(target.blackHoleRadius) else {
            return false
        }
        let targetAngle = atan2(dy, dx) * 180 / .pi
        let delta = normalizedAngleDelta(targetAngle - source.ejectionAngleDegrees)
        let halfSpread = max(6, clampedSpread(source.ejectionSpreadDegrees) / 2)
        return abs(delta) <= halfSpread
    }

    private func clampedFanRadius(_ radius: Double) -> Double {
        max(80, min(radius, 720))
    }

    private func clampedBlackholeRadius(_ radius: Double) -> Double {
        max(80, radius)
    }

    private func clampedSpread(_ degrees: Double) -> Double {
        max(0, min(degrees, 140))
    }

    private func normalizedAngleDelta(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }
}
