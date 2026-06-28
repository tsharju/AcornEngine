import Foundation
import simd

/// The type of projection to use for the camera.
public enum ProjectionType: Sendable {
    /// Orthographic projection, preserving parallel lines and ignoring depth perspective.
    case orthographic
    
    // Future expansion:
    // case perspective
}

/// A component that defines camera projection parameters.
public struct CameraComponent: Component {
    /// The type of projection used by this camera.
    public var projectionType: ProjectionType
    
    /// The vertical half-size of the orthographic viewing volume.
    public var orthographicSize: Float
    
    /// The near clipping plane distance.
    public var nearZ: Float
    
    /// The far clipping plane distance.
    public var farZ: Float
    
    /// The aspect ratio (width / height) of the camera viewport.
    /// This is typically updated dynamically by the renderer or window system.
    public var aspectRatio: Float
    
    /// Initializes a new camera component.
    /// - Parameters:
    ///   - projectionType: The projection type. Defaults to `.orthographic`.
    ///   - orthographicSize: The vertical half-size. Defaults to 5.0.
    ///   - nearZ: The near clipping plane. Defaults to 0.1.
    ///   - farZ: The far clipping plane. Defaults to 1000.0.
    ///   - aspectRatio: The aspect ratio. Defaults to 1.0.
    public init(
        projectionType: ProjectionType = .orthographic,
        orthographicSize: Float = 5.0,
        nearZ: Float = 0.1,
        farZ: Float = 1000.0,
        aspectRatio: Float = 1.0
    ) {
        self.projectionType = projectionType
        self.orthographicSize = orthographicSize
        self.nearZ = nearZ
        self.farZ = farZ
        self.aspectRatio = aspectRatio
    }
    
    /// Computes the projection matrix for this camera.
    public func projectionMatrix() -> simd_float4x4 {
        switch projectionType {
        case .orthographic:
            let right = orthographicSize * aspectRatio
            let top = orthographicSize
            return simd_float4x4(
                orthographic: -right,
                right: right,
                bottom: -top,
                top: top,
                nearZ: nearZ,
                farZ: farZ
            )
        }
    }
}
