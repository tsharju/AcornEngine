import UIKit

/// Level cleared / Victory celebration overlay with star rewards, score summary, and progression buttons.
@MainActor
public final class VictoryOverlay: UIView {
    
    public var onNextLevel: (() -> Void)?
    public var onReplay: (() -> Void)?
    public var onLevelSelect: (() -> Void)?
    public var onMainMenu: (() -> Void)?
    
    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let starsLabel = UILabel()
    private let scoreLabel = UILabel()
    private let acornsLabel = UILabel()
    private let recordBadge = UILabel()
    
    private let nextButton = UIButton(type: .system)
    private let replayButton = UIButton(type: .system)
    private let mapButton = UIButton(type: .system)
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        backgroundColor = UIColor.black.withAlphaComponent(0.75)
        
        cardView.backgroundColor = UIColor(white: 0.12, alpha: 0.95)
        cardView.layer.cornerRadius = 24
        cardView.layer.borderWidth = 2.5
        cardView.layer.borderColor = UIColor(red: 0.25, green: 0.8, blue: 0.4, alpha: 1.0).cgColor
        cardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardView)
        
        NSLayoutConstraint.activate([
            cardView.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: centerYAnchor),
            cardView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.86),
            cardView.topAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor, constant: 40),
            cardView.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -40)
        ])
        
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.distribution = .equalSpacing
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20)
        ])
        
        // 1. Title
        titleLabel.text = "🎉 LEVEL CLEARED!"
        titleLabel.font = UIFont.systemFont(ofSize: 28, weight: .black)
        titleLabel.textColor = UIColor(red: 0.3, green: 0.9, blue: 0.45, alpha: 1.0)
        titleLabel.textAlignment = .center
        stack.addArrangedSubview(titleLabel)
        
        // 2. Stars
        starsLabel.font = UIFont.systemFont(ofSize: 42)
        starsLabel.textAlignment = .center
        stack.addArrangedSubview(starsLabel)
        
        // 3. Score & Acorns
        scoreLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        scoreLabel.textColor = .white
        scoreLabel.textAlignment = .center
        stack.addArrangedSubview(scoreLabel)
        
        acornsLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        acornsLabel.textColor = UIColor(red: 1.0, green: 0.75, blue: 0.2, alpha: 1.0)
        acornsLabel.textAlignment = .center
        stack.addArrangedSubview(acornsLabel)
        
        recordBadge.text = "🏆 NEW BEST RECORD!"
        recordBadge.font = UIFont.systemFont(ofSize: 15, weight: .heavy)
        recordBadge.textColor = .systemYellow
        recordBadge.textAlignment = .center
        recordBadge.isHidden = true
        stack.addArrangedSubview(recordBadge)
        
        // 4. Buttons
        styleButton(nextButton, title: "▶️ NEXT LEVEL", bgColor: UIColor(red: 0.2, green: 0.75, blue: 0.35, alpha: 1.0))
        nextButton.addTarget(self, action: #selector(didTapNext), for: .touchUpInside)
        stack.addArrangedSubview(nextButton)
        
        styleButton(replayButton, title: "🔄 REPLAY LEVEL", bgColor: UIColor(white: 0.3, alpha: 0.9))
        replayButton.addTarget(self, action: #selector(didTapReplay), for: .touchUpInside)
        stack.addArrangedSubview(replayButton)
        
        styleButton(mapButton, title: "🗺️ LEVEL SELECT", bgColor: UIColor(red: 0.2, green: 0.5, blue: 0.85, alpha: 1.0))
        mapButton.addTarget(self, action: #selector(didTapMap), for: .touchUpInside)
        stack.addArrangedSubview(mapButton)
    }
    
    private func styleButton(_ button: UIButton, title: String, bgColor: UIColor) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        button.backgroundColor = bgColor
        button.layer.cornerRadius = 12
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
    }
    
    public func configure(level: Int, score: Int, stars: Int, acorns: Int, isNewBest: Bool) {
        titleLabel.text = "🎉 LEVEL \(level) CLEARED!"
        
        switch stars {
        case 3: starsLabel.text = "⭐⭐⭐"
        case 2: starsLabel.text = "⭐⭐"
        case 1: starsLabel.text = "⭐"
        default: starsLabel.text = "⭐"
        }
        
        scoreLabel.text = "Final Score: \(score)"
        acornsLabel.text = "Acorns Collected: 🌰 +\(acorns)"
        recordBadge.isHidden = !isNewBest
        
        nextButton.isHidden = level >= 100
    }
    
    @objc private func didTapNext() {
        onNextLevel?()
    }
    
    @objc private func didTapReplay() {
        onReplay?()
    }
    
    @objc private func didTapMap() {
        onLevelSelect?()
    }
}
