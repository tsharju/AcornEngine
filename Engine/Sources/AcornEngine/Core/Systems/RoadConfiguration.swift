import Foundation
import simd
internal import AcornMapGeometry

/// Visual and geometric style defining how a specific road class is rendered.
public struct RoadLayerStyle: Sendable, Equatable {
    /// Pavement width of the road ribbon in meters.
    public var width: Float
    /// Outline fraction on each side of the ribbon (e.g. 0.18 for 18% border width).
    public var outlineRatio: Float
    /// Vertical elevation offset above ground in meters (used for hierarchy stacking).
    public var elevation: Float
    /// Surface pavement color (RGBA).
    public var color: SIMD4<Float>
    /// Outer border outline color (RGBA).
    public var outlineColor: SIMD4<Float>
    
    /// Initializes a new road layer style.
    /// - Parameters:
    ///   - width: Road width in meters.
    ///   - outlineRatio: Outline ratio fraction (default 0.18).
    ///   - elevation: Elevation offset in meters (default 0.05).
    ///   - color: Surface fill color (default off-white).
    ///   - outlineColor: Outline border color (default slate grey).
    public init(
        width: Float,
        outlineRatio: Float = 0.18,
        elevation: Float = 0.05,
        color: SIMD4<Float> = SIMD4<Float>(0.98, 0.98, 0.98, 1.0),
        outlineColor: SIMD4<Float> = SIMD4<Float>(0.55, 0.55, 0.60, 1.0)
    ) {
        self.width = width
        self.outlineRatio = outlineRatio
        self.elevation = elevation
        self.color = color
        self.outlineColor = outlineColor
    }
}

/// Configuration specifying which road layers are rendered and their individual visual styles.
public struct RoadConfiguration: Sendable, Equatable {
    /// Whether to explicitly filter out ways not intended for cars (e.g. pedestrian paths, cycleways, footways, tracks, steps).
    public var filterNonCarRoads: Bool
    
    /// If true, only road classes explicitly configured in `layerStyles` will be rendered.
    public var renderOnlyConfiguredClasses: Bool
    
    /// Optional default style applied to road classes not explicitly listed in `layerStyles`.
    public var defaultStyle: RoadLayerStyle?
    
    /// Dictionary mapping road class names to their rendering styles.
    public var layerStyles: [String: RoadLayerStyle]
    
    /// Initializes a road configuration.
    /// - Parameters:
    ///   - filterNonCarRoads: Whether to filter out non-car ways (default `true`).
    ///   - renderOnlyConfiguredClasses: Whether to only render configured classes (default `true`).
    ///   - defaultStyle: Optional fallback style for unconfigured classes.
    ///   - layerStyles: Dictionary of road class styles.
    public init(
        filterNonCarRoads: Bool = true,
        renderOnlyConfiguredClasses: Bool = true,
        defaultStyle: RoadLayerStyle? = nil,
        layerStyles: [String: RoadLayerStyle] = [:]
    ) {
        self.filterNonCarRoads = filterNonCarRoads
        self.renderOnlyConfiguredClasses = renderOnlyConfiguredClasses
        self.defaultStyle = defaultStyle
        self.layerStyles = layerStyles
    }
    
    /// Sets or replaces the style for a road class.
    public mutating func setStyle(_ style: RoadLayerStyle, for roadClass: String) {
        layerStyles[roadClass] = style
    }
    
    /// Removes a road class style, excluding it from rendering if `renderOnlyConfiguredClasses` is true.
    public mutating func removeStyle(for roadClass: String) {
        layerStyles.removeValue(forKey: roadClass)
    }
    
    /// Returns the style for a given road class if defined.
    public func style(for roadClass: String) -> RoadLayerStyle? {
        return layerStyles[roadClass]
    }
    
    /// Default car-only road configuration. Leaves out non-car layers (pedestrian paths, cycleways, footways, tracks, steps).
    public static var carOnly: RoadConfiguration {
        var styles: [String: RoadLayerStyle] = [:]
        
        // Motorway
        let motorway = RoadLayerStyle(
            width: 14.0,
            outlineRatio: 0.18,
            elevation: 0.10,
            color: SIMD4<Float>(0.98, 0.70, 0.35, 1.0),
            outlineColor: SIMD4<Float>(0.45, 0.30, 0.15, 1.0)
        )
        styles["motorway"] = motorway
        styles["motorway_link"] = motorway
        
        // Trunk
        let trunk = RoadLayerStyle(
            width: 12.0,
            outlineRatio: 0.18,
            elevation: 0.09,
            color: SIMD4<Float>(0.98, 0.78, 0.40, 1.0),
            outlineColor: SIMD4<Float>(0.50, 0.35, 0.20, 1.0)
        )
        styles["trunk"] = trunk
        styles["trunk_link"] = trunk
        
        // Primary
        let primary = RoadLayerStyle(
            width: 10.5,
            outlineRatio: 0.18,
            elevation: 0.08,
            color: SIMD4<Float>(0.99, 0.88, 0.55, 1.0),
            outlineColor: SIMD4<Float>(0.55, 0.45, 0.25, 1.0)
        )
        styles["primary"] = primary
        styles["primary_link"] = primary
        
        // Secondary
        let secondary = RoadLayerStyle(
            width: 8.5,
            outlineRatio: 0.18,
            elevation: 0.07,
            color: SIMD4<Float>(0.96, 0.95, 0.88, 1.0),
            outlineColor: SIMD4<Float>(0.50, 0.50, 0.52, 1.0)
        )
        styles["secondary"] = secondary
        styles["secondary_link"] = secondary
        
        // Tertiary
        let tertiary = RoadLayerStyle(
            width: 7.0,
            outlineRatio: 0.18,
            elevation: 0.06,
            color: SIMD4<Float>(0.93, 0.93, 0.93, 1.0),
            outlineColor: SIMD4<Float>(0.55, 0.55, 0.58, 1.0)
        )
        styles["tertiary"] = tertiary
        styles["tertiary_link"] = tertiary
        
        // Street / residential
        let street = RoadLayerStyle(
            width: 6.0,
            outlineRatio: 0.18,
            elevation: 0.05,
            color: SIMD4<Float>(0.98, 0.98, 0.98, 1.0),
            outlineColor: SIMD4<Float>(0.55, 0.55, 0.60, 1.0)
        )
        styles["street"] = street
        styles["residential"] = street
        styles["street_limited"] = street
        styles["living_street"] = street
        
        // Service / driveway / alley
        let service = RoadLayerStyle(
            width: 4.5,
            outlineRatio: 0.20,
            elevation: 0.045,
            color: SIMD4<Float>(0.88, 0.88, 0.88, 1.0),
            outlineColor: SIMD4<Float>(0.60, 0.60, 0.62, 1.0)
        )
        styles["service"] = service
        styles["driveway"] = service
        styles["alley"] = service
        
        return RoadConfiguration(
            filterNonCarRoads: true,
            renderOnlyConfiguredClasses: true,
            defaultStyle: nil,
            layerStyles: styles
        )
    }
    
    /// Configuration that includes all road layers, including pedestrian paths, cycleways, and tracks.
    public static var allRoads: RoadConfiguration {
        var config = RoadConfiguration.carOnly
        config.filterNonCarRoads = false
        config.renderOnlyConfiguredClasses = false
        config.defaultStyle = RoadLayerStyle(
            width: 5.5,
            outlineRatio: 0.18,
            elevation: 0.05,
            color: SIMD4<Float>(0.92, 0.92, 0.92, 1.0),
            outlineColor: SIMD4<Float>(0.55, 0.55, 0.58, 1.0)
        )
        
        // Non-car layers
        config.setStyle(RoadLayerStyle(
            width: 4.0, outlineRatio: 0.22, elevation: 0.04,
            color: SIMD4<Float>(0.85, 0.82, 0.78, 1.0), outlineColor: SIMD4<Float>(0.60, 0.58, 0.55, 1.0)
        ), for: "pedestrian")
        
        config.setStyle(RoadLayerStyle(
            width: 3.0, outlineRatio: 0.22, elevation: 0.04,
            color: SIMD4<Float>(0.85, 0.82, 0.78, 1.0), outlineColor: SIMD4<Float>(0.60, 0.58, 0.55, 1.0)
        ), for: "path")
        
        config.setStyle(RoadLayerStyle(
            width: 3.0, outlineRatio: 0.20, elevation: 0.04,
            color: SIMD4<Float>(0.80, 0.85, 0.82, 1.0), outlineColor: SIMD4<Float>(0.50, 0.58, 0.55, 1.0)
        ), for: "cycleway")
        
        config.setStyle(RoadLayerStyle(
            width: 2.5, outlineRatio: 0.22, elevation: 0.04,
            color: SIMD4<Float>(0.85, 0.82, 0.78, 1.0), outlineColor: SIMD4<Float>(0.60, 0.58, 0.55, 1.0)
        ), for: "footway")
        
        config.setStyle(RoadLayerStyle(
            width: 2.5, outlineRatio: 0.25, elevation: 0.04,
            color: SIMD4<Float>(0.82, 0.80, 0.80, 1.0), outlineColor: SIMD4<Float>(0.55, 0.55, 0.55, 1.0)
        ), for: "steps")
        
        config.setStyle(RoadLayerStyle(
            width: 3.5, outlineRatio: 0.22, elevation: 0.04,
            color: SIMD4<Float>(0.82, 0.78, 0.72, 1.0), outlineColor: SIMD4<Float>(0.58, 0.54, 0.50, 1.0)
        ), for: "track")
        
        return config
    }
}

// MARK: - C++ Interoperability

extension RoadLayerStyle {
    /// Converts this Swift style to C++ `AcornMap.RoadLayerStyle`.
    package func toCxx() -> AcornMap.RoadLayerStyle {
        var cxx = AcornMap.RoadLayerStyle()
        cxx.widthMeters = width
        cxx.outlineRatio = outlineRatio
        cxx.elevation = elevation
        cxx.r = color.x
        cxx.g = color.y
        cxx.b = color.z
        cxx.a = color.w
        cxx.outlineR = outlineColor.x
        cxx.outlineG = outlineColor.y
        cxx.outlineB = outlineColor.z
        cxx.outlineA = outlineColor.w
        return cxx
    }
    
    /// Initializes a Swift `RoadLayerStyle` from C++ `AcornMap.RoadLayerStyle`.
    package init(cxx: AcornMap.RoadLayerStyle) {
        self.init(
            width: cxx.widthMeters,
            outlineRatio: cxx.outlineRatio,
            elevation: cxx.elevation,
            color: SIMD4<Float>(cxx.r, cxx.g, cxx.b, cxx.a),
            outlineColor: SIMD4<Float>(cxx.outlineR, cxx.outlineG, cxx.outlineB, cxx.outlineA)
        )
    }
}

extension RoadConfiguration {
    /// Converts this Swift configuration to C++ `AcornMap.RoadConfiguration`.
    package func toCxx() -> AcornMap.RoadConfiguration {
        var cxx = AcornMap.RoadConfiguration()
        cxx.filterNonCarRoads = filterNonCarRoads
        cxx.renderOnlyConfiguredClasses = renderOnlyConfiguredClasses
        if let def = defaultStyle {
            cxx.hasDefaultStyle = true
            cxx.defaultStyle = def.toCxx()
        } else {
            cxx.hasDefaultStyle = false
        }
        cxx.clearStyles()
        for (roadClass, style) in layerStyles {
            cxx.addStyle(std.__1.string(roadClass), style.toCxx())
        }
        return cxx
    }
}
