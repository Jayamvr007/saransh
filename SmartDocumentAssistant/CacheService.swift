//
//  CacheService.swift
//  SmartDocumentAssistant
//
//  Created by Jayam Verma on 13/12/25.
//


//
//  CacheService.swift
//  SmartDocumentAssistant
//

import Foundation

class CacheService {
    static let shared = CacheService()
    
    private let cacheDirectory: URL
    
    private init() {
        // Create cache directory in app's cache folder
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cachesURL.appendingPathComponent("DocumentSummaries")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Cache Operations
    
    func getCachedSummary(for documentName: String) -> [String]? {
        let cacheKey = sanitizeFilename(documentName)
        let cacheURL = cacheDirectory.appendingPathComponent("\(cacheKey).json")
        
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            print("❌ No cache found for: \(documentName)")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: cacheURL)
            let summary = try JSONDecoder().decode([String].self, from: data)
            print("✅ Loaded cached summary for: \(documentName)")
            return summary
        } catch {
            print("⚠️ Failed to load cache: \(error)")
            return nil
        }
    }
    
    func cacheSummary(_ summary: [String], for documentName: String) {
        let cacheKey = sanitizeFilename(documentName)
        let cacheURL = cacheDirectory.appendingPathComponent("\(cacheKey).json")
        
        do {
            let data = try JSONEncoder().encode(summary)
            try data.write(to: cacheURL)
            print("💾 Cached summary for: \(documentName)")
        } catch {
            print("⚠️ Failed to cache: \(error)")
        }
    }
    
    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        print("🗑️ Cache cleared")
    }
    
    func getCacheSize() -> String {
        let contents = (try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let totalSize = contents.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + size
        }
        return ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }
    
    // Helper to create valid filenames
    private func sanitizeFilename(_ name: String) -> String {
        return name.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
    }
}
