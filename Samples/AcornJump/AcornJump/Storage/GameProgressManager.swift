import Foundation

/// Persistent user save state.
public struct PlayerSaveData: Codable, Sendable, Equatable {
    public var highestUnlockedLevel: Int = 1
    public var levelStars: [Int: Int] = [:] // level -> stars (1...3)
    public var levelHighScores: [Int: Int] = [:] // level -> score
    public var endlessHighScore: Int = 0
    public var totalGoldenAcorns: Int = 0
    public var soundEnabled: Bool = true
    public var musicEnabled: Bool = true
    
    public init() {}
}

/// Central manager for persisting and querying player progress, stars, scores, and settings.
@MainActor
public final class GameProgressManager {
    public static let shared = GameProgressManager()
    
    private var data: PlayerSaveData
    private let saveFileURL: URL
    private let userDefaultsKey = "AcornJump_PlayerSaveData"
    
    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.saveFileURL = docs.appendingPathComponent("acornjump_save.json")
        self.data = PlayerSaveData()
        loadData()
    }
    
    // MARK: - Query Accessors
    
    public var highestUnlockedLevel: Int {
        return max(1, min(100, data.highestUnlockedLevel))
    }
    
    public var endlessHighScore: Int {
        return data.endlessHighScore
    }
    
    public var totalGoldenAcorns: Int {
        return data.totalGoldenAcorns
    }
    
    public var soundEnabled: Bool {
        get { data.soundEnabled }
        set {
            data.soundEnabled = newValue
            saveData()
        }
    }
    
    public var musicEnabled: Bool {
        get { data.musicEnabled }
        set {
            data.musicEnabled = newValue
            saveData()
        }
    }
    
    public func isUnlocked(level: Int) -> Bool {
        return level <= data.highestUnlockedLevel
    }
    
    public func stars(for level: Int) -> Int {
        return data.levelStars[level] ?? 0
    }
    
    public func highScore(for level: Int) -> Int {
        return data.levelHighScores[level] ?? 0
    }
    
    public var totalStarsEarned: Int {
        return data.levelStars.values.reduce(0, +)
    }
    
    // MARK: - Progression Mutation
    
    /// Records completion of a campaign level.
    /// - Returns: `(isNewBestScore: Bool, isNewStarsRecord: Bool)`
    @discardableResult
    public func recordCampaignResult(
        level: Int,
        score: Int,
        stars: Int,
        acornsCollected: Int
    ) -> (isNewBestScore: Bool, isNewStarsRecord: Bool) {
        var isNewBest = false
        var isNewStars = false
        
        let previousBest = data.levelHighScores[level] ?? 0
        if score > previousBest {
            data.levelHighScores[level] = score
            isNewBest = true
        }
        
        let previousStars = data.levelStars[level] ?? 0
        if stars > previousStars {
            data.levelStars[level] = min(3, max(previousStars, stars))
            isNewStars = true
        }
        
        // Unlock next level if this level was completed with >= 1 star
        if stars >= 1 && level == data.highestUnlockedLevel && data.highestUnlockedLevel < 100 {
            data.highestUnlockedLevel += 1
        }
        
        data.totalGoldenAcorns += max(0, acornsCollected)
        saveData()
        
        return (isNewBest, isNewStars)
    }
    
    /// Records result for Endless Mode.
    /// - Returns: `true` if a new all-time high score was set.
    @discardableResult
    public func recordEndlessResult(score: Int, acornsCollected: Int) -> Bool {
        var isNewRecord = false
        if score > data.endlessHighScore {
            data.endlessHighScore = score
            isNewRecord = true
        }
        data.totalGoldenAcorns += max(0, acornsCollected)
        saveData()
        return isNewRecord
    }
    
    /// Spends golden acorns for cosmetics or upgrades.
    public func spendAcorns(_ amount: Int) -> Bool {
        guard amount <= data.totalGoldenAcorns else { return false }
        data.totalGoldenAcorns -= amount
        saveData()
        return true
    }
    
    /// Resets all progress (used for debug/testing).
    public func resetProgress() {
        data = PlayerSaveData()
        saveData()
    }
    
    // MARK: - Serialization
    
    private func loadData() {
        if FileManager.default.fileExists(atPath: saveFileURL.path),
           let fileData = try? Data(contentsOf: saveFileURL),
           let decoded = try? JSONDecoder().decode(PlayerSaveData.self, from: fileData) {
            self.data = decoded
            return
        }
        
        // Fallback to UserDefaults
        if let udData = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode(PlayerSaveData.self, from: udData) {
            self.data = decoded
            return
        }
        
        self.data = PlayerSaveData()
    }
    
    private func saveData() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(data) {
            try? encoded.write(to: saveFileURL, options: .atomic)
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
}
