import UIKit
import simd
import AcornEngine

/// Predefined city locations for the GPS 3D sample map.
public struct CityPreset: Sendable, Equatable {
    public let name: String
    public let coordinate: GPSCoordinate
    
    public init(name: String, coordinate: GPSCoordinate) {
        self.name = name
        self.coordinate = coordinate
    }
    
    public static let helsinki = CityPreset(name: "Helsinki", coordinate: GPSCoordinate(latitude: 60.1699, longitude: 24.9384, altitude: 0.0))
    public static let munich = CityPreset(name: "Munich", coordinate: GPSCoordinate(latitude: 48.1351, longitude: 11.5820, altitude: 0.0))
    public static let newYork = CityPreset(name: "New York", coordinate: GPSCoordinate(latitude: 40.7128, longitude: -74.0060, altitude: 0.0))
    public static let sanFrancisco = CityPreset(name: "San Francisco", coordinate: GPSCoordinate(latitude: 37.7749, longitude: -122.4194, altitude: 0.0))
    public static let tokyo = CityPreset(name: "Tokyo", coordinate: GPSCoordinate(latitude: 35.6762, longitude: 139.6503, altitude: 0.0))
    
    public static let all: [CityPreset] = [.helsinki, .munich, .newYork, .sanFrancisco, .tokyo]
}

/// Movement speed presets for the player character.
public enum MovementSpeedPreset: CaseIterable, Sendable {
    case walk
    case run
    case drive
    
    public var speed: Float {
        switch self {
        case .walk: return 4.0
        case .run: return 10.0
        case .drive: return 25.0
        }
    }
    
    public var title: String {
        switch self {
        case .walk: return "🚶 Walk"
        case .run: return "🏃 Run"
        case .drive: return "🚗 Drive"
        }
    }
    
    public var next: MovementSpeedPreset {
        switch self {
        case .walk: return .run
        case .run: return .drive
        case .drive: return .walk
        }
    }
}

/// A UIKit overlay view that provides game HUD elements, real-time GPS stats,
/// a virtual thumb joystick, and interactive buttons for camera and character controls.
@MainActor
public final class GameHUDView: UIView {
    // MARK: - Callbacks
    
    /// Called when the virtual joystick is moved with a normalized 2D vector `[-1, 1]`.
    public var onJoystickMoved: ((SIMD2<Float>) -> Void)?
    
    /// Called when the player changes movement speed.
    public var onSpeedChanged: ((Float) -> Void)?
    
    /// Called when the user selects a city preset.
    public var onCitySelected: ((GPSCoordinate) -> Void)?
    
    /// Called when the user requests camera recentering behind the player.
    public var onRecenterCamera: (() -> Void)?
    
    /// Called when the user requests camera focus to return to the player character.
    public var onFocusPlayer: (() -> Void)?
    
    /// Called when the user toggles post-apocalyptic rendering mode.
    public var onPostApocalypticToggled: ((Bool) -> Void)?
    
    /// Called when the user adjusts procedural moss density.
    public var onMossDensityChanged: ((Float) -> Void)?
    
    /// Called when the user toggles Screen Space Ambient Occlusion (SSAO).
    public var onSSAOToggled: ((Bool) -> Void)?
    
    // MARK: - State
    
    public private(set) var currentSpeedPreset: MovementSpeedPreset = .run
    public private(set) var isPostApocalypticEnabled: Bool = true
    public private(set) var isSSAOEnabled: Bool = true
    public private(set) var mossDensity: Float = 0.70
    public private(set) var isFollowingPlayer: Bool = true
    
    // MARK: - UI Elements
    
    private let infoCardView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let titleLabel = UILabel()
    private let latLonLabel = UILabel()
    private let tileLabel = UILabel()
    private let tilesLoadedLabel = UILabel()
    
    private let joystickBase = UIView()
    private let thumbKnob = UIView()
    private let joystickMaxRadius: CGFloat = 35.0
    
    private let controlsStackView = UIStackView()
    private let postApocButton = UIButton(type: .system)
    private let mossContainer = UIView()
    private let mossMinusButton = UIButton(type: .system)
    private let mossLabel = UILabel()
    private let mossPlusButton = UIButton(type: .system)
    private let ssaoButton = UIButton(type: .system)
    private let speedButton = UIButton(type: .system)
    private let cityButton = UIButton(type: .system)
    public let focusButton = UIButton(type: .system)
    private let recenterButton = UIButton(type: .system)
    
    // MARK: - Initializers
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    // MARK: - Touch Forwarding
    
    /// Forwards touches outside HUD interactables to the underlying Metal view.
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if infoCardView.frame.contains(point) {
            return true
        }
        if joystickBase.frame.contains(point) {
            return true
        }
        if controlsStackView.frame.contains(point) {
            return true
        }
        return false
    }
    
    // MARK: - Public Updaters
    
    /// Updates the displayed GPS latitude and longitude.
    /// - Parameter coordinate: Current GPS coordinate.
    public func updateGPS(_ coordinate: GPSCoordinate) {
        let latFormatted = coordinate.latitude.formatted(.number.precision(.fractionLength(5)))
        let lonFormatted = coordinate.longitude.formatted(.number.precision(.fractionLength(5)))
        latLonLabel.text = "Lat: \(latFormatted), Lon: \(lonFormatted)"
    }
    
    /// Updates the displayed tile coordinate and loaded tile count.
    /// - Parameters:
    ///   - coordinate: Current slippy map tile coordinate.
    ///   - loadedCount: Total count of currently loaded tiles.
    public func updateTile(coordinate: TileCoordinate, loadedCount: Int) {
        tileLabel.text = "Tile: Z\(coordinate.zoom) X\(coordinate.x) Y\(coordinate.y)"
        tilesLoadedLabel.text = "Tiles Loaded: \(loadedCount)"
    }
    
    /// Updates the loaded tile count label.
    /// - Parameter count: Number of active tiles loaded.
    public func updateLoadedTileCount(_ count: Int) {
        tilesLoadedLabel.text = "Tiles Loaded: \(count)"
    }
    
    /// Updates the focus button title and styling based on whether the camera is following the player.
    /// - Parameter isFollowingPlayer: Whether camera focus is currently locked onto the player character.
    public func setFocusState(isFollowingPlayer: Bool) {
        self.isFollowingPlayer = isFollowingPlayer
        if isFollowingPlayer {
            focusButton.setTitle("📍 Focused", for: .normal)
            focusButton.backgroundColor = UIColor(white: 0.12, alpha: 0.75)
            focusButton.setTitleColor(UIColor(white: 0.75, alpha: 1.0), for: .normal)
            focusButton.layer.borderColor = UIColor(white: 1.0, alpha: 0.25).cgColor
        } else {
            focusButton.setTitle("📍 Focus Player", for: .normal)
            focusButton.backgroundColor = UIColor(red: 0.15, green: 0.45, blue: 0.85, alpha: 0.90)
            focusButton.setTitleColor(.white, for: .normal)
            focusButton.layer.borderColor = UIColor(red: 0.35, green: 0.65, blue: 1.0, alpha: 0.8).cgColor
        }
    }
    
    // MARK: - Setup
    
    private func setupView() {
        backgroundColor = .clear
        
        setupTopInfoCard()
        setupVirtualJoystick()
        setupBottomControls()
    }
    
    private func setupTopInfoCard() {
        infoCardView.translatesAutoresizingMaskIntoConstraints = false
        infoCardView.layer.cornerRadius = 14.0
        infoCardView.layer.masksToBounds = true
        infoCardView.layer.borderWidth = 1.0
        infoCardView.layer.borderColor = UIColor(white: 1.0, alpha: 0.15).cgColor
        addSubview(infoCardView)
        
        titleLabel.text = "3D Map GPS Game"
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .white
        
        latLonLabel.text = "Lat: 0.00000, Lon: 0.00000"
        latLonLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        latLonLabel.textColor = UIColor(white: 0.9, alpha: 1.0)
        
        tileLabel.text = "Tile: Z-- X-- Y--"
        tileLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        tileLabel.textColor = UIColor(white: 0.8, alpha: 1.0)
        
        tilesLoadedLabel.text = "Tiles Loaded: 0"
        tilesLoadedLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        tilesLoadedLabel.textColor = UIColor(white: 0.8, alpha: 1.0)
        
        let stack = UIStackView(arrangedSubviews: [titleLabel, latLonLabel, tileLabel, tilesLoadedLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 3.0
        stack.alignment = .leading
        
        infoCardView.contentView.addSubview(stack)
        
        NSLayoutConstraint.activate([
            infoCardView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),
            infoCardView.centerXAnchor.constraint(equalTo: centerXAnchor),
            
            stack.topAnchor.constraint(equalTo: infoCardView.contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: infoCardView.contentView.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: infoCardView.contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: infoCardView.contentView.trailingAnchor, constant: -16)
        ])
    }
    
    private func setupVirtualJoystick() {
        joystickBase.translatesAutoresizingMaskIntoConstraints = false
        joystickBase.layer.cornerRadius = 60.0
        joystickBase.layer.masksToBounds = true
        joystickBase.backgroundColor = UIColor(white: 0.08, alpha: 0.65)
        joystickBase.layer.borderWidth = 2.0
        joystickBase.layer.borderColor = UIColor(white: 1.0, alpha: 0.25).cgColor
        addSubview(joystickBase)
        
        thumbKnob.translatesAutoresizingMaskIntoConstraints = false
        thumbKnob.layer.cornerRadius = 25.0
        thumbKnob.layer.masksToBounds = true
        thumbKnob.backgroundColor = UIColor(red: 0.25, green: 0.65, blue: 1.0, alpha: 0.85)
        thumbKnob.layer.borderWidth = 2.0
        thumbKnob.layer.borderColor = UIColor.white.cgColor
        joystickBase.addSubview(thumbKnob)
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleJoystickPan(_:)))
        joystickBase.addGestureRecognizer(panGesture)
        joystickBase.isUserInteractionEnabled = true
        
        NSLayoutConstraint.activate([
            joystickBase.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 24),
            joystickBase.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -24),
            joystickBase.widthAnchor.constraint(equalToConstant: 120),
            joystickBase.heightAnchor.constraint(equalToConstant: 120),
            
            thumbKnob.centerXAnchor.constraint(equalTo: joystickBase.centerXAnchor),
            thumbKnob.centerYAnchor.constraint(equalTo: joystickBase.centerYAnchor),
            thumbKnob.widthAnchor.constraint(equalToConstant: 50),
            thumbKnob.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    private func setupBottomControls() {
        controlsStackView.translatesAutoresizingMaskIntoConstraints = false
        controlsStackView.axis = .vertical
        controlsStackView.spacing = 10.0
        controlsStackView.alignment = .trailing
        addSubview(controlsStackView)
        
        // Post-Apocalyptic Toggle Button
        configurePillButton(postApocButton, title: "☣️ Post-Apoc: ON")
        postApocButton.backgroundColor = UIColor(red: 0.30, green: 0.22, blue: 0.10, alpha: 0.85)
        postApocButton.addTarget(self, action: #selector(handlePostApocTapped), for: .touchUpInside)
        controlsStackView.addArrangedSubview(postApocButton)
        
        // Moss Density Stepper Pill
        setupMossControl()
        controlsStackView.addArrangedSubview(mossContainer)
        
        // SSAO Toggle Button
        configurePillButton(ssaoButton, title: "🕶️ SSAO: ON")
        ssaoButton.backgroundColor = UIColor(red: 0.18, green: 0.28, blue: 0.38, alpha: 0.85)
        ssaoButton.addTarget(self, action: #selector(handleSSAOTapped), for: .touchUpInside)
        controlsStackView.addArrangedSubview(ssaoButton)
        
        // Speed Button
        configurePillButton(speedButton, title: currentSpeedPreset.title)
        speedButton.addTarget(self, action: #selector(handleSpeedTapped), for: .touchUpInside)
        controlsStackView.addArrangedSubview(speedButton)
        
        // City Button
        configurePillButton(cityButton, title: "🌍 Cities")
        setupCityMenu()
        controlsStackView.addArrangedSubview(cityButton)
        
        // Focus Player Button
        configurePillButton(focusButton, title: "📍 Focused")
        focusButton.setTitleColor(UIColor(white: 0.75, alpha: 1.0), for: .normal)
        focusButton.addTarget(self, action: #selector(handleFocusTapped), for: .touchUpInside)
        controlsStackView.addArrangedSubview(focusButton)
        
        // Recenter Camera Button
        recenterButton.translatesAutoresizingMaskIntoConstraints = false
        recenterButton.setTitle("🎯", for: .normal)
        recenterButton.titleLabel?.font = .systemFont(ofSize: 22)
        recenterButton.backgroundColor = UIColor(white: 0.12, alpha: 0.75)
        recenterButton.layer.cornerRadius = 24.0
        recenterButton.layer.borderWidth = 1.0
        recenterButton.layer.borderColor = UIColor(white: 1.0, alpha: 0.25).cgColor
        recenterButton.addTarget(self, action: #selector(handleRecenterTapped), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            recenterButton.widthAnchor.constraint(equalToConstant: 48),
            recenterButton.heightAnchor.constraint(equalToConstant: 48)
        ])
        controlsStackView.addArrangedSubview(recenterButton)
        
        NSLayoutConstraint.activate([
            controlsStackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -24),
            controlsStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
    }
    
    private func configurePillButton(_ button: UIButton, title: String) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.backgroundColor = UIColor(white: 0.12, alpha: 0.75)
        button.layer.cornerRadius = 18.0
        button.layer.borderWidth = 1.0
        button.layer.borderColor = UIColor(white: 1.0, alpha: 0.25).cgColor
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
    }
    
    private func setupCityMenu() {
        let menuActions = CityPreset.all.map { preset in
            UIAction(title: preset.name) { [weak self] _ in
                self?.onCitySelected?(preset.coordinate)
            }
        }
        cityButton.menu = UIMenu(title: "Select City", children: menuActions)
        cityButton.showsMenuAsPrimaryAction = true
    }
    
    private func setupMossControl() {
        mossContainer.translatesAutoresizingMaskIntoConstraints = false
        mossContainer.backgroundColor = UIColor(white: 0.12, alpha: 0.75)
        mossContainer.layer.cornerRadius = 18.0
        mossContainer.layer.borderWidth = 1.0
        mossContainer.layer.borderColor = UIColor(white: 1.0, alpha: 0.25).cgColor
        mossContainer.heightAnchor.constraint(equalToConstant: 36).isActive = true
        
        mossMinusButton.translatesAutoresizingMaskIntoConstraints = false
        mossMinusButton.setTitle("−", for: .normal)
        mossMinusButton.setTitleColor(.white, for: .normal)
        mossMinusButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        mossMinusButton.addTarget(self, action: #selector(handleMossMinusTapped), for: .touchUpInside)
        
        let pct = Int(mossDensity * 100)
        mossLabel.translatesAutoresizingMaskIntoConstraints = false
        mossLabel.text = "Moss: \(pct)%"
        mossLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        mossLabel.textColor = UIColor(red: 0.55, green: 0.85, blue: 0.35, alpha: 1.0)
        mossLabel.textAlignment = .center
        
        mossPlusButton.translatesAutoresizingMaskIntoConstraints = false
        mossPlusButton.setTitle("+", for: .normal)
        mossPlusButton.setTitleColor(.white, for: .normal)
        mossPlusButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        mossPlusButton.addTarget(self, action: #selector(handleMossPlusTapped), for: .touchUpInside)
        
        let stack = UIStackView(arrangedSubviews: [mossMinusButton, mossLabel, mossPlusButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 8.0
        stack.alignment = .center
        mossContainer.addSubview(stack)
        
        NSLayoutConstraint.activate([
            mossMinusButton.widthAnchor.constraint(equalToConstant: 24),
            mossPlusButton.widthAnchor.constraint(equalToConstant: 24),
            stack.leadingAnchor.constraint(equalTo: mossContainer.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: mossContainer.trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: mossContainer.centerYAnchor)
        ])
    }
    
    // MARK: - Actions
    
    @objc private func handleJoystickPan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: joystickBase)
        let distance = hypot(translation.x, translation.y)
        let clampedDist = min(distance, joystickMaxRadius)
        let angle = atan2(translation.y, translation.x)
        
        let clampedX = cos(angle) * clampedDist
        let clampedY = sin(angle) * clampedDist
        
        switch recognizer.state {
        case .began, .changed:
            thumbKnob.transform = CGAffineTransform(translationX: clampedX, y: clampedY)
            
            // Normalized input: right is +X, forward (up on screen) is +Y
            let normX = Float(clampedX / joystickMaxRadius)
            let normY = Float(-clampedY / joystickMaxRadius)
            onJoystickMoved?(SIMD2<Float>(normX, normY))
            
        case .ended, .cancelled:
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                usingSpringWithDamping: 0.6,
                initialSpringVelocity: 0.5,
                options: [.curveEaseOut]
            ) {
                self.thumbKnob.transform = .identity
            }
            onJoystickMoved?(.zero)
            
        default:
            break
        }
    }
    
    @objc private func handleSpeedTapped() {
        currentSpeedPreset = currentSpeedPreset.next
        speedButton.setTitle(currentSpeedPreset.title, for: .normal)
        onSpeedChanged?(currentSpeedPreset.speed)
    }
    
    @objc private func handleFocusTapped() {
        onFocusPlayer?()
    }
    
    @objc private func handleRecenterTapped() {
        onRecenterCamera?()
    }
    
    @objc private func handlePostApocTapped() {
        isPostApocalypticEnabled.toggle()
        let status = isPostApocalypticEnabled ? "ON" : "OFF"
        postApocButton.setTitle("☣️ Post-Apoc: \(status)", for: .normal)
        postApocButton.backgroundColor = isPostApocalypticEnabled ? UIColor(red: 0.30, green: 0.22, blue: 0.10, alpha: 0.85) : UIColor(white: 0.12, alpha: 0.75)
        mossContainer.isHidden = !isPostApocalypticEnabled
        ssaoButton.isHidden = !isPostApocalypticEnabled
        onPostApocalypticToggled?(isPostApocalypticEnabled)
    }
    
    @objc private func handleSSAOTapped() {
        isSSAOEnabled.toggle()
        let status = isSSAOEnabled ? "ON" : "OFF"
        ssaoButton.setTitle("🕶️ SSAO: \(status)", for: .normal)
        ssaoButton.backgroundColor = isSSAOEnabled ? UIColor(red: 0.18, green: 0.28, blue: 0.38, alpha: 0.85) : UIColor(white: 0.12, alpha: 0.75)
        onSSAOToggled?(isSSAOEnabled)
    }
    
    @objc private func handleMossMinusTapped() {
        mossDensity = max(0.0, mossDensity - 0.15)
        let pct = Int(round(mossDensity * 100))
        mossLabel.text = "Moss: \(pct)%"
        onMossDensityChanged?(mossDensity)
    }
    
    @objc private func handleMossPlusTapped() {
        mossDensity = min(1.0, mossDensity + 0.15)
        let pct = Int(round(mossDensity * 100))
        mossLabel.text = "Moss: \(pct)%"
        onMossDensityChanged?(mossDensity)
    }
}
