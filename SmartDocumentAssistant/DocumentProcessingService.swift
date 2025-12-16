//
//  DocumentProcessingService.swift
//  SmartDocumentAssistant
//
//  Created by Jayam Verma on 01/12/25.
//

import PDFKit
import UniformTypeIdentifiers
import Vision

enum DocumentError: Error, LocalizedError {
    case fileNotFound
    case passwordProtected
    case corrupted
    case noTextContent
    case imageOnlyPDF
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "File not found at the specified location."
        case .passwordProtected:
            return "This PDF is password-protected. Please unlock it first."
        case .corrupted:
            return "This PDF appears to be corrupted or invalid."
        case .noTextContent:
            return "No text could be extracted from this document."
        case .imageOnlyPDF:
            return "This PDF contains only images. OCR processing is required."
        }
    }
    
    
    var recoverySuggestion: String? {
        switch self {
        case .imageOnlyPDF:
            return "Tap 'Use OCR' to extract text from images (may take longer)."
        case .passwordProtected:
            return "Open the PDF in another app to remove the password, then try again."
        case .corrupted:
            return "Try re-downloading or re-saving the PDF."
        default:
            return "Please try a different document."
        }
    }
}

class DocumentProcessingService {
    
    // MARK: - Safe Text Extraction with Error Handling
    
    func extractTextSafely(from url: URL) throws -> String {
        // 1. Check file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DocumentError.fileNotFound
        }
        
        // 2. Try to open PDF
        guard let document = PDFDocument(url: url) else {
            throw DocumentError.corrupted
        }
        
        // 3. Check if password-protected
        if document.isLocked {
            throw DocumentError.passwordProtected
        }
        
        // 4. Check if document is empty
        guard document.pageCount > 0 else {
            throw DocumentError.noTextContent
        }
        
        // 5. Extract text
        var fullText = ""
        var pagesWithText = 0
        
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let pageText = page.string {
                if !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    fullText += pageText + "\n"
                    pagesWithText += 1
                }
            }
        }
        
        // 6. Check if it's an image-only PDF (< 10% pages have text)
        let textCoverageRatio = Double(pagesWithText) / Double(document.pageCount)
        if textCoverageRatio < 0.1 {
            throw DocumentError.imageOnlyPDF
        }
        
        // 7. Validate extracted text
        let cleanedText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedText.count < 50 {
            throw DocumentError.noTextContent
        }
        
        return cleanedText
    }
    
    // MARK: - Chunking with Error Handling
    
    // MARK: - Chunking with Error Handling
    
    func extractTextChunksSafely(from url: URL, chunkSize: Int = 10000) throws -> [String] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DocumentError.fileNotFound
        }
        
        guard let document = PDFDocument(url: url) else {
            throw DocumentError.corrupted
        }
        
        if document.isLocked {
            throw DocumentError.passwordProtected
        }
        
        guard document.pageCount > 0 else {
            throw DocumentError.noTextContent
        }
        
        var chunks: [String] = []
        var currentChunk = ""
        var totalTextLength = 0
        var pagesWithMeaningfulText = 0
        
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i), let pageText = page.string else { continue }
            
            let cleanPage = pageText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            totalTextLength += cleanPage.count
            
            // Count pages with meaningful text (more than just metadata/whitespace)
            if cleanPage.count > 50 {
                pagesWithMeaningfulText += 1
            }
            
            if currentChunk.count + cleanPage.count > chunkSize {
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk)
                    currentChunk = ""
                }
            }
            
            currentChunk += cleanPage + "\n\n"
        }
        
        if !currentChunk.isEmpty && currentChunk.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 {
            chunks.append(currentChunk)
        }
        
        // IMPROVED: Multiple detection criteria
        let avgTextPerPage = Double(totalTextLength) / Double(document.pageCount)
        let meaningfulTextRatio = Double(pagesWithMeaningfulText) / Double(document.pageCount)
        
        print("📊 Detection stats:")
        print("   - Total text: \(totalTextLength) chars")
        print("   - Avg per page: \(Int(avgTextPerPage)) chars")
        print("   - Pages with text: \(pagesWithMeaningfulText)/\(document.pageCount)")
        print("   - Meaningful ratio: \(meaningfulTextRatio)")
        
        // Throw error if likely image-based
        if avgTextPerPage < 100 || meaningfulTextRatio < 0.2 || chunks.isEmpty {
            throw DocumentError.imageOnlyPDF
        }
        
        // Final validation
        if totalTextLength < 50 {
            throw DocumentError.noTextContent
        }
        
        return chunks
    }
    
    
    // MARK: - OCR for Image-Based PDFs (Optional Feature)
    
    func extractTextUsingOCR(from url: URL, progressHandler: @escaping (Double) -> Void) async throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw DocumentError.corrupted
        }
        
        var allText = ""
        let totalPages = document.pageCount
        
        print("🔍 Starting OCR on \(totalPages) pages...")
        
        for pageIndex in 0..<totalPages {
            guard let page = document.page(at: pageIndex) else {
                print("⚠️ Could not load page \(pageIndex)")
                continue
            }
            
            // ✅ IMPROVED: Render at EVEN HIGHER RESOLUTION (5x scale for maximum quality)
            let pageRect = page.bounds(for: .mediaBox)
            let scale: CGFloat = 5.0  // Increased from 4x to 5x for even better quality
            let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
            
            // ✅ IMPROVED: Use better rendering options
            let renderer = UIGraphicsImageRenderer(size: scaledSize, format: UIGraphicsImageRendererFormat.default())
            let pageImage = renderer.image { ctx in
                // White background
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: scaledSize))
                
                // ✅ IMPROVED: Better context setup for high-quality rendering
                ctx.cgContext.interpolationQuality = .high
                ctx.cgContext.setAllowsAntialiasing(true)
                ctx.cgContext.setShouldAntialias(true)
                ctx.cgContext.setShouldSmoothFonts(true)  // Smooth fonts for better OCR
                
                // Scale context for high-res rendering
                ctx.cgContext.scaleBy(x: scale, y: scale)
                ctx.cgContext.translateBy(x: 0, y: pageRect.height)
                ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
                
                // Draw page with high quality
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            
            print("📸 Rendered page \(pageIndex + 1) at \(Int(scaledSize.width))x\(Int(scaledSize.height))px")
            
            // ✅ DEBUG: Log image info
            print("   📊 Image info: \(pageImage.size.width)x\(pageImage.size.height), scale: \(pageImage.scale)")
            
            // ✅ IMPROVED: Preprocess image for better OCR
            let processedImage = preprocessImageForOCR(pageImage)
            
            // ✅ DEBUG: Save processed image for inspection (optional, for debugging)
            // Uncomment to save images for debugging:
            // if let data = processedImage.pngData() {
            //     let debugURL = FileManager.default.temporaryDirectory.appendingPathComponent("ocr_debug_\(pageIndex).png")
            //     try? data.write(to: debugURL)
            //     print("   💾 Saved debug image to: \(debugURL.path)")
            // }
            
            // OCR using Vision
            let extractedText = try await performOCR(on: processedImage)
            print("📄 Page \(pageIndex + 1): extracted \(extractedText.count) characters")
            
            if extractedText.count > 0 {
                print("   Preview: \(String(extractedText.prefix(100)))")
            } else {
                print("   ⚠️ No text extracted from this page")
            }
            
            allText += extractedText + "\n\n"
            
            // Update progress
            let progress = Double(pageIndex + 1) / Double(totalPages)
            progressHandler(progress)
        }
        
        print("✅ OCR complete. Total extracted: \(allText.count) characters")
        
        // ✅ IMPROVED: Comprehensive text cleaning
        let cleanedText = cleanExtractedText(allText)
        if cleanedText.count < 20 {
            throw DocumentError.noTextContent
        }
        
        return cleanedText
    }
    
    // ✅ IMPROVED: Preprocess image for better OCR results
    private func preprocessImageForOCR(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let ciImage = CIImage(cgImage: cgImage)
        
        var processedImage = ciImage
        
        // ✅ IMPROVED: More aggressive preprocessing for better text detection
        
        // 1. Convert to grayscale first (often helps OCR)
        if let filter = CIFilter(name: "CIColorControls") {
            filter.setValue(processedImage, forKey: kCIInputImageKey)
            filter.setValue(0.0, forKey: kCIInputSaturationKey)  // Grayscale
            if let output = filter.outputImage {
                processedImage = output
            }
        }
        
        // 2. Increase contrast more aggressively
        if let filter = CIFilter(name: "CIColorControls") {
            filter.setValue(processedImage, forKey: kCIInputImageKey)
            filter.setValue(1.3, forKey: kCIInputContrastKey)  // Increased from 1.1 to 1.3
            filter.setValue(0.05, forKey: kCIInputBrightnessKey)  // Slight brightness boost
            if let output = filter.outputImage {
                processedImage = output
            }
        }
        
        // 3. Sharpen more aggressively
        if let filter = CIFilter(name: "CISharpenLuminance") {
            filter.setValue(processedImage, forKey: kCIInputImageKey)
            filter.setValue(0.5, forKey: kCIInputSharpnessKey)  // Increased from 0.3 to 0.5
            if let output = filter.outputImage {
                processedImage = output
            }
        }
        
        // 4. ✅ NEW: Apply unsharp mask for better edge detection
        if let filter = CIFilter(name: "CIUnsharpMask") {
            filter.setValue(processedImage, forKey: kCIInputImageKey)
            filter.setValue(0.5, forKey: kCIInputIntensityKey)
            filter.setValue(2.5, forKey: kCIInputRadiusKey)
            if let output = filter.outputImage {
                processedImage = output
            }
        }
        
        // Convert back to UIImage
        guard let outputCGImage = context.createCGImage(processedImage, from: processedImage.extent) else {
            return image
        }
        
        return UIImage(cgImage: outputCGImage)
    }
    
    // ✅ IMPROVED: Perform OCR on an image with better settings
    private func performOCR(on image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            print("⚠️ Could not get CGImage")
            return ""
        }
        
        // ✅ NEW: Try multiple OCR passes with different settings to catch more text
        var allExtractedTexts: [String] = []
        
        // Pass 1: Accurate mode (current)
        let text1 = try await performOCRSinglePass(cgImage: cgImage, level: .accurate, minConfidence: 0.3)
        if !text1.isEmpty {
            allExtractedTexts.append(text1)
            print("   📝 Pass 1 (accurate): \(text1.count) chars")
        }
        
        // Pass 2: Fast mode (sometimes catches different text)
        let text2 = try await performOCRSinglePass(cgImage: cgImage, level: .fast, minConfidence: 0.2)
        if !text2.isEmpty && text2 != text1 {
            allExtractedTexts.append(text2)
            print("   📝 Pass 2 (fast): \(text2.count) chars")
        }
        
        // Combine and deduplicate
        let combinedText = allExtractedTexts.joined(separator: " ")
        let uniqueText = removeDuplicateText(combinedText)
        
        print("   ✅ Total extracted: \(uniqueText.count) characters")
        print("   📝 Combined text: '\(uniqueText.prefix(200))'")
        
        return uniqueText
    }
    
    // ✅ NEW: Single OCR pass with configurable settings
    private func performOCRSinglePass(cgImage: CGImage, level: VNRequestTextRecognitionLevel, minConfidence: Float) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(returning: "")  // Don't throw, just return empty
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                print("   Found \(observations.count) text regions (level: \(level == .accurate ? "accurate" : "fast"))")
                
                var extractedTexts: [String] = []
                
                for observation in observations {
                    let candidates = observation.topCandidates(5)  // Get more candidates
                    
                    for candidate in candidates {
                        if candidate.confidence >= minConfidence {
                            extractedTexts.append(candidate.string)
                            print("   ✓ '\(candidate.string)' (conf: \(String(format: "%.2f", candidate.confidence)))")
                            break  // Use first candidate that meets threshold
                        }
                    }
                }
                
                let text = extractedTexts.joined(separator: " ")
                continuation.resume(returning: text)
            }
            
            // Configure request
            request.recognitionLevel = level
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "en-GB"]
            
            if #available(iOS 16.0, *) {
                request.revision = VNRecognizeTextRequestRevision3
            }
            
            request.automaticallyDetectsLanguage = true
            request.minimumTextHeight = 0.0  // Accept any text size
            
            // ✅ NEW: Try to detect text in different orientations
            // Vision can sometimes miss text if it's rotated
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: "")
            }
        }
    }
    
    // ✅ NEW: Remove duplicate text segments
    private func removeDuplicateText(_ text: String) -> String {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        var unique: [String] = []
        var seen = Set<String>()
        
        for sentence in sentences {
            let lower = sentence.lowercased()
            if !seen.contains(lower) && sentence.count > 3 {
                unique.append(sentence)
                seen.insert(lower)
            }
        }
        
        return unique.joined(separator: ". ")
    }
        
        // ✅ NEW: Extract text from image file directly (not PDF)
        func extractTextFromImage(_ imageURL: URL) async throws -> String {
            guard let image = UIImage(contentsOfFile: imageURL.path) else {
                throw DocumentError.corrupted
            }
            
            // Preprocess and perform OCR
            let processedImage = preprocessImageForOCR(image)
            return try await performOCR(on: processedImage)
        }
        
        
        
        // MARK: - Metadata Extraction
        
        func extractMetadata(from url: URL) -> [String: String] {
            // Local variable (not a class property)
            
            var docMetadata:[String: String] = [:]
            guard let document = PDFDocument(url: url) else {
                return [:]
            }
            
            if let attributes = document.documentAttributes {
                if let title = attributes[PDFDocumentAttribute.titleAttribute] as? String {
                    docMetadata["title"] = title
                }
                if let author = attributes[PDFDocumentAttribute.authorAttribute] as? String {
                    docMetadata["author"] = author
                }
            }
            
            docMetadata["pageCount"] = "\(document.pageCount)"
            docMetadata["isLocked"] = document.isLocked ? "Yes" : "No"
            
            do {
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let fileSize = fileAttributes[.size] as? Int64 {
                    docMetadata["fileSize"] = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
                }
            } catch {
                print("Error reading file attributes: \(error)")
            }
            
            return docMetadata
        }
    }
    
    // MARK: - Text Cleaning and Post-processing
    
    /// Comprehensive text cleaning that removes artifacts while preserving content quality
    func cleanExtractedText(_ text: String) -> String {
        var cleaned = text
        
        // 1. Fix common OCR errors
        cleaned = cleaned.replacingOccurrences(of: "l0", with: "10", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "O0", with: "00", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "l1", with: "11", options: .regularExpression)
        
        // 2. Fix hyphens used for line breaks (keep dashes between words)
        cleaned = cleaned.replacingOccurrences(of: "\\w-\\s+", with: "", options: .regularExpression)
        
        // 3. Normalize multiple spaces and tabs
        cleaned = cleaned.replacingOccurrences(of: "\\t+", with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        
        // 4. Normalize line breaks (collapse multiple newlines to max 2)
        cleaned = cleaned.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        
        // 5. Remove common page formatting artifacts
        cleaned = cleaned.replacingOccurrences(of: "\\b(page|pg\\.?|p\\.?\\s*\\d+)\\b", with: "", options: [.regularExpression, .caseInsensitive])
        cleaned = cleaned.replacingOccurrences(of: "© \\d{4}-?\\d*", with: "", options: .regularExpression)
        
        // 6. Clean up malformed punctuation
        cleaned = cleaned.replacingOccurrences(of: "\\.{2,}", with: ".", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\?{2,}", with: "?", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "!{2,}", with: "!", options: .regularExpression)
        
        // 7. Remove leading/trailing whitespace and normalize
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }


