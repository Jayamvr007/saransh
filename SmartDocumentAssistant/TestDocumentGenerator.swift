//
//  TestDocumentGenerator.swift
//  SmartDocumentAssistant
//
//  Created by Jayam Verma on 13/12/25.
//

import Foundation
import PDFKit
import UIKit

class TestDocumentGenerator {
    static let shared = TestDocumentGenerator()
    
    private init() {}
    
    func generateAllTestDocuments() -> [TestDocument] {
        return [
            TestDocument(
                name: "✅ Normal Resume",
                generator: createNormalResume,
                expectedBehavior: .success(5)
            ),
            TestDocument(
                name: "📄 Short Document (1 page)",
                generator: createShortDocument,
                expectedBehavior: .success(3)
            ),
            TestDocument(
                name: "📚 Long Book (500 pages)",
                generator: createLongBook,
                expectedBehavior: .success(50)
            ),
            TestDocument(
                name: "🖼️ Image-Only PDF (Scanned)",
                generator: createImageOnlyPDF,
                expectedBehavior: .error(.imageOnlyPDF)
            ),
            TestDocument(
                name: "🔒 Password Protected",
                generator: createPasswordProtectedPDF,
                expectedBehavior: .error(.passwordProtected)
            ),
            TestDocument(
                name: "💥 Corrupted PDF",
                generator: createCorruptedPDF,
                expectedBehavior: .error(.corrupted)
            ),
            TestDocument(
                name: "📭 Empty PDF (No Pages)",
                generator: createEmptyPDF,
                expectedBehavior: .error(.noTextContent)
            )
        ]
    }
    
    // MARK: - Test Document Generators
    
    private func createNormalResume() -> URL {
        let text = """
        JOHN DOE
        iOS Developer
        
        EXPERIENCE
        Senior iOS Developer at TechCorp (2020-2024)
        - Led development of fintech app with 1M+ users
        - Implemented MVVM architecture and SwiftUI
        - Integrated CoreML for on-device AI features
        - Reduced app crash rate by 40%
        
        iOS Developer at StartupXYZ (2018-2020)
        - Built social media app from scratch
        - Implemented real-time chat using Firebase
        - Published 5 apps to App Store
        
        SKILLS
        Swift, SwiftUI, UIKit, CoreML, Combine, MVVM, TDD, Git
        
        EDUCATION
        B.Tech in Computer Science - XYZ University (2014-2018)
        """
        
        return createTextPDF(text: text, filename: "normal_resume.pdf")
    }
    
    private func createShortDocument() -> URL {
        let text = "This is a very short document with just one paragraph. It should return this exact text as the summary."
        return createTextPDF(text: text, filename: "short_doc.pdf")
    }
    
    private func createLongBook() -> URL {
        var longText = "THE GREAT ADVENTURE\nA Novel\n\n"
        
        // Generate 500 pages worth of content
        for chapter in 1...50 {
            longText += "CHAPTER \(chapter)\n\n"
            for paragraph in 1...10 {
                longText += "This is paragraph \(paragraph) of chapter \(chapter). The story continues with our hero facing new challenges and adventures. The plot thickens as mysteries unfold and characters develop through their experiences. "
            }
            longText += "\n\n"
        }
        
        return createTextPDF(text: longText, filename: "long_book.pdf")
    }
    
    private func createImageOnlyPDF() -> URL {
        let pdfDocument = PDFDocument()
        
        // Create 3 pages with rendered text as images (no extractable text)
        for pageNum in 1...3 {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 612, height: 792))
            let image = renderer.image { context in
                // White background
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 612, height: 792))
                
                // Draw text as image (not selectable)
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .left
                
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14),
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: paragraphStyle
                ]
                
                let text = """
                SCANNED DOCUMENT
                Page \(pageNum)
                
                This is a scanned document with no extractable text.
                The OCR feature should be able to read this.
                
                Test text for optical character recognition.
                """
                
                text.draw(in: CGRect(x: 50, y: 100, width: 500, height: 600), withAttributes: attributes)
            }
            
            if let pdfPage = PDFPage(image: image) {
                pdfDocument.insert(pdfPage, at: pdfDocument.pageCount)
            }
        }
        
        let url = tempURL("image_only.pdf")
        pdfDocument.write(to: url)
        return url
    }
    
    private func createPasswordProtectedPDF() -> URL {
        let text = "This document is password protected. Password: test123"
        let tempPDF = createTextPDF(text: text, filename: "temp_password.pdf")
        
        guard let document = PDFDocument(url: tempPDF) else {
            return tempPDF
        }
        
        let protectedURL = tempURL("password_protected.pdf")
        
        // Write with password protection
        document.write(to: protectedURL, withOptions: [
            .userPasswordOption: "test123",
            .ownerPasswordOption: "test123"
        ])
        
        return protectedURL
    }
    
    private func createCorruptedPDF() -> URL {
        let url = tempURL("corrupted.pdf")
        
        // Write garbage data
        let garbageData = "This is not a valid PDF file at all!".data(using: .utf8)!
        try? garbageData.write(to: url)
        
        return url
    }
    
    private func createEmptyPDF() -> URL {
        let pdfDocument = PDFDocument()
        // Don't add any pages - empty document
        
        let url = tempURL("empty.pdf")
        pdfDocument.write(to: url)
        return url
    }
    
    // MARK: - Helper Methods
    
    private func createTextPDF(text: String, filename: String) -> URL {
        let pdfDocument = PDFDocument()
        
        // Split text into pages (approximately 3000 characters per page)
        let pageTexts = text.chunked(into: 3000)
        
        for pageText in pageTexts {
            if let page = createPDFPage(with: pageText) {
                pdfDocument.insert(page, at: pdfDocument.pageCount)
            }
        }
        
        let url = tempURL(filename)
        pdfDocument.write(to: url)
        return url
    }
    
    private func createPDFPage(with text: String) -> PDFPage? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter size
        
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        let image = renderer.image { context in
            // White background
            UIColor.white.setFill()
            context.fill(pageRect)
            
            // Draw text
            let textRect = CGRect(x: 50, y: 50, width: 512, height: 692)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraphStyle
            ]
            
            text.draw(in: textRect, withAttributes: attributes)
        }
        
        return PDFPage(image: image)
    }
    
    private func tempURL(_ filename: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }
}

// MARK: - Supporting Types

struct TestDocument {
    let name: String
    let generator: () -> URL
    let expectedBehavior: ExpectedBehavior
    
    enum ExpectedBehavior {
        case success(Int) // Expected number of summary points
        case error(DocumentError)
    }
}

// MARK: - String Extension

extension String {
    func chunked(into size: Int) -> [String] {
        var chunks: [String] = []
        var currentIndex = startIndex
        
        while currentIndex < endIndex {
            let chunkEnd = index(currentIndex, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[currentIndex..<chunkEnd]))
            currentIndex = chunkEnd
        }
        
        return chunks
    }
}
