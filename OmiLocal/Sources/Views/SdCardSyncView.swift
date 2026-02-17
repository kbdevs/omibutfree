import SwiftUI

struct SdCardSyncView: View {
    @EnvironmentObject var appState: AppState
    @State private var files: [Int] = []
    @State private var isLoading: Bool = false
    @State private var isSyncing: Bool = false
    @State private var progress: Double = 0
    @State private var statusMessage: String = ""
    
    var body: some View {
        List {
            Section {
                if files.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "sdcard")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No recordings found on SD card")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    ForEach(files, id: \.self) { fileId in
                        HStack {
                            Image(systemName: "waveform")
                                .foregroundColor(.purple)
                            VStack(alignment: .leading) {
                                Text("Recording \(fileId)")
                                    .fontWeight(.medium)
                                Text("Tap to sync")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if isSyncing && progress < 1.0 {
                                ProgressView(value: progress)
                            } else {
                                Image(systemName: "arrow.right")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            
            if !statusMessage.isEmpty {
                Section {
                    Text(statusMessage)
                        .foregroundColor(.secondary)
                }
            }
            
            Section {
                Button {
                    Task {
                        await syncAllRecordings()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isSyncing {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text(isSyncing ? "Syncing..." : "Sync All")
                        Spacer()
                    }
                }
                .disabled(files.isEmpty || isSyncing)
            }
        }
        .navigationTitle("SD Card Sync")
        .onAppear {
            Task {
                await loadFiles()
            }
        }
    }
    
    private func loadFiles() async {
        isLoading = true
        // In a full implementation, this would query the BLE service for files
        // For now, we'll simulate with empty
        files = []
        isLoading = false
    }
    
    private func syncAllRecordings() async {
        isSyncing = true
        progress = 0
        statusMessage = "Starting sync..."
        
        for (index, fileId) in files.enumerated() {
            statusMessage = "Syncing recording \(fileId)..."
            progress = Double(index) / Double(files.count)
            
            // In a full implementation, this would:
            // 1. Read the audio file from the device
            // 2. Process it with the transcription service
            // 3. Save as a conversation
            
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        progress = 1.0
        statusMessage = "Sync complete!"
        
        await MainActor.run {
            Task {
                await appState.loadData()
            }
        }
        
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        await MainActor.run {
            isSyncing = false
            statusMessage = ""
            files = []
        }
    }
}
