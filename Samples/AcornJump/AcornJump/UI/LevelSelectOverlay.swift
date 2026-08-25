import UIKit

/// 100-Level Campaign selector overlay organized across 10 Forest Zone tabs.
@MainActor
public final class LevelSelectOverlay: UIView {
    
    public var onSelectLevel: ((Int) -> Void)?
    public var onBackToMenu: (() -> Void)?
    
    private var currentZoneIndex: Int = 1 // 1...10
    
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    
    private let zoneCard = UIView()
    private let prevZoneButton = UIButton(type: .system)
    private let nextZoneButton = UIButton(type: .system)
    private let zoneTitleLabel = UILabel()
    private let zoneSubtitleLabel = UILabel()
    
    private let gridContainer = UIView()
    private let gridStack = UIStackView()
    private var levelButtons: [UIButton] = []
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        backgroundColor = UIColor(red: 0.04, green: 0.10, blue: 0.08, alpha: 0.94)
        
        // 1. Top Header
        let headerView = UIView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerView)
        
        backButton.setTitle("◀ Back", for: .normal)
        backButton.setTitleColor(UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0), for: .normal)
        backButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        backButton.addTarget(self, action: #selector(didTapBack), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(backButton)
        
        titleLabel.text = "100-LEVEL MAP"
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .black)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            headerView.heightAnchor.constraint(equalToConstant: 44),
            
            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
        
        // 2. Zone Selection Card
        zoneCard.backgroundColor = UIColor(white: 0.14, alpha: 0.9)
        zoneCard.layer.cornerRadius = 16
        zoneCard.layer.borderWidth = 1.5
        zoneCard.layer.borderColor = UIColor(red: 0.25, green: 0.6, blue: 0.4, alpha: 0.8).cgColor
        zoneCard.translatesAutoresizingMaskIntoConstraints = false
        addSubview(zoneCard)
        
        let zoneNav = UIStackView()
        zoneNav.axis = .horizontal
        zoneNav.alignment = .center
        zoneNav.distribution = .fill
        zoneNav.spacing = 10
        zoneNav.translatesAutoresizingMaskIntoConstraints = false
        zoneCard.addSubview(zoneNav)
        
        prevZoneButton.setTitle("◀", for: .normal)
        prevZoneButton.setTitleColor(.white, for: .normal)
        prevZoneButton.titleLabel?.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        prevZoneButton.backgroundColor = UIColor(white: 0.22, alpha: 0.9)
        prevZoneButton.layer.cornerRadius = 10
        prevZoneButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        prevZoneButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        prevZoneButton.addTarget(self, action: #selector(didTapPrevZone), for: .touchUpInside)
        zoneNav.addArrangedSubview(prevZoneButton)
        
        let zoneTextStack = UIStackView()
        zoneTextStack.axis = .vertical
        zoneTextStack.alignment = .center
        zoneTextStack.spacing = 3
        
        zoneTitleLabel.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        zoneTitleLabel.textColor = UIColor(red: 1.0, green: 0.85, blue: 0.25, alpha: 1.0)
        zoneTitleLabel.textAlignment = .center
        zoneTitleLabel.numberOfLines = 1
        zoneTextStack.addArrangedSubview(zoneTitleLabel)
        
        zoneSubtitleLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        zoneSubtitleLabel.textColor = UIColor(white: 0.85, alpha: 1.0)
        zoneSubtitleLabel.textAlignment = .center
        zoneSubtitleLabel.numberOfLines = 1
        zoneTextStack.addArrangedSubview(zoneSubtitleLabel)
        
        zoneNav.addArrangedSubview(zoneTextStack)
        
        nextZoneButton.setTitle("▶", for: .normal)
        nextZoneButton.setTitleColor(.white, for: .normal)
        nextZoneButton.titleLabel?.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        nextZoneButton.backgroundColor = UIColor(white: 0.22, alpha: 0.9)
        nextZoneButton.layer.cornerRadius = 10
        nextZoneButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        nextZoneButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        nextZoneButton.addTarget(self, action: #selector(didTapNextZone), for: .touchUpInside)
        zoneNav.addArrangedSubview(nextZoneButton)
        
        NSLayoutConstraint.activate([
            zoneCard.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 14),
            zoneCard.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            zoneCard.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            zoneNav.topAnchor.constraint(equalTo: zoneCard.topAnchor, constant: 12),
            zoneNav.bottomAnchor.constraint(equalTo: zoneCard.bottomAnchor, constant: -12),
            zoneNav.leadingAnchor.constraint(equalTo: zoneCard.leadingAnchor, constant: 12),
            zoneNav.trailingAnchor.constraint(equalTo: zoneCard.trailingAnchor, constant: -12)
        ])
        
        // 3. Level Grid
        gridStack.axis = .vertical
        gridStack.alignment = .fill
        gridStack.distribution = .fillEqually
        gridStack.spacing = 14
        gridStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gridStack)
        
        for _ in 0..<2 {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.alignment = .fill
            rowStack.distribution = .fillEqually
            rowStack.spacing = 12
            
            for _ in 0..<5 {
                let btn = UIButton(type: .system)
                btn.titleLabel?.numberOfLines = 0
                btn.titleLabel?.textAlignment = .center
                btn.layer.cornerRadius = 14
                btn.layer.borderWidth = 1.5
                btn.addTarget(self, action: #selector(didTapLevelButton(_:)), for: .touchUpInside)
                rowStack.addArrangedSubview(btn)
                levelButtons.append(btn)
            }
            gridStack.addArrangedSubview(rowStack)
        }
        
        NSLayoutConstraint.activate([
            gridStack.topAnchor.constraint(equalTo: zoneCard.bottomAnchor, constant: 24),
            gridStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            gridStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            gridStack.heightAnchor.constraint(equalToConstant: 220)
        ])
        
        let currentUnlocked = GameProgressManager.shared.highestUnlockedLevel
        currentZoneIndex = ZoneTheme.zone(for: currentUnlocked).rawValue
        refreshZone()
    }
    
    public func refreshZone() {
        guard let zone = ZoneTheme(rawValue: currentZoneIndex) else { return }
        
        zoneTitleLabel.text = "Zone \(currentZoneIndex)/10: \(zone.title)"
        zoneSubtitleLabel.text = zone.subtitle
        
        prevZoneButton.isEnabled = currentZoneIndex > 1
        prevZoneButton.alpha = currentZoneIndex > 1 ? 1.0 : 0.35
        
        nextZoneButton.isEnabled = currentZoneIndex < 10
        nextZoneButton.alpha = currentZoneIndex < 10 ? 1.0 : 0.35
        
        let startLevel = (currentZoneIndex - 1) * 10 + 1
        let mgr = GameProgressManager.shared
        
        for i in 0..<10 {
            let levelNum = startLevel + i
            let btn = levelButtons[i]
            btn.tag = levelNum
            
            let isUnlocked = mgr.isUnlocked(level: levelNum)
            let stars = mgr.stars(for: levelNum)
            let highScore = mgr.highScore(for: levelNum)
            
            if isUnlocked {
                btn.isEnabled = true
                btn.backgroundColor = UIColor(red: 0.16, green: 0.42, blue: 0.28, alpha: 0.95)
                btn.layer.borderColor = UIColor(red: 0.3, green: 0.85, blue: 0.45, alpha: 1.0).cgColor
                
                let starStr: String
                switch stars {
                case 3: starStr = "⭐⭐⭐"
                case 2: starStr = "⭐⭐"
                case 1: starStr = "⭐"
                default: starStr = "—"
                }
                
                let title = "\(levelNum)\n\(starStr)\n\(highScore > 0 ? "\(highScore)" : "")"
                let attrTitle = NSMutableAttributedString(string: title)
                btn.setAttributedTitle(attrTitle, for: .normal)
                btn.setTitleColor(.white, for: .normal)
            } else {
                btn.isEnabled = false
                btn.backgroundColor = UIColor(white: 0.12, alpha: 0.7)
                btn.layer.borderColor = UIColor(white: 0.25, alpha: 0.5).cgColor
                btn.setTitle("\(levelNum)\n🔒", for: .normal)
                btn.setTitleColor(UIColor(white: 0.5, alpha: 1.0), for: .normal)
            }
        }
    }
    
    @objc private func didTapPrevZone() {
        if currentZoneIndex > 1 {
            currentZoneIndex -= 1
            refreshZone()
        }
    }
    
    @objc private func didTapNextZone() {
        if currentZoneIndex < 10 {
            currentZoneIndex += 1
            refreshZone()
        }
    }
    
    @objc private func didTapLevelButton(_ sender: UIButton) {
        let levelNum = sender.tag
        if GameProgressManager.shared.isUnlocked(level: levelNum) {
            onSelectLevel?(levelNum)
        }
    }
    
    @objc private func didTapBack() {
        onBackToMenu?()
    }
}
