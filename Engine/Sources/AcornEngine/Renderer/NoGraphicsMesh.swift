import Foundation
internal import AcornRHI

/// Lifetime wrapper around an `AcornRHIDevice` handle so meshes and textures
/// safely outlive temporary references to `NoGraphicsRenderer`.
internal final class NoGraphicsDeviceBox: @unchecked Sendable {
    internal let handle: OpaquePointer

    internal init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        acorn_rhi_destroy_device(handle)
    }
}

/// A GPU-resident mesh backed by `NoGraphicsAPI`.
public final class NoGraphicsMesh: Mesh, @unchecked Sendable {
    /// The number of vertices in the mesh.
    public let vertexCount: Int

    /// The number of indices in the mesh (0 when non-indexed).
    public let indexCount: Int

    /// Whether the mesh uses the 80-byte skinned vertex layout.
    public let isSkinned: Bool

    #if DEBUG
    /// Host-side copy of the vertices for debugging and unit test inspection.
    public let vertices: [Vertex]
    #endif

    internal let deviceBox: NoGraphicsDeviceBox
    internal let rhiHandle: OpaquePointer

    internal init(
        deviceBox: NoGraphicsDeviceBox,
        rhiHandle: OpaquePointer,
        vertices: [Vertex] = []
    ) {
        self.deviceBox = deviceBox
        self.rhiHandle = rhiHandle
        self.vertexCount = Int(acorn_rhi_mesh_vertex_count(rhiHandle))
        self.indexCount = Int(acorn_rhi_mesh_index_count(rhiHandle))
        self.isSkinned = acorn_rhi_mesh_is_skinned(rhiHandle)
        #if DEBUG
        self.vertices = vertices
        #endif
    }

    deinit {
        acorn_rhi_destroy_mesh(deviceBox.handle, rhiHandle)
    }
}
