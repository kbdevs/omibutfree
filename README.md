# Omi Local - Setup Guide

A minimal, self-contained app for your Omi device. No accounts, no backend, all data stored locally on your iPhone.

## Prerequisites

### 1. Development Tools

| Tool | Version | Install |
|------|---------|---------|
| **Xcode** | 16.4+ | [Mac App Store](https://apps.apple.com/app/xcode/id497799835) |
| **Flutter** | 3.35+ | [flutter.dev/docs/get-started](https://flutter.dev/docs/get-started/install) |
| **CocoaPods** | 1.16+ | `brew install cocoapods` |

### 2. API Keys

| Service | Purpose | Get From |
|---------|---------|----------|
| **Deepgram** | Speech-to-text | [console.deepgram.com/api-keys](https://console.deepgram.com/api-keys) |
| **OpenAI** | AI chat & summaries | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) |

Both offer free credits for new accounts.

### 3. iPhone Setup

1. Connect iPhone 15 Pro via USB
2. Enable **Developer Mode**: Settings → Privacy & Security → Developer Mode → Enable
3. Trust your Mac when prompted on iPhone

---

## Installation

### Step 1: Navigate to App

```bash
cd /Users/kb/.gemini/antigravity/playground/primordial-filament/omi_local
```

### Step 2: Install Dependencies

```bash
flutter pub get
```

### Step 3: Install iOS Dependencies

```bash
cd ios && pod install && cd ..
```

### Step 4: Open in Xcode (First Time Only)

```bash
open ios/Runner.xcworkspace
```

In Xcode:
1. Select **Runner** in the left sidebar
2. Go to **Signing & Capabilities** tab
3. Select your **Team** (Apple Developer account)
4. Xcode will create a provisioning profile automatically

---

## Running the App

### Development Mode (Connected to Mac)

```bash
flutter run
```

### Release Build (Standalone on iPhone)

```bash
# Build
flutter build ios --release

# Install (requires ios-deploy: brew install ios-deploy)
ios-deploy --bundle build/ios/iphoneos/Runner.app
```

---

## First Launch Setup

1. **Open the app** on your iPhone
2. Go to **Settings** tab (bottom right)
3. Enter your **Deepgram API Key**
4. Enter your **OpenAI API Key**
5. Keys are saved locally - you only do this once

---

## Using the App

## Features

- **Omi BLE Connection**: Connect directly to your Omi device via Bluetooth
- **iPhone Mic Fallback**: Use your phone's microphone when no Omi device is connected
- **Real-time Transcription**: Live speech-to-text via Deepgram with speaker diarization
- **Continuous Recording**: Always-on recording that auto-saves after 2 minutes of silence
- **Local Storage**: All conversations stored on-device using SQLite
- **AI Chat**: Chat with AI that references your conversation history
- **Auto Summarization**: AI-generated titles and summaries for each conversation
- **No Account Required**: No sign-up, no backend servers

### Connect to Omi Device

1. Go to **Device** tab
2. Tap **Scan for Devices**
3. Select your Omi device from the list
4. Wait for connection (green banner appears)

### Record a Conversation

1. Ensure device is connected
2. Tap **Start Recording**
3. Speak - you'll see live transcription
4. Tap **Stop Recording** when done
5. Conversation is auto-summarized and saved

### View History

1. Go to **History** tab
2. Tap any conversation to see full transcript
3. Swipe left to delete

### Chat with AI

1. Go to **Chat** tab
2. Ask questions about your conversations
3. AI has access to your last 5 conversations for context

---

## Troubleshooting

### "Bluetooth permission denied"
- Go to iPhone Settings → Privacy & Security → Bluetooth
- Enable for Omi Local

### "API key invalid" errors
- Double-check your keys in Settings
- Ensure no extra spaces when pasting
- Deepgram: Must be an API key, not project ID
- OpenAI: Must start with `sk-`

### Device not found when scanning
- Ensure Omi is powered on and in range
- Toggle Bluetooth off/on on iPhone
- Try force-closing and reopening the app

### Build fails in Xcode
- Ensure you selected a Team in Signing & Capabilities
- Try: `flutter clean && flutter pub get && cd ios && pod install`

---

## Cost Estimates

| Service | Pricing | Typical Usage |
|---------|---------|---------------|
| **Deepgram Nova-2** | $0.0043/minute | ~$2-5/month |
| **OpenAI GPT-4o-mini** | $0.15/1M tokens | ~$1-3/month |

**Total: ~$3-8/month** for typical personal use.

---

## Files & Data

All data stays on your iPhone:

| Data | Location |
|------|----------|
| Conversations | SQLite database in app sandbox |
| API Keys | iOS Keychain (encrypted) |
| Recordings | Not stored (streamed to Deepgram) |

To reset: Delete the app from iPhone.
