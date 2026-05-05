import SwiftUI
import RealityKit
import ARKit
import Combine

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var arManager: ARManager
    @ObservedObject var estimator: AnchorEstimator
    @ObservedObject var radar: RadarManager

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView.session = arManager.session

        // AnchorEntity is pinned at world origin by ARKit and cannot be moved dynamically.
        // All content that needs to track the DWM position lives inside `trackingParent`,
        // a plain Entity whose position we update freely every frame via setPosition(relativeTo:nil).
        let sceneAnchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(sceneAnchor)

        let trackingParent = Entity()
        sceneAnchor.addChild(trackingParent)

        // Green sphere marks the UWB (DWM) anchor position
        let mesh = MeshResource.generateSphere(radius: 0.05)
        var material = UnlitMaterial()
        material.color = .init(tint: .green)
        let anchorVisualEntity = ModelEntity(mesh: mesh, materials: [material])
        anchorVisualEntity.isEnabled = false   // hidden until the DWM position is known
        trackingParent.addChild(anchorVisualEntity)

        let coordinator = context.coordinator
        coordinator.anchorVisualEntity = anchorVisualEntity
        coordinator.trackingParent = trackingParent

        // SceneEvents.Update fires every rendered frame on the render thread.
        coordinator.updateSub = arView.scene.subscribe(to: SceneEvents.Update.self) {
            [weak estimator, weak radar, weak coordinator, weak anchorVisualEntity, weak arView] _ in
            guard let estimator, let radar, let coordinator,
                  let anchorVisualEntity, let trackingParent = coordinator.trackingParent else { return }

            let alpha: Float = 0.12

            if let target = estimator.anchorPosition {
                // EMA-smooth toward the latest DWM estimate every frame to hide solver step-changes.
                if let current = coordinator.smoothedPosition {
                    coordinator.smoothedPosition = current + alpha * (target - current)
                } else {
                    coordinator.smoothedPosition = target
                }
                // Move the plain Entity (not the AnchorEntity) — this is what actually works.
                trackingParent.setPosition(coordinator.smoothedPosition!, relativeTo: nil)
                anchorVisualEntity.isEnabled = true
            } else {
                // No DWM estimate yet — hide everything and clear the smoothed position so
                // the first real estimate snaps in without an EMA lag from a stale position.
                coordinator.smoothedPosition = nil
                anchorVisualEntity.isEnabled = false
            }

            // Blobs are children of trackingParent so their positions are automatically
            // relative to the DWM anchor. Only show them when the anchor position is known.
            let blobsToShow = estimator.anchorPosition != nil ? radar.blobs : []
            coordinator.syncBlobs(blobs: blobsToShow, parent: trackingParent)

            // Off-screen directional indicator
            guard let arView else { return }
            guard let position = coordinator.smoothedPosition else {
                if coordinator.lastAngle != nil {
                    DispatchQueue.main.async { estimator.offScreenAngle = nil }
                    coordinator.lastAngle = nil
                }
                return
            }

            let isOffScreen: Bool
            if let proj = arView.project(position) {
                isOffScreen = !arView.bounds.contains(proj)
            } else {
                isOffScreen = true
            }

            if isOffScreen {
                guard let camera = arView.session.currentFrame?.camera else { return }
                let cameraTransform = camera.transform
                let localPos4 = simd_mul(simd_inverse(cameraTransform),
                                        simd_float4(position.x, position.y, position.z, 1.0))
                // Camera sensor is landscape-right; in portrait: sensor +X = UI up, sensor +Y = UI right.
                let angle = Double(atan2(localPos4.x, localPos4.y))
                if coordinator.lastAngle == nil || abs(coordinator.lastAngle! - angle) > 0.05 {
                    coordinator.lastAngle = angle
                    DispatchQueue.main.async { estimator.offScreenAngle = angle }
                }
            } else {
                if coordinator.lastAngle != nil {
                    DispatchQueue.main.async { estimator.offScreenAngle = nil }
                    coordinator.lastAngle = nil
                }
            }
        }

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var anchorVisualEntity: ModelEntity?
        var trackingParent: Entity?
        var updateSub: (any Cancellable)?
        var smoothedPosition: simd_float3? = nil
        var lastAngle: Double?

        var blobEntities: [Entity] = []

        func syncBlobs(blobs: [RadarBlob], parent: Entity) {
            for (index, blob) in blobs.enumerated() {
                let entity: Entity
                if index < blobEntities.count {
                    entity = blobEntities[index]
                    entity.isEnabled = true
                } else {
                    let mesh = MeshResource.generateSphere(radius: 0.1)
                    let material = UnlitMaterial()
                    let model = ModelEntity(mesh: mesh, materials: [material])

                    let text = MeshResource.generateText(
                        "", extrusionDepth: 0.01,
                        font: .systemFont(ofSize: 0.1),
                        containerFrame: .zero,
                        alignment: .center,
                        lineBreakMode: .byWordWrapping)
                    let textModel = ModelEntity(mesh: text, materials: [UnlitMaterial(color: .white)])
                    textModel.position = [0, 0.15, 0]
                    textModel.name = "textNode"

                    let parentNode = Entity()
                    parent.addChild(parentNode)
                    parentNode.addChild(model)
                    parentNode.addChild(textModel)

                    blobEntities.append(parentNode)
                    entity = parentNode
                }

                entity.position = blob.position

                if let model = entity.children.first as? ModelEntity,
                   let textNode = entity.findEntity(named: "textNode") as? ModelEntity {
                    var mat = UnlitMaterial()
                    if blob.classId == 1 {
                        mat.color = .init(tint: .green)
                    } else if blob.classId == 2 {
                        mat.color = .init(tint: .red)
                    } else {
                        mat.color = .init(tint: .gray)
                    }
                    model.model?.materials = [mat]

                    let label: String
                    if blob.classId == 1 { label = "ACTIVE" }
                    else if blob.classId == 2 { label = "UNCONSCIOUS" }
                    else { label = "NOISE" }

                    textNode.model?.mesh = MeshResource.generateText(
                        label, extrusionDepth: 0.01,
                        font: .systemFont(ofSize: 0.1),
                        containerFrame: .zero,
                        alignment: .center,
                        lineBreakMode: .byWordWrapping)

                    textNode.components.set(BillboardComponent())
                }
            }

            for index in blobs.count..<blobEntities.count {
                blobEntities[index].isEnabled = false
            }
        }
    }
}
