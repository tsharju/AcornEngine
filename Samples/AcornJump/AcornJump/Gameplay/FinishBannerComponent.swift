import Foundation
import simd
import AcornEngine

/// ECS Component for the level finish line banner.
public struct FinishBannerComponent: Component {
    public var targetHeight: Float
    public var isTriggered: Bool = false
    
    public init(targetHeight: Float) {
        self.targetHeight = targetHeight
    }
}
