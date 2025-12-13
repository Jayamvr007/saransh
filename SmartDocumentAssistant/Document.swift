//
//  Document.swift
//  SmartDocumentAssistant
//
//  Created by Jayam Verma on 01/12/25.
//

import Foundation
import UniformTypeIdentifiers

struct Document: Identifiable, Codable {
    let id: UUID
    let name: String
    let type: DocumentType
    let fileURL: URL
    let createdAt: Date
    var summary: String?
    var classification: String?
    var extractedText: String?
    
    init(id: UUID = UUID(), name: String, type: DocumentType, fileURL: URL, createdAt: Date = Date(), summary: String? = nil, classification: String? = nil, extractedText: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.summary = summary
        self.classification = classification
        self.extractedText = extractedText
    }
}


enum DocumentType: String, Codable {
    case pdf, audio, text
    
    var icon: String {
        switch self {
        case .pdf: return "doc.fill"
        case .audio: return "waveform"
        case .text: return "doc.text.fill"
        }
    }
}


struct ProcessingResult {
    let summary: String
    let keyPoints: [String]
    let classification: String?
    let processingTime: TimeInterval
}
