//
//  SummaryView.swift
//  SmartDocumentAssistant
//
//  Created by Jayam Verma on 01/12/25.
//

import SwiftUI

struct SummaryView: View {
    @StateObject var viewModel: SummarizationViewModel
    let document: Document
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.isProcessing {
                    ProcessingView(
                        progress: viewModel.processingProgress,
                        message: viewModel.progressMessage,
                        isOCR: viewModel.isPerformingOCR,
                        onCancel: {
                            viewModel.cancelProcessing()
                        }
                    )
                } else if let error = viewModel.errorMessage {
                    ErrorView(
                        message: error,
                        suggestion: viewModel.recoverySuggestion,
                        needsOCR: viewModel.needsOCR,
                        onRetryWithOCR: {
                            Task {
                                await viewModel.processDocument(document, useOCR: true)
                            }
                        }
                    )
                } else {
                    DocumentInfoCard(document: document)
                    
                    if !viewModel.summary.value.isEmpty {
                        SummarySectionBullets(points: viewModel.summary.value)
                        
                        // Share button
                        ShareButton(points: viewModel.summary.value, documentName: document.name)
                    }
                    
                    if !viewModel.keyPoints.value.isEmpty {
                        KeyPointsSection(points: viewModel.keyPoints.value)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(document.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.processDocument(document)
        }
    }
}

// MARK: - Processing View with Progress

struct ProcessingView: View {
    let progress: Double
    let message: String
    let isOCR: Bool
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            if isOCR {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                Text("Performing OCR")
                    .font(.headline)
                Text("Extracting text from images...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
            }
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .padding(.horizontal, 40)
            
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button(action: onCancel) {
                Text("Cancel")
                    .foregroundColor(.red)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Enhanced Error View

struct ErrorView: View {
    let message: String
    let suggestion: String?
    let needsOCR: Bool
    let onRetryWithOCR: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: needsOCR ? "doc.text.image" : "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(needsOCR ? .orange : .red)
            
            Text(needsOCR ? "OCR Required" : "Error")
                .font(.headline)
            
            Text(message)
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if let suggestion = suggestion {
                Text(suggestion)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            if needsOCR {
                Button(action: onRetryWithOCR) {
                    HStack {
                        Image(systemName: "text.viewfinder")
                        Text("Use OCR")
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(10)
                }
                .padding(.horizontal, 40)
                .padding(.top, 10)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Share Button

struct ShareButton: View {
    let points: [String]
    let documentName: String
    
    var body: some View {
        ShareLink(item: generateShareText()) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text("Share Summary")
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .cornerRadius(10)
        }
    }
    
    private func generateShareText() -> String {
        var text = "Summary of \(documentName)\n\n"
        for (index, point) in points.enumerated() {
            text += "\(index + 1). \(point)\n\n"
        }
        return text
    }
}

// MARK: - Summary Section (Unchanged)

struct SummarySectionBullets: View {
    let points: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "text.alignleft")
                    .foregroundColor(.blue)
                Text("Summary")
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                        
                        Text(point)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Keep other helper views (KeyPointsSection, DocumentInfoCard)

struct KeyPointsSection: View {
    let points: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet")
                    .foregroundColor(.green)
                Text("Key Points")
                    .font(.headline)
            }
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(point)
                        .font(.body)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct DocumentInfoCard: View {
    let document: Document
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: document.type.icon)
                .font(.largeTitle)
                .foregroundColor(.blue)
                .frame(width: 50, height: 50)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(document.name)
                    .font(.headline)
                Text(document.type.rawValue.uppercased())
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(document.createdAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
