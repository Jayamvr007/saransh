//
//  SummarizationViewModel.swift
//  SmartDocumentAssistant
//

import Foundation

@MainActor
class SummarizationViewModel: ObservableObject {
    @Published var document: Document?
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var recoverySuggestion: String?
    
    @Published var processingProgress: Double = 0.0
    @Published var progressMessage: String = ""
    
    var summary: Box<[String]> = Box([])
    var keyPoints: Box<[String]> = Box([])
    var classification: Box<String?> = Box(nil)
    
    @Published var needsOCR: Bool = false
    @Published var isPerformingOCR: Bool = false
    
    private let coreMLService: CoreMLService
    private let docService: DocumentProcessingService
    private var cancellationToken: Task<Void, Never>?
    
    // REMOVED: private var summaryCache: [String: [String]] = [:]
    // NOW USING: CacheService.shared
    
    init(coreMLService: CoreMLService, docService: DocumentProcessingService) {
        self.coreMLService = coreMLService
        self.docService = docService
    }
    
    func processDocument(_ doc: Document, useOCR: Bool = false) async {
        let cacheKey = doc.name
        if !useOCR {
            if let cached = CacheService.shared.getCachedSummary(for: cacheKey) {
                print("✅ CACHE HIT: \(cacheKey)")
                await MainActor.run {
                    self.summary.value = cached
                    self.isProcessing = false
                    self.processingProgress = 1.0
                    self.progressMessage = "Loaded from cache"
                }
                if let firstChunk = cached.first {
                    let keywords = self.coreMLService.extractKeyPoints(firstChunk, count: 5)
                    await MainActor.run {
                        self.keyPoints.value = keywords
                    }
                }
                return
            } else {
                print("❌ CACHE MISS: \(cacheKey) - will process")
            }
        }
        
        isProcessing = true
        errorMessage = nil
        recoverySuggestion = nil
        needsOCR = false
        processingProgress = 0.0
        
        cancellationToken = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            do {
                await self.updateProgress(0.1, "Extracting text from PDF...")
                
                var chunks: [String] = []
                
                if useOCR {
                    print("🔍 Starting OCR extraction...")
                    await MainActor.run { self.isPerformingOCR = true }
                    
                    let fullText = try await self.docService.extractTextUsingOCR(from: doc.fileURL) { progress in
                        Task { @MainActor in
                            self.processingProgress = 0.1 + (progress * 0.4)
                            self.progressMessage = "Performing OCR... \(Int(progress * 100))%"
                        }
                    }
                    
                    print("✅ OCR completed. Extracted text length: \(fullText.count) characters")
                    print("📄 First 200 chars: \(String(fullText.prefix(200)))")
                    
                    await MainActor.run { self.isPerformingOCR = false }
                    
                    // ✅ IMPROVED: More lenient validation for OCR
                    let cleanedText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Lower threshold from 100 to 30 characters
                    if cleanedText.count < 30 {
                        print("❌ OCR extracted too little text: \(cleanedText.count) chars")
                        print("📄 Extracted text preview: '\(String(cleanedText.prefix(200)))'")
                        
                        await MainActor.run {
                            if cleanedText.isEmpty {
                                self.errorMessage = "OCR could not detect any text in this document."
                                self.recoverySuggestion = "The image may be too blurry, rotated, or contain no readable text. Try:\n• Using a higher quality image\n• Ensuring text is clearly visible\n• Rotating the image if it's sideways"
                            } else {
                                self.errorMessage = "OCR could not extract enough readable text from this document."
                                self.recoverySuggestion = "Only \(cleanedText.count) characters were found. The document may be:\n• Too low quality or blurry\n• Rotated or skewed\n• In an unsupported language\n• Contains mostly images/graphics with little text"
                            }
                            self.isProcessing = false
                            self.needsOCR = false // Don't show OCR button again
                        }
                        return
                    }
                    
                    chunks = await self.splitTextIntoChunks(cleanedText)
                    print("✅ Split into \(chunks.count) chunks")
                    
                } else {
                    chunks = try self.docService.extractTextChunksSafely(from: doc.fileURL)
                }
                
                // Validation for empty chunks (only if NOT using OCR, since we validated above)
                if !useOCR {
                    guard !chunks.isEmpty else {
                        await MainActor.run {
                            self.needsOCR = true
                            self.errorMessage = "This PDF contains only images or no readable text."
                            self.recoverySuggestion = "Tap 'Use OCR' to extract text (may take 1-2 minutes)."
                            self.isProcessing = false
                        }
                        return
                    }
                    
                    let totalLength = chunks.reduce(0) { $0 + $1.count }
                    
                    guard totalLength > 50 else {
                        await MainActor.run {
                            self.needsOCR = true
                            self.errorMessage = "Document appears to be empty or scanned."
                            self.recoverySuggestion = "Tap 'Use OCR' to extract text from images."
                            self.isProcessing = false
                        }
                        return
                    }
                }
                
                if Task.isCancelled { return }
                
                await self.updateProgress(0.5, "Analyzing document structure...")
                
                let totalLength = chunks.reduce(0) { $0 + $1.count }
                let estimatedPages = max(1, totalLength / 2000)
                
                print("📊 Processing \(estimatedPages) pages worth of content")
                
                if estimatedPages == 1 && totalLength < 500 {
                    let singleParagraph = chunks.joined(separator: " ")
                    await MainActor.run {
                        self.summary.value = [singleParagraph]
                        self.keyPoints.value = self.coreMLService.extractKeyPoints(singleParagraph, count: 3)
                        self.isProcessing = false
                        self.processingProgress = 1.0
                    }
                    return
                }
                
                let targetSummaryLength = await self.calculateAdaptiveSummaryLength(pages: estimatedPages)
                
                var summaryPoints: [String] = []
                var allKeyPoints: [String] = []
                
                if totalLength < 15000 {
                    await self.updateProgress(0.7, "Generating summary...")
                    let fullText = chunks.joined(separator: "\n")
                    summaryPoints = self.coreMLService.summarizeTextAsPoints(fullText, sentenceCount: min(targetSummaryLength, 5))
                    allKeyPoints = self.coreMLService.extractKeyPoints(fullText, count: 5)
                } else {
                    await self.updateProgress(0.6, "Processing chapters...")
                    let sentencesPerChunk = max(2, min(5, targetSummaryLength / chunks.count))
                    var chunkSummaries: [(chunkIndex: Int, points: [String])] = []
                    
                    for (index, chunk) in chunks.enumerated() {
                        if Task.isCancelled { return }
                        let progress = 0.6 + (Double(index) / Double(chunks.count)) * 0.3
                        await self.updateProgress(progress, "Processing chunk \(index + 1)/\(chunks.count)...")
                        let points = self.coreMLService.summarizeTextAsPoints(chunk, sentenceCount: sentencesPerChunk)
                        if !points.isEmpty {
                            chunkSummaries.append((index, points))
                        }
                    }
                    
                    await self.updateProgress(0.95, "Finalizing summary...")
                    let strataCount = min(10, max(5, estimatedPages / 50))
                    summaryPoints = await self.createStratifiedSummaryPoints(
                        from: chunkSummaries,
                        totalChunks: chunks.count,
                        strataCount: strataCount,
                        finalPointCount: targetSummaryLength
                    )
                    
                    var accumulatedKeywords: [String] = []
                    for i in stride(from: 0, to: chunks.count, by: max(1, chunks.count / 10)) {
                        let points = self.coreMLService.extractKeyPoints(chunks[i], count: 3)
                        accumulatedKeywords.append(contentsOf: points)
                    }
                    allKeyPoints = self.coreMLService.extractKeyPoints(accumulatedKeywords.joined(separator: " "), count: 8)
                }
                
                print("✅ Summary generated: \(summaryPoints.count) points")
                
                // Cache OCR results too
                CacheService.shared.cacheSummary(summaryPoints, for: cacheKey)
                
                await MainActor.run {
                    self.summary.value = summaryPoints
                    self.keyPoints.value = allKeyPoints
                    self.isProcessing = false
                    self.processingProgress = 1.0
                    self.progressMessage = "Complete!"
                }
                
            } catch DocumentError.imageOnlyPDF {
                await MainActor.run {
                    self.needsOCR = true
                    self.errorMessage = "This PDF contains only images."
                    self.recoverySuggestion = "Tap 'Use OCR' to extract text (may take 1-2 minutes)."
                    self.isProcessing = false
                }
            } catch let error as DocumentError {
                await self.updateError(error.localizedDescription ?? "Unknown error", suggestion: error.recoverySuggestion)
            } catch {
                print("❌ Unexpected error: \(error)")
                await self.updateError("Failed to process document: \(error.localizedDescription)", suggestion: "Please try again or use a different document.")
            }
        }
        
        await cancellationToken?.value
    }

    
    // ... (rest of the methods remain the same)
    
    func cancelProcessing() {
        cancellationToken?.cancel()
        isProcessing = false
        progressMessage = "Cancelled"
    }
    
    private func splitTextIntoChunks(_ text: String, chunkSize: Int = 8000) -> [String] {
        var chunks: [String] = []
        var current = ""
        for char in text {
            current.append(char)
            if current.count >= chunkSize {
                chunks.append(current)
                current = ""
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
    
    @MainActor
    private func updateProgress(_ progress: Double, _ message: String) {
        self.processingProgress = progress
        self.progressMessage = message
    }
    
    @MainActor
    private func updateError(_ msg: String, suggestion: String?) {
        self.errorMessage = msg
        self.recoverySuggestion = suggestion
        self.isProcessing = false
    }
    
    private func calculateAdaptiveSummaryLength(pages: Int) -> Int {
        switch pages {
        case 0...10: return 5
        case 11...50: return 10
        case 51...100: return 15
        case 101...200: return 25
        case 201...400: return 35
        default: return 50
        }
    }
    
    private func createStratifiedSummaryPoints(
        from chunkSummaries: [(chunkIndex: Int, points: [String])],
        totalChunks: Int,
        strataCount: Int,
        finalPointCount: Int
    ) -> [String] {
        let chunkPerStrata = max(1, totalChunks / strataCount)
        var selectedPoints: [String] = []
        
        for stratum in 0..<strataCount {
            let startChunk = stratum * chunkPerStrata
            let endChunk = min((stratum + 1) * chunkPerStrata, totalChunks)
            let summariesInStratum = chunkSummaries.filter {
                $0.chunkIndex >= startChunk && $0.chunkIndex < endChunk
            }
            if let representative = summariesInStratum.first {
                selectedPoints.append(contentsOf: representative.points)
            }
        }
        
        if selectedPoints.count > finalPointCount {
            let combinedText = selectedPoints.joined(separator: " ")
            return coreMLService.summarizeTextAsPoints(combinedText, sentenceCount: finalPointCount)
        }
        
        return selectedPoints
    }
}
