import Foundation
import AcornMath

/// Target transform property animated by an animation channel.
public enum ModelAnimationPath: UInt8, Sendable, Codable, Equatable, Hashable {
    case translation = 1
    case rotation = 2
    case scale = 3
    case weights = 4
}

/// Interpolation algorithm applied between animation keyframes.
public enum ModelAnimationInterpolation: UInt8, Sendable, Codable, Equatable, Hashable {
    case linear = 0
    case step = 1
    case cubicSpline = 2
}

/// An individual animation track binding a sequence of keyframes to a specific node transform property.
public struct ModelAnimationChannel: Sendable, Equatable {
    /// The index of the target node in the model hierarchy.
    public var targetNodeIndex: Int
    
    /// Optional human-readable name of the target node.
    public var targetNodeName: String?
    
    /// The transform property modified by this channel.
    public var path: ModelAnimationPath
    
    /// The interpolation method used between keyframes.
    public var interpolation: ModelAnimationInterpolation
    
    /// Keyframe timestamps in seconds, sorted in ascending order.
    public var keyframeTimes: [Float]
    
    /// Raw keyframe values (3 floats per keyframe for Vec3, 4 for Vec4, or 3x for CubicSpline).
    public var keyframeValues: [Float]
    
    /// The number of float elements per keyframe in `keyframeValues`.
    public var valuesPerKeyframe: Int
    
    /// Initializes a new animation channel.
    public init(
        targetNodeIndex: Int,
        targetNodeName: String? = nil,
        path: ModelAnimationPath,
        interpolation: ModelAnimationInterpolation = .linear,
        keyframeTimes: [Float],
        keyframeValues: [Float],
        valuesPerKeyframe: Int
    ) {
        self.targetNodeIndex = targetNodeIndex
        self.targetNodeName = targetNodeName
        self.path = path
        self.interpolation = interpolation
        self.keyframeTimes = keyframeTimes
        self.keyframeValues = keyframeValues
        self.valuesPerKeyframe = valuesPerKeyframe
    }
    
    /// Evaluates a 3D vector property (translation or scale) at the given time in seconds.
    public func evaluateVec3(at time: Float) -> SIMD3<Float>? {
        guard !keyframeTimes.isEmpty else { return nil }
        
        let count = keyframeTimes.count
        if count == 1 || time <= keyframeTimes[0] {
            return readVec3(keyframeIndex: 0, component: .value)
        }
        if time >= keyframeTimes[count - 1] {
            return readVec3(keyframeIndex: count - 1, component: .value)
        }
        
        let i = findKeyframeIndex(time)
        let t0 = keyframeTimes[i]
        let t1 = keyframeTimes[i + 1]
        let dt = t1 - t0
        let alpha = dt > 0.00001 ? (time - t0) / dt : 0.0
        
        switch interpolation {
        case .step:
            return readVec3(keyframeIndex: i, component: .value)
            
        case .linear:
            guard let v0 = readVec3(keyframeIndex: i, component: .value),
                  let v1 = readVec3(keyframeIndex: i + 1, component: .value) else {
                return nil
            }
            return mix(v0, v1, t: alpha)
            
        case .cubicSpline:
            guard let p0 = readVec3(keyframeIndex: i, component: .value),
                  let m0 = readVec3(keyframeIndex: i, component: .outTangent),
                  let p1 = readVec3(keyframeIndex: i + 1, component: .value),
                  let k1 = readVec3(keyframeIndex: i + 1, component: .inTangent) else {
                return nil
            }
            let t = alpha
            let t2 = t * t
            let t3 = t2 * t
            let h00 = 2.0 * t3 - 3.0 * t2 + 1.0
            let h10 = t3 - 2.0 * t2 + t
            let h01 = -2.0 * t3 + 3.0 * t2
            let h11 = t3 - t2
            return p0 * h00 + m0 * (dt * h10) + p1 * h01 + k1 * (dt * h11)
        }
    }
    
    /// Evaluates a 4D quaternion rotation property at the given time in seconds.
    public func evaluateVec4(at time: Float) -> SIMD4<Float>? {
        guard !keyframeTimes.isEmpty else { return nil }
        
        let count = keyframeTimes.count
        if count == 1 || time <= keyframeTimes[0] {
            return readVec4(keyframeIndex: 0, component: .value)
        }
        if time >= keyframeTimes[count - 1] {
            return readVec4(keyframeIndex: count - 1, component: .value)
        }
        
        let i = findKeyframeIndex(time)
        let t0 = keyframeTimes[i]
        let t1 = keyframeTimes[i + 1]
        let dt = t1 - t0
        let alpha = dt > 0.00001 ? (time - t0) / dt : 0.0
        
        switch interpolation {
        case .step:
            return readVec4(keyframeIndex: i, component: .value)
            
        case .linear:
            guard let q0 = readVec4(keyframeIndex: i, component: .value),
                  let q1 = readVec4(keyframeIndex: i + 1, component: .value) else {
                return nil
            }
            return slerp(q0, q1, t: alpha)
            
        case .cubicSpline:
            guard let p0 = readVec4(keyframeIndex: i, component: .value),
                  let m0 = readVec4(keyframeIndex: i, component: .outTangent),
                  let p1 = readVec4(keyframeIndex: i + 1, component: .value),
                  let k1 = readVec4(keyframeIndex: i + 1, component: .inTangent) else {
                return nil
            }
            let t = alpha
            let t2 = t * t
            let t3 = t2 * t
            let h00 = 2.0 * t3 - 3.0 * t2 + 1.0
            let h10 = t3 - 2.0 * t2 + t
            let h01 = -2.0 * t3 + 3.0 * t2
            let h11 = t3 - t2
            let res = p0 * h00 + m0 * (dt * h10) + p1 * h01 + k1 * (dt * h11)
            return normalize(res)
        }
    }
    
    // MARK: - Internal Helpers
    
    private enum SplineComponent {
        case inTangent
        case value
        case outTangent
    }
    
    private func findKeyframeIndex(_ time: Float) -> Int {
        var low = 0
        var high = keyframeTimes.count - 2
        while low <= high {
            let mid = (low + high) / 2
            if time < keyframeTimes[mid] {
                high = mid - 1
            } else if time >= keyframeTimes[mid + 1] {
                low = mid + 1
            } else {
                return mid
            }
        }
        return max(0, min(low, keyframeTimes.count - 2))
    }
    
    private func readVec3(keyframeIndex: Int, component: SplineComponent) -> SIMD3<Float>? {
        let baseOffset: Int
        if interpolation == .cubicSpline {
            let compOffset: Int
            switch component {
            case .inTangent: compOffset = 0
            case .value: compOffset = 3
            case .outTangent: compOffset = 6
            }
            baseOffset = keyframeIndex * 9 + compOffset
        } else {
            baseOffset = keyframeIndex * valuesPerKeyframe
        }
        
        guard baseOffset + 2 < keyframeValues.count else { return nil }
        return SIMD3<Float>(
            keyframeValues[baseOffset],
            keyframeValues[baseOffset + 1],
            keyframeValues[baseOffset + 2]
        )
    }
    
    private func readVec4(keyframeIndex: Int, component: SplineComponent) -> SIMD4<Float>? {
        let baseOffset: Int
        if interpolation == .cubicSpline {
            let compOffset: Int
            switch component {
            case .inTangent: compOffset = 0
            case .value: compOffset = 4
            case .outTangent: compOffset = 8
            }
            baseOffset = keyframeIndex * 12 + compOffset
        } else {
            baseOffset = keyframeIndex * valuesPerKeyframe
        }
        
        guard baseOffset + 3 < keyframeValues.count else { return nil }
        return SIMD4<Float>(
            keyframeValues[baseOffset],
            keyframeValues[baseOffset + 1],
            keyframeValues[baseOffset + 2],
            keyframeValues[baseOffset + 3]
        )
    }
}
