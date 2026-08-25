import UIKit

/// Start menu overlay displaying game title, campaign play button, level select, endless mode, and player statistics.
@MainActor
public final class MainMenuOverlay: UIView {
    
    public var onPlayCampaign: (() -> Void)?
    public var onOpenLevelSelect: (() -> Void)?
    public var onPlayEndless: (() -> Void)?
    public var onToggleSound: (() -> Void)?
    
    private let heroIconLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let statsCard = UIView()
    private let starsLabel = UILabel()
    private let acornsLabel = UILabel()
    private let endlessBestLabel = UILabel()
    
    private let playCampaignButton = UIButton(type: .system)
    private let levelSelectButton = UIButton(type: .system)
    private let endlessButton = UIButton(type: .system)
    private let soundButton = UIButton(type: .system)
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        backgroundColor = UIColor(red: 0.05, green: 0.12, blue: 0.08, alpha: 0.88)
        
        let container = UIStackView()
        container.axis = .vertical
        container.alignment = .fill
        container.distribution = .equalSpacing
        container.spacing = 18
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)
        
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: centerXAnchor),
            container.centerYAnchor.constraint(equalTo: centerYAnchor),
            container.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.86),
            container.topAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            container.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
        
        // 1. Title Header & Acorn Hero Mascot
        let titleStack = UIStackView()
        titleStack.axis = .vertical
        titleStack.alignment = .center
        titleStack.spacing = 6
        
        heroIconLabel.text = "🌰"
        heroIconLabel.font = UIFont.systemFont(ofSize: 64)
        heroIconLabel.textAlignment = .center
        titleStack.addArrangedSubview(heroIconLabel)
        
        titleLabel.text = "ACORN JUMP"
        titleLabel.font = UIFont.systemFont(ofSize: 42, weight: .black)
        titleLabel.textColor = UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0)
        titleLabel.textAlignment = .center
        titleStack.addArrangedSubview(titleLabel)
        
        subtitleLabel.text = "Ascend the 100-Level World Tree"
        subtitleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        subtitleLabel.textColor = UIColor(red: 0.85, green: 0.95, blue: 0.9, alpha: 1.0)
        subtitleLabel.textAlignment = .center
        titleStack.addArrangedSubview(subtitleLabel)
        
        container.addArrangedSubview(titleStack)
        
        // 2. Stats Card
        statsCard.backgroundColor = UIColor(white: 0.15, alpha: 0.85)
        statsCard.layer.cornerRadius = 16
        statsCard.layer.borderWidth = 1.5
        statsCard.layer.borderColor = UIColor(red: 0.3, green: 0.65, blue: 0.4, alpha: 0.8).cgColor
        
        let statsStack = UIStackView()
        statsStack.axis = .horizontal
        statsStack.distribution = .fillEqually
        statsStack.alignment = .center
        statsStack.translatesAutoresizingMaskIntoConstraints = false
        statsCard.addSubview(statsStack)
        
        NSLayoutConstraint.activate([
            statsStack.topAnchor.constraint(equalTo: statsCard.topAnchor, constant: 14),
            statsStack.bottomAnchor.constraint(equalTo: statsCard.bottomAnchor, constant: -14),
            statsStack.leadingAnchor.constraint(equalTo: statsCard.leadingAnchor, constant: 12),
            statsStack.trailingAnchor.constraint(equalTo: statsCard.trailingAnchor, constant: -12)
        ])
        
        starsLabel.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        starsLabel.textColor = .systemYellow
        starsLabel.textAlignment = .center
        statsStack.addArrangedSubview(starsLabel)
        
        acornsLabel.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        acornsLabel.textColor = UIColor(red: 1.0, green: 0.65, blue: 0.15, alpha: 1.0)
        acornsLabel.textAlignment = .center
        statsStack.addArrangedSubview(acornsLabel)
        
        endlessBestLabel.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        endlessBestLabel.textColor = .systemCyan
        endlessBestLabel.textAlignment = .center
        statsStack.addArrangedSubview(endlessBestLabel)
        
        container.addArrangedSubview(statsCard)
        
        // 3. Action Buttons
        styleButton(playCampaignButton, title: "▶️  PLAY CAMPAIGN", bgColor: UIColor(red: 0.2, green: 0.75, blue: 0.35, alpha: 1.0))
        playCampaignButton.addTarget(self, action: #selector(didTapPlayCampaign), for: .touchUpInside)
        container.addArrangedSubview(playCampaignButton)
        
        styleButton(levelSelectButton, title: "🗺️  100-LEVEL MAP", bgColor: UIColor(red: 0.25, green: 0.55, blue: 0.9, alpha: 1.0))
        levelSelectButton.addTarget(self, action: #selector(didTapLevelSelect), for: .touchUpInside)
        container.addArrangedSubview(levelSelectButton)
        
        styleButton(endlessButton, title: "🚀  ENDLESS CLIMB", bgColor: UIColor(red: 0.65, green: 0.3, blue: 0.85, alpha: 1.0))
        endlessButton.addTarget(self, action: #selector(didTapEndless), for: .touchUpInside)
        container.addArrangedSubview(endlessButton)
        
        // 4. Sound & Settings Row
        let bottomRow = UIStackView()
        bottomRow.axis = .horizontal
        bottomRow.distribution = .equalCentering
        bottomRow.alignment = .center
        
        soundButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        soundButton.addTarget(self, action: #selector(didTapSound), for: .touchUpInside)
        bottomRow.addArrangedSubview(soundButton)
        
        container.addArrangedSubview(bottomRow)
        
        refreshStats()
    }
    
    private func styleButton(_ button: UIButton, title: String, bgColor: UIColor) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .black)
        button.backgroundColor = bgColor
        button.layer.cornerRadius = 15
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.3
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.layer.shadowRadius = 6
        button.heightAnchor.constraint(equalToConstant: 56).isActive = true
    }
    
    public func refreshStats() {
        let mgr = GameProgressManager.shared
        let unlocked = mgr.highestUnlockedLevel
        let totalStars = mgr.totalStarsEarned
        let acorns = mgr.totalGoldenAcorns
        let endlessScore = mgr.endlessHighScore
        
        starsLabel.text = "⭐ \(totalStars)/300"
        acornsLabel.text = "🌰 \(acorns)"
        endlessBestLabel.text = "🏆 \(endlessScore)"
        
        playCampaignButton.setTitle("▶️  PLAY LEVEL \(unlocked)", for: .normal)
        
        soundButton.setTitle(mgr.soundEnabled ? "🔊 Sound: ON" : "🔇 Sound: OFF", for: .normal)
        soundButton.setTitleColor(mgr.soundEnabled ? .white : .lightGray, for: .normal)
    }
    
    @objc private func didTapPlayCampaign() {
        onPlayCampaign?()
    }
    
    @objc private func didTapLevelSelect() {
        onOpenLevelSelect?()
    }
    
    @objc private func didTapEndless() {
        onPlayEndless?()
    }
    
    @objc private func didTapSound() {
        GameProgressManager.shared.soundEnabled.toggle()
        refreshStats()
        onToggleSound?()
    }
}
