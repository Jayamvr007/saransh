//
//  ContentView.swift
//  SmartDocumentAssistant
//
//  Created by Jayam Verma on 01/12/25.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedURL: URL?
    @State private var documents: [Document] = []
    @State private var showingDocumentPicker = false
    @State private var selectedDocument: Document?
    
    // Services
    private let coreMLService = CoreMLService()
    private let docService = DocumentProcessingService()
    
    var body: some View {
        NavigationStack {
            ZStack {
                if documents.isEmpty {
                    EmptyStateView(showingPicker: $showingDocumentPicker)
                } else {
                    DocumentListView(
                        documents: $documents,
                        selectedDocument: $selectedDocument,
                        showingPicker: $showingDocumentPicker
                    )
                }
            }
            .navigationTitle("Saransh")
            .toolbar {
                            #if DEBUG
                            ToolbarItem(placement: .navigationBarLeading) {
                                NavigationLink(destination: TestDocumentsView(
                                    coreMLService: coreMLService,
                                    docService: docService
                                )) {
                                    Label("Test", systemImage: "hammer.fill")
                                        .foregroundColor(.orange)
                                }
                            }
                            #endif
                        }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPickerView(selectedURL: $selectedURL)
            }
            .sheet(item: $selectedDocument) { document in
                NavigationStack {
                    SummaryView(
                        viewModel: SummarizationViewModel(
                            coreMLService: coreMLService,
                            docService: docService
                        ),
                        document: document
                    )
                }
            }
            .onChange(of: selectedURL) { _, newURL in
                if let url = newURL {
                    addDocument(from: url)
                }
            }
        }
    }
    
    private func addDocument(from url: URL) {
        // Copy file to permanent location
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsDirectory.appendingPathComponent(url.lastPathComponent)
        
        // Copy file if it doesn't already exist
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            do {
                try FileManager.default.copyItem(at: url, to: destinationURL)
            } catch {
                print("Failed to copy document: \(error)")
                // Still try to use the original URL
            }
        }
        
        let name = url.lastPathComponent
        let type: DocumentType = url.pathExtension.lowercased() == "pdf" ? .pdf : .audio
        
        let document = Document(
            name: name,
            type: type,
            fileURL: FileManager.default.fileExists(atPath: destinationURL.path) ? destinationURL : url
        )
        
        documents.append(document)
    }
}

// MARK: - Supporting Views

struct EmptyStateView: View {
    @Binding var showingPicker: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("No Documents")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add a PDF to get started with AI-powered summarization and analysis")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: { showingPicker = true }) {
                Label("Add Document", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: 200)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
        }
    }
}

struct DocumentListView: View {
    @Binding var documents: [Document]
    @Binding var selectedDocument: Document?
    @Binding var showingPicker: Bool
    
    var body: some View {
        List {
            ForEach(documents) { document in
                DocumentRow(document: document)
                    .onTapGesture {
                        selectedDocument = document
                    }
            }
            .onDelete(perform: deleteDocuments)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingPicker = true }) {
                    Image(systemName: "plus")
                }
            }
        }
    }
    
    private func deleteDocuments(at offsets: IndexSet) {
        documents.remove(atOffsets: offsets)
    }
}

struct DocumentRow: View {
    let document: Document
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: document.type.icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(document.name)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack {
                    Text(document.type.rawValue.uppercased())
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if document.summary != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}


#if DEBUG
struct TestDocumentsView: View {
    let coreMLService: CoreMLService
    let docService: DocumentProcessingService
    
    @State private var selectedTestDoc: Document?
    
    var body: some View {
        List {
            Section {
                Text("Test different document scenarios")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Edge Cases") {
                ForEach(TestDocumentGenerator.shared.generateAllTestDocuments(), id: \.name) { testDoc in
                    Button {
                        let url = testDoc.generator()
                        let doc = Document(
                            name: testDoc.name,
                            type: .pdf,
                            fileURL: url
                        )
                        selectedTestDoc = doc
                    } label: {
                        HStack {
                            Image(systemName: iconForTest(testDoc))
                                .foregroundColor(colorForTest(testDoc))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(testDoc.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                Text(descriptionForTest(testDoc))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Section("Actions") {
                Button(role: .destructive) {
                    CacheService.shared.clearCache()
                } label: {
                    Label("Clear Cache", systemImage: "trash.fill")
                }
                
                Button {
                    print("Cache size: \(CacheService.shared.getCacheSize())")
                } label: {
                    Label("Print Cache Size", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("Test Suite")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedTestDoc) { document in
            NavigationStack {
                SummaryView(
                    viewModel: SummarizationViewModel(
                        coreMLService: coreMLService,
                        docService: docService
                    ),
                    document: document
                )
            }
        }
    }
    
    private func iconForTest(_ testDoc: TestDocument) -> String {
        switch testDoc.expectedBehavior {
        case .success:
            return "checkmark.circle.fill"
        case .error(.imageOnlyPDF):
            return "photo.on.rectangle"
        case .error(.passwordProtected):
            return "lock.fill"
        case .error(.corrupted):
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.circle.fill"
        }
    }
    
    private func colorForTest(_ testDoc: TestDocument) -> Color {
        switch testDoc.expectedBehavior {
        case .success:
            return .green
        case .error(.imageOnlyPDF):
            return .orange
        case .error:
            return .red
        }
    }
    
    private func descriptionForTest(_ testDoc: TestDocument) -> String {
        switch testDoc.expectedBehavior {
        case .success(let points):
            return "Should generate ~\(points) summary points"
        case .error(let docError):
            return "Should show: \(docError.localizedDescription ?? "error")"
        }
    }
}
#endif


#Preview {
    ContentView()
}
