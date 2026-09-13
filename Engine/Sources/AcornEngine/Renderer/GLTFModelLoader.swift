import Foundation
import AcornMath

#if canImport(Metal)
import Metal
internal import AcornMetal
#endif

/// Represents a node within a loaded glTF scene.
public struct GLTFNode: Sendable {
    /// The name of the node.
    public let name: String
    /// The index of the mesh this node contains, if any.
    public let meshIndex: Int?
    /// The index of the parent node in the returned nodes array, if any.
    public let parentIndex: Int?
    /// The local translation of the node.
    public let translation: SIMD3<Float>
    /// The local rotation quaternion (x, y, z, w).
    public let rotation: SIMD4<Float>
    /// The local scale of the node.
    public let scale: SIMD3<Float>
}

/// Represents a loaded glTF model including meshes, node hierarchy, texture data, and animations.
public struct GLTFModel: Sendable {
    #if canImport(Metal)
    /// The meshes contained in the glTF asset.
    public let meshes: [MetalMesh]
    #else
    /// The meshes contained in the glTF asset.
    public let meshes: [any Mesh]
    #endif
    
    /// The scene node hierarchy.
    public let nodes: [GLTFNode]
    
    /// Embedded texture data, if present.
    public let textureData: Data?
    
    /// The animation clips loaded from the model.
    public let animations: [ModelAnimationClip]
    
    #if canImport(Metal)
    /// Initializes a new glTF model representation.
    public init(
        meshes: [MetalMesh],
        nodes: [GLTFNode],
        textureData: Data? = nil,
        animations: [ModelAnimationClip] = []
    ) {
        self.meshes = meshes
        self.nodes = nodes
        self.textureData = textureData
        self.animations = animations
    }
    #else
    /// Initializes a new glTF model representation.
    public init(
        meshes: [any Mesh],
        nodes: [GLTFNode],
        textureData: Data? = nil,
        animations: [ModelAnimationClip] = []
    ) {
        self.meshes = meshes
        self.nodes = nodes
        self.textureData = textureData
        self.animations = animations
    }
    #endif
    
    /// Instantiates the model in an ECS World, creating entities for each node and setting up
    /// transform hierarchies, mesh components, and a `ModelAnimationComponent` if animations are present.
    /// - Parameters:
    ///   - world: The ECS world.
    ///   - texture: Optional texture to apply to mesh components.
    /// - Returns: The root entity of the instantiated model.
    @MainActor
    public func instantiate(in world: World, color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1), texture: (any Texture)? = nil) -> Entity {
        let rootEntity = world.createEntity()
        world.addComponent(TransformComponent(), to: rootEntity)
        
        var nodeEntities: [Entity] = []
        nodeEntities.reserveCapacity(nodes.count)
        var restTransforms: [NodeRestTransform] = []
        restTransforms.reserveCapacity(nodes.count)
        
        for node in nodes {
            let entity = world.createEntity()
            world.setName(node.name, for: entity)
            
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
                let meshComp = MeshComponent(mesh: meshes[meshIdx], color: color, texture: texture)
                world.addComponent(meshComp, to: entity)
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
                nodeRestTransforms: restTransforms
            )
            world.addComponent(animComp, to: rootEntity)
        }
        
        return rootEntity
    }
}

/// A loader class responsible for loading glTF models from disk.
public final class GLTFModelLoader: Sendable {
    #if canImport(Metal)
    /// The Metal device to create mesh buffers on.
    private let device: (any MTLDevice)?
    #endif
    
    /// The generic renderer used to create meshes, if available.
    public let renderer: (any Renderer)?

    /// Initializes a new GLTFModelLoader with an abstract Renderer.
    /// - Parameter renderer: The Renderer backend to use.
    public init(renderer: any Renderer) {
        self.renderer = renderer
        #if canImport(Metal)
        self.device = (renderer as? MetalRenderer)?.device
        #endif
    }

    #if canImport(Metal)
    /// Initializes a new GLTFModelLoader with a Metal device.
    /// - Parameter device: The Metal device.
    public init(device: any MTLDevice) {
        self.device = device
        self.renderer = nil
    }

    /// Loads a glTF model from a local file URL producing MetalMesh instances.
    /// - Parameter url: The file URL of the model (.glb or .gltf).
    /// - Returns: A tuple containing the loaded meshes, nodes, raw texture data, and animation clips.
    /// - Throws: An error if loading fails.
    public func load(from url: URL) throws -> (meshes: [MetalMesh], nodes: [GLTFNode], textureData: Data?, animations: [ModelAnimationClip]) {
        guard let device = self.device else {
            throw NSError(domain: "GLTFModelLoaderErrorDomain", code: 4, userInfo: [NSLocalizedDescriptionKey: "Metal device required for loading MetalMesh."])
        }
        guard url.isFileURL else {
            throw NSError(domain: "GLTFModelLoaderErrorDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "Only file URLs are supported."])
        }

        let path = url.path
        let devicePtr = Unmanaged.passUnretained(device).toOpaque()

        // Allocate buffers to store output meshes, nodes, and animations
        var meshesPtrs = [UnsafeMutableRawPointer?](repeating: nil, count: 256)
        var nodesData = [Acorn.GLTFNodeData](repeating: Acorn.GLTFNodeData(), count: 256)
        var nodeCount: Int32 = 0
        var textureDataPtr: UnsafeRawPointer? = nil
        var textureSize: Int32 = 0
        var animContainer = Acorn.GLTFAnimationContainer()
        
        let count = Int(Acorn.GLTFLoader.loadRaw(
            path, 
            devicePtr, 
            &meshesPtrs, 
            256, 
            &nodesData, 
            256, 
            &nodeCount, 
            &textureDataPtr, 
            &textureSize,
            &animContainer
        ))

        guard count > 0 else {
            throw NSError(domain: "GLTFModelLoaderErrorDomain", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to load glTF meshes or file not found: \(path)"])
        }

        var meshes: [MetalMesh] = []
        meshes.reserveCapacity(count)
        for i in 0..<count {
            if let ptr = meshesPtrs[i] {
                let cxxMesh = ptr.assumingMemoryBound(to: Acorn.AcornMetalMesh.self)
                meshes.append(MetalMesh(cxxMesh: cxxMesh))
            }
        }

        var nodes: [GLTFNode] = []
        nodes.reserveCapacity(Int(nodeCount))
        for i in 0..<Int(nodeCount) {
            let data = nodesData[i]
            
            // Extract string from char[64] name tuple
            var nameBytes = [Int8]()
            withUnsafePointer(to: data.name) { ptr in
                ptr.withMemoryRebound(to: Int8.self, capacity: 64) { reboundPtr in
                    nameBytes = Array(UnsafeBufferPointer(start: reboundPtr, count: 64))
                }
            }
            if let nullIndex = nameBytes.firstIndex(of: 0) {
                nameBytes = Array(nameBytes[..<nullIndex])
            }
            let nodeName = String(decoding: nameBytes.map { UInt8(bitPattern: $0) }, as: UTF8.self)

            let meshIdx = data.meshIndex >= 0 ? Int(data.meshIndex) : nil
            let parentIdx = data.parentIndex >= 0 ? Int(data.parentIndex) : nil

            let translation = SIMD3<Float>(data.translation.0, data.translation.1, data.translation.2)
            let rotation = SIMD4<Float>(data.rotation.0, data.rotation.1, data.rotation.2, data.rotation.3)
            let scale = SIMD3<Float>(data.scale.0, data.scale.1, data.scale.2)

            nodes.append(GLTFNode(
                name: nodeName,
                meshIndex: meshIdx,
                parentIndex: parentIdx,
                translation: translation,
                rotation: rotation,
                scale: scale
            ))
        }

        var textureData: Data? = nil
        if let texPtr = textureDataPtr, textureSize > 0 {
            textureData = Data(bytes: texPtr, count: Int(textureSize))
        }

        // Extract animations
        var animations: [ModelAnimationClip] = []
        if animContainer.animationCount > 0, let animsPtr = animContainer.animations {
            for a in 0..<Int(animContainer.animationCount) {
                let animData = animsPtr[a]
                
                var nameBytes = [Int8]()
                withUnsafePointer(to: animData.name) { ptr in
                    ptr.withMemoryRebound(to: Int8.self, capacity: 64) { reboundPtr in
                        nameBytes = Array(UnsafeBufferPointer(start: reboundPtr, count: 64))
                    }
                }
                if let nullIndex = nameBytes.firstIndex(of: 0) {
                    nameBytes = Array(nameBytes[..<nullIndex])
                }
                var animName = String(decoding: nameBytes.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                if animName.isEmpty {
                    animName = "animation_\(a)"
                }
                
                var channels: [ModelAnimationChannel] = []
                if animData.channelCount > 0, let channelsPtr = animData.channels {
                    for c in 0..<Int(animData.channelCount) {
                        let chData = channelsPtr[c]
                        let nodeIdx = Int(chData.nodeIndex)
                        let pathVal = chData.path
                        let interpVal = chData.interpolation
                        let keyframeCount = Int(chData.keyframeCount)
                        let valuesPerKeyframe = Int(chData.valuesPerKeyframe)
                        
                        guard let path = ModelAnimationPath(rawValue: pathVal),
                              let interpolation = ModelAnimationInterpolation(rawValue: interpVal),
                              let tsPtr = chData.timestamps,
                              let valPtr = chData.values,
                              keyframeCount > 0 else {
                            continue
                        }
                        
                        let timestamps = Array(UnsafeBufferPointer(start: tsPtr, count: keyframeCount))
                        let totalVals = keyframeCount * valuesPerKeyframe
                        let values = Array(UnsafeBufferPointer(start: valPtr, count: totalVals))
                        
                        let nodeName = (nodeIdx >= 0 && nodeIdx < nodes.count) ? nodes[nodeIdx].name : nil
                        
                        let channel = ModelAnimationChannel(
                            targetNodeIndex: nodeIdx,
                            targetNodeName: nodeName,
                            path: path,
                            interpolation: interpolation,
                            keyframeTimes: timestamps,
                            keyframeValues: values,
                            valuesPerKeyframe: valuesPerKeyframe
                        )
                        channels.append(channel)
                    }
                }
                
                let clip = ModelAnimationClip(
                    name: animName,
                    duration: Double(animData.duration),
                    channels: channels,
                    playbackMode: .loop
                )
                animations.append(clip)
            }
        }
        Acorn.GLTFLoader.freeAnimationContainer(&animContainer)

        return (meshes: meshes, nodes: nodes, textureData: textureData, animations: animations)
    }

    /// Loads a glTF model returning a structured `GLTFModel` instance.
    /// - Parameter url: The file URL of the model (.glb or .gltf).
    /// - Returns: The loaded `GLTFModel`.
    /// - Throws: An error if loading fails.
    public func loadModel(from url: URL) throws -> GLTFModel {
        let result = try load(from: url)
        return GLTFModel(
            meshes: result.meshes,
            nodes: result.nodes,
            textureData: result.textureData,
            animations: result.animations
        )
    }
    #endif

    /// Loads a glTF model returning platform-agnostic Mesh resources.
    /// - Parameter url: The file URL of the model (.glb or .gltf).
    /// - Returns: A tuple containing the loaded meshes, nodes, raw texture data, and animation clips.
    /// - Throws: An error if loading fails.
    public func loadMeshes(from url: URL) throws -> (meshes: [any Mesh], nodes: [GLTFNode], textureData: Data?, animations: [ModelAnimationClip]) {
        #if canImport(Metal)
        if self.device != nil {
            let result = try load(from: url)
            return (meshes: result.meshes, nodes: result.nodes, textureData: result.textureData, animations: result.animations)
        }
        #endif
        throw NSError(domain: "GLTFModelLoaderErrorDomain", code: 2, userInfo: [NSLocalizedDescriptionKey: "Loading meshes requires a supported rendering device."])
    }
}
