import Foundation

class CacheService {
    static let shared = CacheService()
    
    private let cache = NSCache<NSString, CacheEntry>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    
    private class CacheEntry {
        let explanation: String
        let timestamp: Date
        let learningStyle: LearningStyle
        
        init(explanation: String, timestamp: Date, learningStyle: LearningStyle) {
            self.explanation = explanation
            self.timestamp = timestamp
            self.learningStyle = learningStyle
        }
    }
    
    private init() {
        // Set up cache directory
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cachesDirectory.appendingPathComponent("CursorAssistant")
        
        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Configure memory cache
        cache.countLimit = 100 // Max 100 entries in memory
        cache.totalCostLimit = 10 * 1024 * 1024 // 10MB max memory
        
        // Load persistent cache on startup
        loadPersistentCache()
        
        // Clean up old cache entries
        cleanupOldCache()
    }
    
    func getExplanation(for term: String, learningStyle: LearningStyle) -> String? {
        let key = cacheKey(term: term, learningStyle: learningStyle)
        
        // Check memory cache first
        if let entry = cache.object(forKey: key as NSString) {
            // Check if entry is still valid
            if Date().timeIntervalSince(entry.timestamp) < maxCacheAge {
                return entry.explanation
            } else {
                cache.removeObject(forKey: key as NSString)
            }
        }
        
        return nil
    }
    
    func setExplanation(_ explanation: String, for term: String, learningStyle: LearningStyle) {
        let key = cacheKey(term: term, learningStyle: learningStyle)
        let entry = CacheEntry(explanation: explanation, timestamp: Date(), learningStyle: learningStyle)
        
        // Store in memory cache
        cache.setObject(entry, forKey: key as NSString)
        
        // Persist to disk
        persistEntry(entry, for: key)
    }
    
    private func cacheKey(term: String, learningStyle: LearningStyle) -> String {
        return "\(term.lowercased())_\(learningStyle.rawValue)"
    }
    
    private func persistEntry(_ entry: CacheEntry, for key: String) {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")
        
        let data: [String: Any] = [
            "explanation": entry.explanation,
            "timestamp": entry.timestamp.timeIntervalSince1970,
            "learningStyle": entry.learningStyle.rawValue
        ]
        
        try? JSONSerialization.data(withJSONObject: data).write(to: fileURL)
    }
    
    private func loadPersistentCache() {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        
        for file in files {
            guard file.pathExtension == "json" else { continue }
            
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let explanation = json["explanation"] as? String,
                  let timestamp = json["timestamp"] as? TimeInterval,
                  let learningStyleString = json["learningStyle"] as? String,
                  let learningStyle = LearningStyle(rawValue: learningStyleString) else {
                continue
            }
            
            let entry = CacheEntry(
                explanation: explanation,
                timestamp: Date(timeIntervalSince1970: timestamp),
                learningStyle: learningStyle
            )
            
            let key = file.deletingPathExtension().lastPathComponent
            cache.setObject(entry, forKey: key as NSString)
        }
    }
    
    private func cleanupOldCache() {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }
        
        let now = Date()
        
        for file in files {
            guard file.pathExtension == "json" else { continue }
            
            if let modificationDate = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                if now.timeIntervalSince(modificationDate) > maxCacheAge {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
    }
    
    func clearCache() {
        cache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    func getCacheStats() -> (count: Int, size: Int) {
        var count = 0
        var totalSize = 0
        
        if let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for file in files where file.pathExtension == "json" {
                count += 1
                if let fileSize = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += fileSize
                }
            }
        }
        
        return (count, totalSize)
    }
}