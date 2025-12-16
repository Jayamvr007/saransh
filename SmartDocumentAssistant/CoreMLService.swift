//
//  CoreMLService.swift
//  SmartDocumentAssistant
//
//  Created by Jayam Verma on 01/12/25.
//

import CoreML
import NaturalLanguage
import Foundation

class CoreMLService {
    
    private let wordEmbedding = NLEmbedding.wordEmbedding(for: .english)
    private var documentClassifier: NLModel?
    
    // Universal Grammar Stop Words (Applies to ALL documents)
    private let universalStopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "is", "are", "was", "were",
        "to", "of", "in", "for", "on", "with", "at", "by", "from", "up",
        "about", "into", "over", "after", "that", "this", "these", "those",
        "he", "she", "it", "they", "we", "you", "i", "his", "her", "their",
        "has", "have", "had", "do", "does", "did", "will", "would", "can", "could",
        "as", "if", "so", "than", "then", "just", "now", "here", "there", "when",
        "where", "why", "how", "all", "any", "some", "no", "not", "only", "own",
        "same", "so", "than", "too", "very", "can", "will", "just", "don", "should",
        "now", "such", "other", "more", "most", "also", "which"
    ]
    
    init() {
        setupModels()
    }
    
    private func setupModels() {
        if let modelURL = Bundle.main.url(forResource: "DocumentClassifier", withExtension: "mlmodelc"),
           let mlModel = try? MLModel(contentsOf: modelURL) {
            documentClassifier = try? NLModel(mlModel: mlModel)
        }
    }

    // MARK: - Generalized Keyword Extraction
    
    func extractKeyPoints(_ text: String, count: Int = 5) -> [String] {
        let cleanedText = sanitizeDocumentText(text)
        
        // 1. Calculate Term Frequency
        let tf = calculateTermFrequency(cleanedText)
        
        // 2. Score words
        var scoredWords: [(String, Double)] = []
        for (word, frequency) in tf {
            let score = calculateRelevanceScore(word: word, frequency: frequency)
            if score > 0 {
                scoredWords.append((word, score))
            }
        }
        
        // 3. Deduplicate (Remove "Development" if "Developer" exists, keeping higher score)
        let uniqueWords = deduplicateLemmas(scoredWords)
        
        // 4. Return Top N
        return uniqueWords
            .sorted { $0.1 > $1.1 }
            .prefix(count)
            .map { $0.0 }
    }
    
    // MARK: - Scoring Logic
    
    private func calculateRelevanceScore(word: String, frequency: Int) -> Double {
        let lowerWord = word.lowercased()
        
        // FILTER 1: Stop Words & Length
        if universalStopWords.contains(lowerWord) { return 0.0 }
        if word.count < 3 { return 0.0 }
        
        // FILTER 2: Part of Speech & Entity Bonus
        var scoreMultiplier = 1.0
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = word
        let tag = tagger.tag(at: word.startIndex, unit: .word, scheme: .lexicalClass).0
        let nameTag = tagger.tag(at: word.startIndex, unit: .word, scheme: .nameType).0
        
        if nameTag == .personalName || nameTag == .placeName || nameTag == .organizationName {
            scoreMultiplier = 3.0 // Strongest signal (Entity)
        } else if tag == .noun {
            scoreMultiplier = 1.5 // Good signal
        } else if tag == .verb || tag == .adjective {
            scoreMultiplier = 0.5 // Penalty (e.g. "Working", "Good")
        } else {
            scoreMultiplier = 0.8 // Neutral
        }
        
        // FILTER 3: Suffix Penalty (Abstract Nouns vs Concrete Nouns)
        // Words ending in -ing, -ence, -ment are often abstract (Experience, Development)
        // Words without these are often concrete (Developer, Swift, Project)
        if lowerWord.hasSuffix("ing") || lowerWord.hasSuffix("ment") || lowerWord.hasSuffix("ence") || lowerWord.hasSuffix("tion") {
            scoreMultiplier *= 0.6 // Reduce score for abstract concepts
        }
        
        // FILTER 4: Capitalization Bonus
        if word.first?.isUppercase == true {
            scoreMultiplier *= 1.5
        }
        
        return Double(frequency) * scoreMultiplier
    }
    
    // Helper to remove variations like "Developer" vs "Development" vs "Developing"
    // Keeps the one with the highest score
    private func deduplicateLemmas(_ candidates: [(String, Double)]) -> [(String, Double)] {
        var bestCandidates: [String: (String, Double)] = [:] // Root -> (Original, Score)
        
        for (word, score) in candidates {
            // Simple stemming approximation (prefix matching)
            // e.g. "Develop" matches "Developer", "Development"
            // We use the first 4-5 chars as a "root key" for long words
            let key = (word.count > 5) ? String(word.prefix(5)).lowercased() : word.lowercased()
            
            if let existing = bestCandidates[key] {
                // If this variation has a higher score, replace it
                if score > existing.1 {
                    bestCandidates[key] = (word, score)
                }
            } else {
                bestCandidates[key] = (word, score)
            }
        }
        
        return Array(bestCandidates.values)
    }
    
    // MARK: - Summarization as Bullet Points with TF-IDF & Position Scoring
    func summarizeTextAsPoints(_ text: String, sentenceCount: Int = 5) -> [String] {
        let cleanedText = sanitizeDocumentText(text)
        guard !cleanedText.isEmpty else { return [] }
        
        let sentences = extractSentences(from: cleanedText)
        guard sentences.count > sentenceCount else { return sentences }
        
        // Score sentences using TF-IDF, position, and semantic similarity
        let scoredSentences = scoreSentencesByImportance(sentences)
        
        // Select top N sentences
        let topCount = min(sentenceCount, sentences.count)
        let topSentences = scoredSentences
            .sorted { $0.score > $1.score }
            .prefix(topCount)
            .sorted { $0.originalIndex < $1.originalIndex }
            .map { $0.sentence }
        
        return topSentences
    }
    
    // MARK: - Sentence Scoring with Multiple Factors
    private func scoreSentencesByImportance(_ sentences: [String]) -> [ScoredSentence] {
        // Calculate word frequencies for TF-IDF
        let allText = sentences.joined(separator: " ")
        let wordFreq = calculateTermFrequency(allText)
        
        let maxFreq = wordFreq.values.max() ?? 1
        
        // Score each sentence
        return sentences.enumerated().map { index, sentence in
            let words = sentence.lowercased().split(separator: " ").map(String.init)
            
            // TF-IDF Score (0.6 weight)
            var tfidfScore: Double = 0
            for word in words where !universalStopWords.contains(word) && word.count > 2 {
                let frequency = Double(wordFreq[word] ?? 0)
                let tf = frequency / Double(maxFreq)
                let idf = log(Double(sentences.count) / (Double(wordFreq.filter { $0.value > 0 && $0.key == word }.count) + 1))
                tfidfScore += tf * idf
            }
            
            // Position Score (0.2 weight) - Beginning sentences are more important
            let positionScore = Double(sentences.count - index) / Double(sentences.count)
            
            // Length Score (0.1 weight) - Moderate length is better
            let wordCount = words.count
            let lengthScore = min(1.0, Double(wordCount) / 30.0)
            
            // Semantic similarity to document (0.1 weight)
            let sentenceVectors = [sentenceVector(for: sentence)]
            let allVectors = sentences.map { sentenceVector(for: $0) }
            let documentCentroid = computeCentroid(of: allVectors) ?? Array(repeating: 0.0, count: 300)
            let semanticScore = sentenceVectors.isEmpty ? 0.0 : cosineSimilarity(sentenceVectors[0], documentCentroid)
            
            // Combined weighted score
            let totalScore = (tfidfScore * 0.6) + (positionScore * 0.2) + (lengthScore * 0.1) + (semanticScore * 0.1)
            
            return ScoredSentence(
                sentence: sentence,
                score: totalScore,
                originalIndex: index
            )
        }
    }

    
    private func calculateTermFrequency(_ text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range])
            // Only count if it's not a number or symbol
            if word.rangeOfCharacter(from: .letters) != nil {
                counts[word, default: 0] += 1
            }
            return true
        }
        return mergeCaseVariants(counts)
    }
    
    private func mergeCaseVariants(_ counts: [String: Int]) -> [String: Int] {
        var merged: [String: Int] = [:]
        var caseMap: [String: String] = [:]
        
        for (word, _) in counts {
            let lower = word.lowercased()
            if let existing = caseMap[lower] {
                if word.first?.isUppercase == true && existing.first?.isLowercase == true {
                    caseMap[lower] = word
                }
            } else {
                caseMap[lower] = word
            }
        }
        
        for (word, count) in counts {
            if let best = caseMap[word.lowercased()] {
                merged[best, default: 0] += count
            }
        }
        return merged
    }

    // MARK: - Semantic Summarization (Unchanged)
    
    func summarizeText(_ text: String, sentenceCount: Int = 5) -> String {
        let cleanedText = sanitizeDocumentText(text)
        guard !cleanedText.isEmpty else { return "" }
        let sentences = extractSentences(from: cleanedText)
        guard sentences.count > sentenceCount else { return cleanedText }
        let sentenceVectors = sentences.map { sentenceVector(for: $0) }
        guard let documentCentroid = computeCentroid(of: sentenceVectors) else {
            return sentences.prefix(min(sentences.count, sentenceCount)).joined(separator: "\n\n")
        }
        let scored = sentences.indices.map { ($0, cosineSimilarity(sentenceVectors[$0], documentCentroid)) }
        let top = scored.sorted { $0.1 > $1.1 }.prefix(sentenceCount).map { $0.0 }
        return top.sorted().map { sentences[$0] }.joined(separator: "\n\n")
    }
    
    // MARK: - Helpers (Unchanged)
    
    private func sanitizeDocumentText(_ text: String) -> String {
        var cleaned = text
        
        // Remove excessive whitespace
        cleaned = cleaned.replacingOccurrences(of: "\n", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        // Remove common artifacts (page numbers, headers/footers patterns)
        cleaned = cleaned.replacingOccurrences(of: "\\b(page|chapter|section)\\s*\\d+\\b", with: "", options: [.regularExpression, .caseInsensitive])
        
        // Remove multiple dots or dashes (cleaning)
        cleaned = cleaned.replacingOccurrences(of: "\\.{2,}", with: ".", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\-{2,}", with: "-", options: .regularExpression)
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractSentences(from text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if s.count > 20 { sentences.append(s) }
            return true
        }
        return sentences
    }
    
    private func sentenceVector(for sentence: String) -> [Double] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = sentence
        var vectors: [[Double]] = []
        tokenizer.enumerateTokens(in: sentence.startIndex..<sentence.endIndex) { range, _ in
            let word = String(sentence[range]).lowercased()
            if !universalStopWords.contains(word), let v = wordEmbedding?.vector(for: word) {
                vectors.append(v)
            }
            return true
        }
        let dim = wordEmbedding?.dimension ?? 300
        return computeCentroid(of: vectors) ?? Array(repeating: 0.0, count: dim)
    }
    
    private func computeCentroid(of vectors: [[Double]]) -> [Double]? {
        guard !vectors.isEmpty else { return nil }
        let dim = vectors[0].count
        var sum = Array(repeating: 0.0, count: dim)
        var count = 0
        for v in vectors { if v.count == dim { for i in 0..<dim { sum[i] += v[i] }; count += 1 } }
        return count > 0 ? sum.map { $0 / Double(count) } : nil
    }
    
    private func cosineSimilarity(_ v1: [Double], _ v2: [Double]) -> Double {
        guard v1.count == v2.count, !v1.isEmpty else { return 0.0 }
        var dot = 0.0, magA = 0.0, magB = 0.0
        for i in 0..<v1.count { dot += v1[i]*v2[i]; magA += v1[i]*v1[i]; magB += v2[i]*v2[i] }
        return (magA == 0 || magB == 0) ? 0.0 : dot / (sqrt(magA) * sqrt(magB))
    }
    
    func classifyDocument(_ text: String) -> String? {
        return documentClassifier?.predictedLabel(for: text)
    }
}

// MARK: - Helper Structures

struct ScoredSentence {
    let sentence: String
    let score: Double
    let originalIndex: Int
}
