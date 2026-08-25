import UIKit

/// In-game HUD overlay displaying height, score, level progress bar, golden acorns, active powerup meter, and pause button.
@MainActor
public final class GameHUDOverlay: UIView {
    
    public var onPauseTapped: (() -> Void)?
    
    private let topStack = UIStackView()
    private let levelBadgeLabel = UILabel()
    private let scoreLabel = UILabel()
    private let acornsLabel = UILabel()
    private let pauseButton = UIButton(type: .system)
    
    private let progressContainer = UIView()
    private let progressBar = UIView()
    private var progressBarWidthConstraint: NSLayoutConstraint?
    private let progressLabel = UILabel()
    
    private let powerupBadge = UIView()
    private let powerupLabel = UILabel()
    private let powerupMeter = UIProgressView(progressViewStyle: .default)
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        isUserInteractionEnabled = true
        
        // 1. Top HUD Row
        topStack.axis = .horizontal
        topStack.distribution = .equalSpacing
        topStack.alignment = .center
        topStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topStack)
        
        NSLayoutConstraint.activate([
            topStack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 10),
            topStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            topStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            topStack.heightAnchor.constraint(equalToConstant: 38)
        ])
        
        levelBadgeLabel.font = UIFont.systemFont(ofSize: 13, weight: .heavy)
        levelBadgeLabel.textColor = .systemYellow
        levelBadgeLabel.backgroundColor = UIColor(white: 0.12, alpha: 0.8)
        levelBadgeLabel.layer.cornerRadius = 8
        levelBadgeLabel.layer.masksToBounds = true
        levelBadgeLabel.textAlignment = .center
        topStack.addArrangedSubview(levelBadgeLabel)
        
        scoreLabel.font = UIFont.systemFont(ofSize: 18, weight: .black)
        scoreLabel.textColor = .white
        scoreLabel.textAlignment = .center
        topStack.addArrangedSubview(scoreLabel)
        
        let rightStack = UIStackView()
        rightStack.axis = .horizontal
        rightStack.spacing = 10
        rightStack.alignment = .center
        
        acornsLabel.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        acornsLabel.textColor = UIColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1.0)
        rightStack.addArrangedSubview(acornsLabel)
        
        pauseButton.setTitle("⏸️", for: .normal)
        pauseButton.titleLabel?.font = UIFont.systemFont(ofSize: 20)
        pauseButton.addTarget(self, action: #selector(didTapPause), for: .touchUpInside)
        rightStack.addArrangedSubview(pauseButton)
        
        topStack.addArrangedSubview(rightStack)
        
        // 2. Level Progress Bar (Campaign Mode)
        progressContainer.backgroundColor = UIColor(white: 0.2, alpha: 0.75)
        progressContainer.layer.cornerRadius = 6
        progressContainer.layer.masksToBounds = true
        progressContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressContainer)
        
        progressBar.backgroundColor = UIColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1.0)
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressContainer.addSubview(progressBar)
        
        progressLabel.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        progressLabel.textColor = .white
        progressLabel.textAlignment = .center
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        progressContainer.addSubview(progressLabel)
        
        let widthConstraint = progressBar.widthAnchor.constraint(equalToConstant: 0)
        self.progressBarWidthConstraint = widthConstraint
        
        NSLayoutConstraint.activate([
            progressContainer.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 6),
            progressContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressContainer.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.8),
            progressContainer.heightAnchor.constraint(equalToConstant: 16),
            
            progressBar.topAnchor.constraint(equalTo: progressContainer.topAnchor),
            progressBar.bottomAnchor.constraint(equalTo: progressContainer.bottomAnchor),
            progressBar.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor),
            widthConstraint,
            
            progressLabel.centerXAnchor.constraint(equalTo: progressContainer.centerXAnchor),
            progressLabel.centerYAnchor.constraint(equalTo: progressContainer.centerYAnchor)
        ])
        
        // 3. Powerup Gauge Card (Hidden when no powerup)
        powerupBadge.backgroundColor = UIColor(red: 0.1, green: 0.4, blue: 0.6, alpha: 0.85)
        powerupBadge.layer.cornerRadius = 10
        powerupBadge.translatesAutoresizingMaskIntoConstraints = false
        powerupBadge.isHidden = true
        addSubview(powerupBadge)
        
        let powerupStack = UIStackView()
        powerupStack.axis = .horizontal
        powerupStack.spacing = 8
        powerupStack.alignment = .center
        powerupStack.translatesAutoresizingMaskIntoConstraints = false
        powerupBadge.addSubview(powerupStack)
        
        powerupLabel.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        powerupLabel.textColor = .white
        powerupStack.addArrangedSubview(powerupLabel)
        
        powerupMeter.progressTintColor = .systemYellow
        powerupMeter.trackTintColor = UIColor(white: 0.3, alpha: 0.8)
        powerupMeter.widthAnchor.constraint(equalToConstant: 80).isActive = true
        powerupStack.addArrangedSubview(powerupMeter)
        
        NSLayoutConstraint.activate([
            powerupBadge.topAnchor.constraint(equalTo: progressContainer.bottomAnchor, constant: 8),
            powerupBadge.centerXAnchor.constraint(equalTo: centerXAnchor),
            powerupStack.topAnchor.constraint(equalTo: powerupBadge.topAnchor, constant: 6),
            powerupStack.bottomAnchor.constraint(equalTo: powerupBadge.bottomAnchor, constant: -6),
            powerupStack.leadingAnchor.constraint(equalTo: powerupBadge.leadingAnchor, constant: 12),
            powerupStack.trailingAnchor.constraint(equalTo: powerupBadge.trailingAnchor, constant: -12)
        ])
    }
    
    public func update(
        height: Float,
        targetHeight: Float,
        score: Int,
        acorns: Int,
        isCampaign: Bool,
        levelNumber: Int,
        activePowerup: PowerupType?,
        powerupTimeRemaining: Float,
        shieldCharges: Int
    ) {
        scoreLabel.text = "Score: \(score)"
        acornsLabel.text = "🌰 \(acorns)"
        
        if isCampaign {
            levelBadgeLabel.text = "  Lvl \(levelNumber)  "
            progressContainer.isHidden = false
            
            let progress = min(1.0, max(0.0, height / targetHeight))
            let totalWidth = progressContainer.bounds.width > 0 ? progressContainer.bounds.width : (bounds.width * 0.8)
            progressBarWidthConstraint?.constant = totalWidth * CGFloat(progress)
            progressLabel.text = "\(Int(height))m / \(Int(targetHeight))m 🏁"
        } else {
            levelBadgeLabel.text = " 🚀 Endless "
            progressContainer.isHidden = true
        }
        
        // Powerup status
        if let powerup = activePowerup {
            powerupBadge.isHidden = false
            switch powerup {
            case .jetpack(let duration):
                powerupLabel.text = "🚀 Jetpack"
                powerupMeter.progress = max(0.0, min(1.0, powerupTimeRemaining / duration))
            case .propeller(let duration):
                powerupLabel.text = "🚁 Propeller"
                powerupMeter.progress = max(0.0, min(1.0, powerupTimeRemaining / duration))
            case .shield:
                powerupLabel.text = "🛡️ Shield (\(shieldCharges))"
                powerupMeter.progress = 1.0
            case .springShoes(let jumps):
                powerupLabel.text = "👟 Spring Shoes (\(jumps))"
                powerupMeter.progress = 1.0
            }
        } else if shieldCharges > 0 {
            powerupBadge.isHidden = false
            powerupLabel.text = "🛡️ Shield (\(shieldCharges))"
            powerupMeter.progress = 1.0
        } else {
            powerupBadge.isHidden = true
        }
    }
    
    @objc private func didTapPause() {
        onPauseTapped?()
    }
}
