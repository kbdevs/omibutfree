# Omibutfree (Omi Local)

A free, self-hosted, privacy-focused alternative for your Omi device. No accounts, no monthly subscriptions, no data leaving your device without your permission.

<div align="center">
  <img src="assets/icon.png" width="120" height="120" alt="Omi Local Icon" />
</div>

## Features

- **100% Local & Private**: All conversations and data are stored locally on your iPhone using SQLite.
- **No Accounts Required**: Use the app immediately without signing up for anything.
- **Direct Omi Connection**: Connects directly to Omi devices (Friend) via Bluetooth Low Energy (BLE).
- **Premium UI**: Modern "2025 VC" aesthetic with dark mode and smooth animations.
- **Flexible Transcription**:
  - **Cloud**: Deepgram Nova-2 (Highest quality)
  - **Local**: On-device Whisper (Free, offline) or Sherpa-ONNX (Real-time)
- **AI Memory**: Chat with your past conversations using OpenAI (GPT-4o-mini or other models).
- **Background Recording**: Continues recording even when the phone is locked.

## Setup Guide

### Prerequisites
- **Mac** with Xcode installed
- **iPhone** (Developer Mode enabled)
- **Flutter SDK** installed

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/kbdevs/omibutfree.git
   cd omibutfree
   ```

2. **Install Dependencies**
   ```bash
   flutter pub get
   cd ios && pod install && cd ..
   ```

3. **Configure API Keys (Optional)**
   The app works with local transcription out of the box. For cloud features, you'll need:
   - **Deepgram API Key** (for cloud transcription)
   - **OpenAI API Key** (for AI chat)
   
   Enter these in the app's **Settings** page.

4. **Run on iPhone**
   Connect your iPhone and run:
   ```bash
   flutter run --release
   ```

## Privacy

- **Audio**: Streamed directly from Omi to your phone. If using Deepgram, audio is sent briefly for transcription and not stored. If using Whisper, audio never leaves your device.
- **Transcripts**: Stored in a local SQLite database in the app's sandbox.
- **Keys**: API keys are stored securely in the iOS Keychain.

## Contributing

Open source and free forever. PRs welcome!
