#if canImport(UIKit) && canImport(QuartzCore) && canImport(Metal)
import Foundation
import Metal
import QuartzCore
import UIKit

/// Weakly-bridged `CADisplayLink` target avoiding retain cycles with `RenderSurfaceView`.
@MainActor
private final class RenderSurfaceDisplayLinkTarget: NSObject {
    weak var owner: RenderSurfaceView?

    @objc func handleDisplayLinkTick() {
        owner?.handleDisplayLinkTick()
    }
}

/// Holds display link and notification observer tokens for thread-safe teardown on deallocation.
private final class RenderSurfaceLoopHolder: @unchecked Sendable {
    var displayLink: CADisplayLink?
    var backgroundObserver: NSObjectProtocol?
    var foregroundObserver: NSObjectProtocol?

    deinit {
        displayLink?.invalidate()
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }
}

/// A `UIView` backed by `CAMetalLayer` and synchronized with a `CADisplayLink` for `NoGraphicsRenderer`.
@MainActor
public final class RenderSurfaceView: UIView {
    /// Uses `CAMetalLayer` as the Core Animation backing layer for Metal 4 swapchain presentation.
    public override class var layerClass: AnyClass {
        CAMetalLayer.self
    }

    /// The underlying `CAMetalLayer` backing this view.
    public var metalLayer: CAMetalLayer {
        guard let metalLayer = layer as? CAMetalLayer else {
            fatalError("RenderSurfaceView backing layer must be CAMetalLayer")
        }
        return metalLayer
    }

    /// Swapchain color pixel format applied to the backing `CAMetalLayer`.
    public var pixelFormat: SurfacePixelFormat = .bgra8UnormSRGB {
        didSet {
            applyPixelFormat()
        }
    }

    /// Clear color used by sample controllers when calling `Renderer.beginFrame(clearColor:)`.
    public var clearColor: SIMD4<Float> = SIMD4<Float>(0.1, 0.2, 0.3, 1.0)

    /// Preferred frame cadence requested from `CADisplayLink`.
    public var preferredFramesPerSecond: Int = 60 {
        didSet {
            loopHolder.displayLink?.preferredFramesPerSecond = preferredFramesPerSecond
        }
    }

    /// Pauses or resumes frame tick delivery while keeping the display link registered.
    public var isPaused: Bool = false {
        didSet {
            updateDisplayLinkPauseState()
        }
    }

    /// Current drawable dimensions in physical pixels.
    public private(set) var drawableSize: CGSize = .zero

    /// Called on the main actor whenever `drawableSize` changes after layout or scale updates.
    public var onDrawableSizeChanged: ((CGSize) -> Void)?

    /// Called on the main actor for each display link tick while attached to a window and active.
    public var onRenderFrame: (() -> Void)?

    /// Surface descriptor capturing the `CAMetalLayer` pointer and current pixel extent.
    public var surfaceDescriptor: RenderSurfaceDescriptor {
        let scale = resolvedScaleFactor()
        let pixelSize = currentPixelSize(scale: scale)
        return RenderSurfaceDescriptor(
            nativeLayer: Unmanaged.passUnretained(metalLayer).toOpaque(),
            width: max(1, Int(pixelSize.width)),
            height: max(1, Int(pixelSize.height)),
            scaleFactor: Float(scale),
            pixelFormat: pixelFormat
        )
    }

    private let loopHolder = RenderSurfaceLoopHolder()
    private let displayLinkTarget = RenderSurfaceDisplayLinkTarget()
    private var attachedRenderer: (any Renderer)?
    private var isApplicationActive = true

    /// Creates a `RenderSurfaceView` programmatically.
    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    /// Creates a `RenderSurfaceView` from Interface Builder archives.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    /// Associates a renderer so resize events and background transitions automatically synchronize GPU work.
    public func attachRenderer(_ renderer: (any Renderer)?) {
        attachedRenderer = renderer
        if drawableSize.width >= 1, drawableSize.height >= 1 {
            _ = attachedRenderer?.resizeSurface(
                width: Int(drawableSize.width),
                height: Int(drawableSize.height)
            )
        }
    }

    /// Starts the `CADisplayLink` render loop on the main run loop if not already active.
    public func startRendering() {
        registerLifecycleObserversIfNeeded()
        if loopHolder.displayLink == nil {
            let link = CADisplayLink(
                target: displayLinkTarget,
                selector: #selector(RenderSurfaceDisplayLinkTarget.handleDisplayLinkTick)
            )
            link.preferredFramesPerSecond = preferredFramesPerSecond
            link.add(to: .main, forMode: .common)
            loopHolder.displayLink = link
        }
        updateDrawableSizeIfNeeded()
        updateDisplayLinkPauseState()
    }

    /// Stops and invalidates the `CADisplayLink` render loop and drains pending GPU work.
    public func stopRendering() {
        loopHolder.displayLink?.invalidate()
        loopHolder.displayLink = nil
        attachedRenderer?.waitIdle()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            updateDrawableSizeIfNeeded()
        }
        updateDisplayLinkPauseState()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateDrawableSizeIfNeeded()
    }

    private func commonInit() {
        displayLinkTarget.owner = self
        metalLayer.framebufferOnly = true
        applyPixelFormat()
        registerForTraitChanges([UITraitDisplayScale.self]) { (view: RenderSurfaceView, _) in
            view.updateDrawableSizeIfNeeded()
        }
        registerLifecycleObserversIfNeeded()
    }

    private func applyPixelFormat() {
        switch pixelFormat {
        case .bgra8Unorm:
            metalLayer.pixelFormat = .bgra8Unorm
        case .bgra8UnormSRGB:
            metalLayer.pixelFormat = .bgra8Unorm_srgb
        case .rgba8Unorm:
            metalLayer.pixelFormat = .rgba8Unorm
        }
    }

    private func resolvedScaleFactor() -> CGFloat {
        if traitCollection.displayScale > 0 {
            return traitCollection.displayScale
        }
        if let screenScale = window?.windowScene?.screen.scale, screenScale > 0 {
            return screenScale
        }
        return 1.0
    }

    private func currentPixelSize(scale: CGFloat) -> CGSize {
        let width = (bounds.width * scale).rounded()
        let height = (bounds.height * scale).rounded()
        return CGSize(width: max(0, width), height: max(0, height))
    }

    private func updateDrawableSizeIfNeeded() {
        let scale = resolvedScaleFactor()
        contentScaleFactor = scale
        metalLayer.contentsScale = scale

        let pixelSize = currentPixelSize(scale: scale)
        guard pixelSize.width >= 1, pixelSize.height >= 1 else {
            return
        }

        if metalLayer.drawableSize != pixelSize {
            metalLayer.drawableSize = pixelSize
        }

        guard drawableSize != pixelSize else {
            return
        }

        drawableSize = pixelSize
        _ = attachedRenderer?.resizeSurface(
            width: Int(pixelSize.width),
            height: Int(pixelSize.height)
        )
        onDrawableSizeChanged?(pixelSize)
    }

    private func updateDisplayLinkPauseState() {
        let shouldPause = isPaused || !isApplicationActive || window == nil
        loopHolder.displayLink?.isPaused = shouldPause
    }

    private func registerLifecycleObserversIfNeeded() {
        let center = NotificationCenter.default
        if loopHolder.backgroundObserver == nil {
            loopHolder.backgroundObserver = center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleDidEnterBackground()
                }
            }
        }
        if loopHolder.foregroundObserver == nil {
            loopHolder.foregroundObserver = center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleWillEnterForeground()
                }
            }
        }
    }

    private func handleDidEnterBackground() {
        isApplicationActive = false
        updateDisplayLinkPauseState()
        attachedRenderer?.waitIdle()
    }

    private func handleWillEnterForeground() {
        isApplicationActive = true
        updateDrawableSizeIfNeeded()
        updateDisplayLinkPauseState()
    }

    fileprivate func handleDisplayLinkTick() {
        guard window != nil, !isPaused, isApplicationActive else {
            return
        }
        updateDrawableSizeIfNeeded()
        guard drawableSize.width >= 1, drawableSize.height >= 1 else {
            return
        }
        onRenderFrame?()
    }
}
#endif
