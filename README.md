# Omi Local (Omibutfree)

<div align="center">

![Omi Local](assets/icon.png)

**The Open Source, Privacy-First Companion for Omi Devices.**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue.svg)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-iOS-black.svg)]()
[![License](https://img.shields.io/badge/License-MIT-green.svg)]()
[![Version](https://img.shields.io/badge/Version-2.1.0-purple.svg)]()

[Features](#features) • [Installation](#installation) • [Architecture](#architecture) • [Roadmap](#roadmap)

</div>

---

## 🚀 Overview

**Omi Local** is a fully functioning, self-hosted alternative to the official Omi app. It is designed for users who want full control over their data, zero monthly subscriptions, and a powerful local-first AI experience.

It connects directly to your Omi hardware (Friend/DevKit) via Bluetooth Low Energy (BLE) and processes audio entirely on your terms—whether that's using local Whisper models on your iPhone or your own private API keys for Cloud transcription.

## ✨ Features

### 🔒 Privacy & Sovereignty

- **100% Local Storage**: All memories, tasks, and conversations live in a SQLite database on your device.
- **Your Keys, Your Model**: Bring your own OpenAI/Deepgram keys. No middleman servers. Deepgram gives **$200 free credit** on signup!
- **Offline Capable**: Use local Whisper models to transcribe audio without an internet connection.
- **Export All Data**: Export your entire database as JSON anytime.
- **iCloud Backup**: Optional sync across your devices.
- **Voiceprints (Speaker Recognition)**: while recognition is on, the app keeps up to the last five minutes of audio in memory only (it is not saved) and uses it to compute a voiceprint (a numeric summary of a voice) for each speaker segment that is at least two seconds long and still in that memory. Voiceprints are stored in the app's local database on the device; this feature does not save audio. Voiceprints from a conversation are deleted after 14 days unless you name that speaker; samples of people you name are kept until you delete them (People & Voices > Delete person, or Delete all voice data), except that only the newest 40 samples are kept per named person, so older ones are replaced as new ones are added. Expiry of the 14-day samples runs when a conversation is saved and each time the app is brought to the foreground, as well as at start-up. The app itself does not upload voiceprints, but the database may be included in device backups, and the audio is still sent to Deepgram for transcription as before. Voiceprints count as biometric data in some places, so only record people who are OK with it.

### 🧠 Advanced AI

- **Memories**: Automatically extracts important facts. Edit or add memories manually by selecting text.
- **Actionable Tasks**: Detects promises and to-dos with scheduled local notifications.
- **Hold-to-Ask**: Hold the Omi button to chat with your AI assistant in real-time.
- **Speaker Recognition** (opt-in, Cloud/Deepgram mode): Tap a speaker in a saved conversation to name them; the app learns their voice on-device and recognizes that person in later conversations, including while listening live. Turn it on before you start listening: it can only learn from voice samples captured while it is on, so a conversation recorded with it off cannot be used to name its speakers afterwards. Manage people and delete voice data under Settings > People & Voices. Read the [voiceprint privacy note](#-privacy--sovereignty) before turning it on.

### ⚡️ Modern Hardware Integration

- **Direct BLE Connection**: Low-latency audio streaming from Omi devices.
- **Battery Notifications**: Alerts at 50% and 20% battery levels.
- **Device Management**: View battery life, adjust mic gain, and LED dimming.

### 🎨 Premium Experience

- **Dark Mode UI**: Polished design with smooth animations.
- **Conversation Search**: Find past conversations instantly.
- **Duration Display**: See how long each conversation lasted.
- **Statistics Dashboard**: Track your usage with conversation counts, word totals, and more.
- **Notification Controls**: Toggle every notification type individually.

## 🛠 Tech Stack

- **Framework**: Flutter (Dart)
- **Database**: SQLite (sqflite)
- **Bluetooth**: Flutter Blue Plus
- **Audio Codec**: Opus (Custom decoder)
- **Local AI**: Sherpa-ONNX (Streaming), Whisper (Batch)
- **Cloud AI**: Deepgram (STT), OpenAI (LLM)

## 📦 Installation

### Prerequisites

- macOS with Xcode installed
- iPhone (Developer Mode enabled)
- Omi Device (Friend or DevKit)

### Quick Start

1. **Clone the repo**

   ```bash
   git clone https://github.com/kbdevs/omibutfree.git
   cd omibutfree
   ```

2. **Install Dependencies**

   ```bash
   flutter pub get
   cd ios && pod install && cd ..
   ```

3. **Run on Device**
   Connect your iPhone via USB.

   ```bash
   flutter run --release
   ```

4. **Configure**
   Go to **Settings** in the app to add your OpenAI API Key and choose your transcription model.

## 🗺 Roadmap

- [x] **Core**: BLE Audio, Live Transcription, Database
- [x] **AI**: Memories, Tasks, Local Notifications
- [x] **Hardware**: Battery, Haptics, Device Info
- [x] **v2.1.0**: Edit Memories, Search, Export, Stats, Notification Settings
- [ ] **Integrations**: Google Calendar, Notion, Apple Reminders
- [x] **Voice**: Speaker Diarization (Train to recognize your voice)
- [ ] **Sync**: Robust SD Card file synchronization

## 🤝 Contributing

This project is open source and free forever. We welcome contributions!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 🙏 Credits & Third-Party Models

- **Sherpa-ONNX** (Apache-2.0) runs the speaker-embedding model on-device.
- **Voice model**: a WeSpeaker ResNet34 speaker-embedding model trained on VoxCeleb, in ONNX format, downloaded on first use (~26 MB) from the sherpa-onnx author's Hugging Face repo (`csukuangfj/speaker-embedding-models`), pinned to one commit and checked against a SHA-256 before it is used. I could not find a clear license statement for this exact file. WeSpeaker's [pretrained-model docs](https://github.com/wenet-e2e/wespeaker/blob/master/docs/pretrained.md) say its pretrained models follow the license of their training dataset, and the [VoxCeleb dataset page](https://mm.kaist.ac.kr/datasets/voxceleb/) has that dataset's terms. Read both yourself before using or redistributing the model.

---

**Built with ❤️ by kbdevs**
