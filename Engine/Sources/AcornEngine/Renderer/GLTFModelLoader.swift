import Foundation
import AcornMath
internal import AcornGLTF

/// Represents a skeleton skin binding in a glTF model.
public struct GLTFSkin: Sendable, Equatable {
    /// The name of the skin.
    public let name: String

    /// Indices of nodes that act as skeleton joints.
    public let jointNodeIndices: [Int]

    /// Column-major inverse bind matrices, one per joint.
    public let inverseBindMatrices: [Matrix4x4]

    /// Initializes a new GLTFSkin representation.
    public init(name: String = "", jointNodeIndices: [Int] = [], inverseBindMatrices: [Matrix4x4] = []) {
        self.name = name
        self.jointNodeIndices = jointNodeIndices
        self.inverseBindMatrices = inverseBindMatrices
    }
}

/// Represents a node within a loaded glTF scene.
public struct GLTFNode: Sendable {
    /// The name of the node.
    public let name: String

    /// The index of the mesh this node contains, if any.
    public let meshIndex: Int?

    /// The index of the parent node in the returned nodes array, if any.
    public let parentIndex: Int?

    /// The index of the skin associated with this node, if any.
    public let skinIndex: Int?

    /// The local translation of the node.
    public let translation: SIMD3<Float>

    /// The local rotation quaternion (x, y, z, w).
    public let rotation: SIMD4<Float>

    /// The local scale of the node.
    public let scale: SIMD3<Float>

    /// Initializes a new glTF node descriptor.
    public init(
        name: String,
        meshIndex: Int? = nil,
        parentIndex: Int? = nil,
        skinIndex: Int? = nil,
        translation: SIMD3<Float> = .zero,
        rotation: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1),
        scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    ) {
        self.name = name
        self.meshIndex = meshIndex
        self.parentIndex = parentIndex
        self.skinIndex = skinIndex
        self.translation = translation
        self.rotation = rotation
        self.scale = scale
    }
}

/// Represents a loaded glTF model including meshes, node hierarchy, texture data, and animations.
public struct GLTFModel: Sendable {
    /// The GPU meshes contained in the glTF asset.
    public let meshes: [any Mesh]

    /// The scene node hierarchy.
    public let nodes: [GLTFNode]

    /// Embedded texture data, if present.
    public let textureData: Data?

    /// The animation clips loaded from the model.
    public let animations: [ModelAnimationClip]

    /// The skins loaded from the model.
    public let skins: [GLTFSkin]

    /// Initializes a new glTF model representation.
    public init(
        meshes: [any Mesh],
        nodes: [GLTFNode],
        textureData: Data? = nil,
        animations: [ModelAnimationClip] = [],
        skins: [GLTFSkin] = []
    ) {
        self.meshes = meshes
        self.nodes = nodes
        self.textureData = textureData
        self.animations = animations
        self.skins = skins
    }

    /// Instantiates the model in an ECS World, creating entities for each node and setting up
    /// transform hierarchies, mesh components, and a `ModelAnimationComponent` if animations are present.
    /// - Parameters:
    ///   - world: The ECS world.
    ///   - color: Base color tint applied to mesh components. Defaults to opaque white.
    ///   - texture: Optional texture to apply to mesh components.
    /// - Returns: The root entity of the instantiated model.
    @MainActor
    public func instantiate(
        in world: World,
        color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        texture: (any Texture)? = nil
    ) -> Entity {
        let rootEntity = world.createEntity()
        world.addComponent(TransformComponent(), to: rootEntity)

        var nodeEntities: [Entity] = []
        nodeEntities.reserveCapacity(nodes.count)
        var restTransforms: [NodeRestTransform] = []
        restTransforms.reserveCapacity(nodes.count)

        var skinnedMeshEntities: [Entity] = []
        for node in nodes {
            let entity = world.createEntity()
            #if DEBUG
            world.setName(node.name, for: entity)
            #endif

            let localTransform = TransformComponent(
                position: node.translation,
                rotation: quaternionToEuler(node.rotation),
                scale: node.scale,
                orientation: node.rotation
            )
            world.addComponent(localTransform, to: entity)

            restTransforms.append(NodeRestTransform(
                translation: node.translation,
                rotation: node.rotation,
                scale: node.scale
            ))

            if let meshIdx = node.meshIndex, meshIdx < meshes.count {
                let mesh = meshes[meshIdx]
                if let skinIdx = node.skinIndex, skinIdx >= 0 && skinIdx < skins.count {
                    let skin = skins[skinIdx]
                    let initialMatrices = [Matrix4x4](repeating: .identity, count: skin.jointNodeIndices.count)
                    let skinnedComp = SkinnedMeshComponent(
                        mesh: mesh,
                        color: color,
                        texture: texture,
                        skinIndex: skinIdx,
                        jointMatrices: initialMatrices
                    )
                    world.addComponent(skinnedComp, to: entity)
                    skinnedMeshEntities.append(entity)
                } else {
                    let meshComp = MeshComponent(mesh: mesh, color: color, texture: texture)
                    world.addComponent(meshComp, to: entity)
                }
            }
            nodeEntities.append(entity)
        }

        for (i, node) in nodes.enumerated() {
            let childEntity = nodeEntities[i]
            if let parentIdx = node.parentIndex, parentIdx < nodeEntities.count {
                let parentEntity = nodeEntities[parentIdx]
                world.addComponent(ParentComponent(parent: parentEntity), to: childEntity)
            } else {
                world.addComponent(ParentComponent(parent: rootEntity), to: childEntity)
            }
        }

        if !animations.isEmpty {
            var animDict: [String: ModelAnimationClip] = [:]
            for clip in animations {
                animDict[clip.name] = clip
            }
            let animComp = ModelAnimationComponent(
                clips: animDict,
                initialClip: animations.first?.name,
                speed: 1.0,
                isPlaying: true,
                nodeEntities: nodeEntities,
                nodeRestTransforms: restTransforms,
                skins: skins,
                skinnedMeshEntities: skinnedMeshEntities
            )
            world.addComponent(animComp, to: rootEntity)
        }

        return rootEntity
    }
}

/// Loads glTF 2.0 (`.gltf` / `.glb`) assets via `AcornGLTF` and uploads GPU geometry through a `Renderer`.
public final class GLTFModelLoader: Sendable {
    /// The renderer used to upload loaded GPU meshes.
    public let renderer: (any Renderer)?

    /// Initializes a new GLTFModelLoader backed by a `Renderer`.
    /// - Parameter renderer: The renderer backend used to allocate GPU meshes.
    public init(renderer: any Renderer) {
        self.renderer = renderer
    }

    /// Loads a glTF model from a local file URL producing backend-agnostic `Mesh` instances.
    /// - Parameter url: The file URL of the model (`.glb` or `.gltf`).
    /// - Returns: A tuple containing loaded meshes, scene nodes, optional embedded texture bytes, animations, and skins.
    /// - Throws: An error if the file cannot be parsed or GPU mesh creation fails.
    public func load(from url: URL) throws -> (
        meshes: [any Mesh],
        nodes: [GLTFNode],
        textureData: Data?,
        animations: [ModelAnimationClip],
        skins: [GLTFSkin]
    ) {
        guard url.isFileURL else {
            throw NSError(
                domain: "GLTFModelLoaderErrorDomain",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Only file URLs are supported."]
            )
        }
        guard let renderer = self.renderer else {
            throw NSError(
                domain: "GLTFModelLoaderErrorDomain",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Renderer required for loading glTF meshes."]
            )
        }

        var result = AcornGLTFModelResult()
        defer {
            acorn_gltf_free_result(&result)
        }

        let path = url.path
        guard acorn_gltf_load_file(path, &result), result.meshCount > 0 else {
            throw NSError(
                domain: "GLTFModelLoaderErrorDomain",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to load glTF meshes or file not found: \(path)"]
            )
        }

        var meshes: [any Mesh] = []
        meshes.reserveCapacity(Int(result.meshCount))
        if let meshesPtr = result.meshes {
            for i in 0..<Int(result.meshCount) {
                let meshData = meshesPtr[i]
                guard let gpuMesh = Self.uploadMesh(meshData, renderer: renderer) else {
                    throw NSError(
                        domain: "GLTFModelLoaderErrorDomain",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Renderer failed to allocate GPU mesh for glTF primitive \(i)."]
                    )
                }
                meshes.append(gpuMesh)
            }
        }

        var nodes: [GLTFNode] = []
        nodes.reserveCapacity(Int(result.nodeCount))
        if let nodesPtr = result.nodes {
            for i in 0..<Int(result.nodeCount) {
                let data = nodesPtr[i]
                let nodeName = Self.decodeFixedCString(data.name)
                nodes.append(GLTFNode(
                    name: nodeName,
                    meshIndex: data.meshIndex >= 0 ? Int(data.meshIndex) : nil,
                    parentIndex: data.parentIndex >= 0 ? Int(data.parentIndex) : nil,
                    skinIndex: data.skinIndex >= 0 ? Int(data.skinIndex) : nil,
                    translation: SIMD3<Float>(data.translation.0, data.translation.1, data.translation.2),
                    rotation: SIMD4<Float>(data.rotation.0, data.rotation.1, data.rotation.2, data.rotation.3),
                    scale: SIMD3<Float>(data.scale.0, data.scale.1, data.scale.2)
                ))
            }
        }

        var textureData: Data? = nil
        if let texPtr = result.textureData, result.textureSize > 0 {
            textureData = Data(bytes: texPtr, count: Int(result.textureSize))
        }

        var animations: [ModelAnimationClip] = []
        if result.animationCount > 0, let animsPtr = result.animations {
            animations.reserveCapacity(Int(result.animationCount))
            for a in 0..<Int(result.animationCount) {
                let animData = animsPtr[a]
                var animName = Self.decodeFixedCString(animData.name)
                if animName.isEmpty {
                    animName = "animation_\(a)"
                }

                var channels: [ModelAnimationChannel] = []
                if animData.channelCount > 0, let channelsPtr = animData.channels {
                    channels.reserveCapacity(Int(animData.channelCount))
                    for c in 0..<Int(animData.channelCount) {
                        let chData = channelsPtr[c]
                        let nodeIdx = Int(chData.nodeIndex)
                        let keyframeCount = Int(chData.keyframeCount)
                        let valuesPerKeyframe = Int(chData.valuesPerKeyframe)

                        guard let path = ModelAnimationPath(rawValue: chData.path),
                              let interpolation = ModelAnimationInterpolation(rawValue: chData.interpolation),
                              let tsPtr = chData.timestamps,
                              let valPtr = chData.values,
                              keyframeCount > 0 else {
                            continue
                        }

                        let timestamps = Array(UnsafeBufferPointer(start: tsPtr, count: keyframeCount))
                        let values = Array(UnsafeBufferPointer(start: valPtr, count: keyframeCount * valuesPerKeyframe))
                        let targetNodeName = (nodeIdx >= 0 && nodeIdx < nodes.count) ? nodes[nodeIdx].name : nil

                        channels.append(ModelAnimationChannel(
                            targetNodeIndex: nodeIdx,
                            targetNodeName: targetNodeName,
                            path: path,
                            interpolation: interpolation,
                            keyframeTimes: timestamps,
                            keyframeValues: values,
                            valuesPerKeyframe: valuesPerKeyframe
                        ))
                    }
                }

                animations.append(ModelAnimationClip(
                    name: animName,
                    duration: Double(animData.duration),
                    channels: channels,
                    playbackMode: .loop
                ))
            }
        }

        var skins: [GLTFSkin] = []
        if result.skinCount > 0, let skinsPtr = result.skins {
            skins.reserveCapacity(Int(result.skinCount))
            for s in 0..<Int(result.skinCount) {
                let skinData = skinsPtr[s]
                var skinName = Self.decodeFixedCString(skinData.name)
                if skinName.isEmpty {
                    skinName = "skin_\(s)"
                }

                var jointIndices: [Int] = []
                if skinData.jointCount > 0, let jointsPtr = skinData.jointNodeIndices {
                    jointIndices.reserveCapacity(Int(skinData.jointCount))
                    for j in 0..<Int(skinData.jointCount) {
                        jointIndices.append(Int(jointsPtr[j]))
                    }
                }

                var inverseBindMatrices: [Matrix4x4] = []
                if skinData.jointCount > 0, let ibmPtr = skinData.inverseBindMatrices {
                    inverseBindMatrices.reserveCapacity(Int(skinData.jointCount))
                    for j in 0..<Int(skinData.jointCount) {
                        let offset = j * 16
                        let col0 = SIMD4<Float>(ibmPtr[offset + 0], ibmPtr[offset + 1], ibmPtr[offset + 2], ibmPtr[offset + 3])
                        let col1 = SIMD4<Float>(ibmPtr[offset + 4], ibmPtr[offset + 5], ibmPtr[offset + 6], ibmPtr[offset + 7])
                        let col2 = SIMD4<Float>(ibmPtr[offset + 8], ibmPtr[offset + 9], ibmPtr[offset + 10], ibmPtr[offset + 11])
                        let col3 = SIMD4<Float>(ibmPtr[offset + 12], ibmPtr[offset + 13], ibmPtr[offset + 14], ibmPtr[offset + 15])
                        inverseBindMatrices.append(Matrix4x4(col0, col1, col2, col3))
                    }
                }

                skins.append(GLTFSkin(name: skinName, jointNodeIndices: jointIndices, inverseBindMatrices: inverseBindMatrices))
            }
        }

        return (meshes: meshes, nodes: nodes, textureData: textureData, animations: animations, skins: skins)
    }

    /// Loads a glTF model returning a structured `GLTFModel` instance.
    /// - Parameter url: The file URL of the model (`.glb` or `.gltf`).
    /// - Returns: The loaded `GLTFModel`.
    /// - Throws: An error if loading fails.
    public func loadModel(from url: URL) throws -> GLTFModel {
        let result = try load(from: url)
        return GLTFModel(
            meshes: result.meshes,
            nodes: result.nodes,
            textureData: result.textureData,
            animations: result.animations,
            skins: result.skins
        )
    }

    /// Loads a glTF model returning platform-agnostic `Mesh` resources.
    /// - Parameter url: The file URL of the model (`.glb` or `.gltf`).
    /// - Returns: A tuple containing the loaded meshes, nodes, raw texture data, animation clips, and skins.
    /// - Throws: An error if loading fails.
    public func loadMeshes(from url: URL) throws -> (
        meshes: [any Mesh],
        nodes: [GLTFNode],
        textureData: Data?,
        animations: [ModelAnimationClip],
        skins: [GLTFSkin]
    ) {
        return try load(from: url)
    }

    // MARK: - Helpers

    private static func uploadMesh(_ meshData: AcornGLTFMeshData, renderer: any Renderer) -> (any Mesh)? {
        let vertexCount = Int(meshData.vertexCount)
        let indexCount = Int(meshData.indexCount)
        guard vertexCount > 0 else { return nil }

        let indices: [UInt32]
        if indexCount > 0, let indexPtr = meshData.indices {
            indices = Array(UnsafeBufferPointer(start: indexPtr, count: indexCount))
        } else {
            indices = []
        }

        if meshData.isSkinned {
            guard let skinnedPtr = meshData.skinnedVertices else { return nil }
            let byteCount = vertexCount * MemoryLayout<AcornGLTFSkinnedVertex>.stride
            let skinnedData = Data(bytes: skinnedPtr, count: byteCount)
            return renderer.createSkinnedMesh(
                skinnedVertexData: skinnedData,
                vertexCount: vertexCount,
                indices: indices
            )
        }

        guard let vertPtr = meshData.vertices else { return nil }
        let vertices = UnsafeBufferPointer(start: vertPtr, count: vertexCount).map { v in
            Vertex(
                position: SIMD3<Float>(v.position.0, v.position.1, v.position.2),
                color: SIMD4<Float>(v.color.0, v.color.1, v.color.2, v.color.3),
                texCoord: SIMD2<Float>(v.texCoord.0, v.texCoord.1),
                normal: SIMD3<Float>(v.normal.0, v.normal.1, v.normal.2)
            )
        }
        return renderer.createMesh(meshData: CPUMeshData(vertices: vertices, indices: indices))
    }

    private static func decodeFixedCString<T>(_ fixedTuple: T) -> String {
        return withUnsafePointer(to: fixedTuple) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 64) { cStr in
                let raw = Array(UnsafeBufferPointer(start: cStr, count: 64))
                let length = raw.firstIndex(of: 0) ?? 64
                return String(decoding: raw[..<length].map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
    }
}
