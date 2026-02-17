import SwiftUI

struct DeviceSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var dimRatio: Double = 100
    @State private var micGain: Double = 4
    @State private var batteryLevel: Int?
    @State private var isLoading: Bool = false
    
    var body: some View {
        List {
            Section("Customization") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("LED Dimming")
                        Spacer()
                        Text("\(Int(dimRatio))%")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $dimRatio, in: 0...100, step: 1) {
                        Text("Dimming")
                    } onEditingChanged: { editing in
                        if !editing {
                            Task {
                                await setLedDimRatio()
                            }
                        }
                    }
                }
            }
            
            Section("Device Info") {
                HStack {
                    Text("Battery Level")
                    Spacer()
                    Text("\(batteryLevel ?? 0)%")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Microphone Gain") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Mic Gain")
                        Spacer()
                        Text(gainLabel)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("High - for distant or soft voices")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Slider(value: $micGain, in: 0...8, step: 1) {
                        Text("Mic Gain")
                    } onEditingChanged: { editing in
                        if !editing {
                            Task {
                                await setMicGain()
                            }
                        }
                    }
                    
                    HStack {
                        Text("Mute")
                        Spacer()
                        Text("Max")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        PresetButton(label: "Quiet", level: 2, currentLevel: $micGain)
                        PresetButton(label: "Normal", level: 4, currentLevel: $micGain)
                        PresetButton(label: "High", level: 6, currentLevel: $micGain)
                    }
                    .padding(.top, 8)
                }
            }
            
            Section("Debug") {
                Button {
                    Task {
                        await appState.startAudioTest()
                    }
                } label: {
                    HStack {
                        Text("Test Mic Audio")
                        Spacer()
                        if appState.isTestingAudio {
                            ProgressView()
                        } else {
                            Image(systemName: "mic")
                        }
                    }
                }
                .disabled(appState.isTestingAudio)
            }
            
            Section {
                Button(role: .destructive) {
                    Task {
                        await appState.disconnectDevice()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("Disconnect")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Device Settings")
        .onAppear {
            Task {
                await loadDeviceSettings()
            }
        }
    }
    
    private var gainLabel: String {
        let level = Int(micGain)
        switch level {
        case 0: return "Mute"
        case 1: return "+1dB"
        case 2: return "+2dB"
        case 3: return "+3dB"
        case 4: return "+4dB"
        case 5: return "+5dB"
        case 6: return "+6dB (High)"
        case 7: return "+7dB"
        case 8: return "+8dB (Max)"
        default: return "Level \(level)"
        }
    }
    
    private func loadDeviceSettings() async {
        batteryLevel = appState.batteryLevel
        
        // Load dim ratio from BLE
        // Note: These would need actual BLE reads in a full implementation
    }
    
    private func setLedDimRatio() async {
        // Note: This would need actual BLE writes in a full implementation
    }
    
    private func setMicGain() async {
        // Note: This would need actual BLE writes in a full implementation
    }
}

struct PresetButton: View {
    let label: String
    let level: Double
    @Binding var currentLevel: Double
    
    var body: some View {
        Button {
            currentLevel = level
        } label: {
            Text(label)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(currentLevel == level ? Color.purple.opacity(0.2) : Color(.systemGray6))
                .foregroundColor(currentLevel == level ? .purple : .primary)
                .cornerRadius(8)
        }
    }
}
