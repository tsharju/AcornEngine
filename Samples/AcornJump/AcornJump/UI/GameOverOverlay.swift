import UIKit

/// Game Over dialog overlay displaying final height, score, high score comparisons, and retry options.
@MainActor
public final class GameOverOverlay: UIView {
    
    public var onRetry: (() -> Void)?
    public var onLevelSelect: (() -> Void)?
    public var onMainMenu: (() -> Void)?
    
    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let heightLabel = UILabel()
    private let scoreLabel = UILabel()
    private let acornsLabel = UILabel()
    private let recordBadge = UILabel()
    
    private let retryButton = UIButton(type: .system)
    private let mapButton = UIButton(type: .system)
    private let menuButton = UIButton(type: .system)
    
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
        cardView.layer.borderColor = UIColor(red: 0.9, green: 0.3, blue: 0.25, alpha: 1.0).cgColor
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
        titleLabel.text = "💀 GAME OVER"
        titleLabel.font = UIFont.systemFont(ofSize: 28, weight: .black)
        titleLabel.textColor = UIColor(red: 0.95, green: 0.35, blue: 0.3, alpha: 1.0)
        titleLabel.textAlignment = .center
        stack.addArrangedSubview(titleLabel)
        
        // 2. Height & Score
        heightLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        heightLabel.textColor = .white
        heightLabel.textAlignment = .center
        stack.addArrangedSubview(heightLabel)
        
        scoreLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        scoreLabel.textColor = UIColor(white: 0.9, alpha: 1.0)
        scoreLabel.textAlignment = .center
        stack.addArrangedSubview(scoreLabel)
        
        acornsLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        acornsLabel.textColor = UIColor(red: 1.0, green: 0.75, blue: 0.2, alpha: 1.0)
        acornsLabel.textAlignment = .center
        stack.addArrangedSubview(acornsLabel)
        
        recordBadge.text = "🏆 NEW ALL-TIME RECORD!"
        recordBadge.font = UIFont.systemFont(ofSize: 15, weight: .heavy)
        recordBadge.textColor = .systemYellow
        recordBadge.textAlignment = .center
        recordBadge.isHidden = true
        stack.addArrangedSubview(recordBadge)
        
        // 3. Action Buttons
        styleButton(retryButton, title: "🔄 TRY AGAIN", bgColor: UIColor(red: 0.2, green: 0.75, blue: 0.35, alpha: 1.0))
        retryButton.addTarget(self, action: #selector(didTapRetry), for: .touchUpInside)
        stack.addArrangedSubview(retryButton)
        
        styleButton(mapButton, title: "🗺️ LEVEL SELECT", bgColor: UIColor(red: 0.25, green: 0.55, blue: 0.9, alpha: 1.0))
        mapButton.addTarget(self, action: #selector(didTapMap), for: .touchUpInside)
        stack.addArrangedSubview(mapButton)
        
        styleButton(menuButton, title: "🏠 MAIN MENU", bgColor: UIColor(white: 0.28, alpha: 0.9))
        menuButton.addTarget(self, action: #selector(didTapMenu), for: .touchUpInside)
        stack.addArrangedSubview(menuButton)
    }
    
    private func styleButton(_ button: UIButton, title: String, bgColor: UIColor) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        button.backgroundColor = bgColor
        button.layer.cornerRadius = 12
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
    }
    
    public func configure(height: Float, score: Int, acorns: Int, isNewBest: Bool, isCampaign: Bool) {
        heightLabel.text = "Height Reached: \(Int(height))m"
        scoreLabel.text = "Score: \(score)"
        acornsLabel.text = "Acorns Collected: 🌰 +\(acorns)"
        recordBadge.isHidden = !isNewBest
        mapButton.isHidden = !isCampaign
    }
    
    @objc private func didTapRetry() {
        onRetry?()
    }
    
    @objc private func didTapMap() {
        onLevelSelect?()
    }
    
    @objc private func didTapMenu() {
        onMainMenu?()
    }
}
