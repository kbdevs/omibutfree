# Omi Local (Omibutfree)

<div align="center">

![Omi Local](assets/icon.png)

**The Open Source, Privacy-First Companion for Omi Devices.**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue.svg)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-iOS-black.svg)]()
[![License](https://img.shields.io/badge/License-MIT-green.svg)]()

[Features](#features) • [Installation](#installation) • [Architecture](#architecture) • [Roadmap](#roadmap)

</div>

---

## 🚀 Overview

**Omi Local** is a fully functioning, self-hosted alternative to the official Omi app. It is designed for users who want full control over their data, zero monthly subscriptions, and a powerful local-first AI experience.

It connects directly to your Omi hardware (Friend/DevKit) via Bluetooth Low Energy (BLE) and processes audio entirely on your terms—whether that's using local Whisper models on your iPhone or your own private API keys for Cloud transcription.

## ✨ Features

### 🔒 Privacy & Sovereignty

- **100% Local Storage**: All memories, tasks, and conversations live in a SQLite database on your device.
- **Your Keys, Your Model**: Bring your own OpenAI/Deepgram keys. No middleman servers.
- **Offline Capable**: Use local Whisper models to transcribe audio without an internet connection.

### 🧠 Advanced AI

- **Memories**: Automatically extracts and индеxexes important facts about your life (e.g., "My dog's name is Rex").
- **Actionable Tasks**: Detects promises and to-dos (e.g., "Remind me to buy milk in 20 mins") and schedules precise local notifications.
- **Hold-to-Ask**: Hold the Omi button to chat with your AI assistant in real-time. It pauses your meeting, answers you, and resumes seamlessly.

### ⚡️ Modern Hardware Integration

- **Direct BLE Connection**: Low-latency audio streaming from Omi devices.
- **Device Management**: View battery life, hardware revision, and manage SD card storage directly from the app.
- **Haptic Feedback**: Rich haptic responses for button presses and AI interactions.

### 🎨 Premium Experience

- **"2025" Design**: A polished, dark-mode-first UI with smooth animations and glassmorphism.
- **Background Audio**: Robust background processing ensures you never miss a moment, even when the phone is locked.

## 🛠 Tech Stack

- **Framework**: Flutter (Dart)
- **Database**: SQLite (Drift)
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
- [ ] **Integrations**: Google Calendar, Notion, Apple Reminders
- [ ] **Voice**: Speaker Diarization (Train to recognize your voice)
- [ ] **Sync**: Robust SD Card file synchronization

## 🤝 Contributing

This project is open source and free forever. We welcome contributions!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

**Built with ❤️ by KB Devs**
