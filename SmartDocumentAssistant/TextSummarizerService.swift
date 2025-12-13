//
//  TextSummarizerService.swift
//  SmartDocumentAssistant
//
//  Created by Jayam Verma on 01/12/25.
//


// Add via SPM: https://github.com/fdzsergio/Reductio
import Reductio

class TextSummarizerService {
    // TextRank algorithm for extractive summarization
    func summarize(_ text: String, compression: Double = 0.7) async -> [String] {
        // Reductio.summarize is async, so we can call it directly
        return await Reductio.summarize(text: text, compression: Float(compression))
    }
    
    // Extract keywords
    func extractKeywords(_ text: String, count: Int = 10) async -> [String] {
        // Check if Reductio.keywords also has async version
        // If not, you may need to check the actual API
        // For now, using the async pattern
        return await Reductio.keywords(from: text, count: count)
    }
}
