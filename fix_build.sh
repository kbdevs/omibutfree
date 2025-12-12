#!/bin/bash
set -e

echo "🔍 Locating Flutter..."
FLUTTER_BIN=$(which flutter)
if [ -z "$FLUTTER_BIN" ]; then
  echo "❌ Flutter not found! Please run this script in a terminal where 'flutter' is in your PATH."
  exit 1
fi

FLUTTER_SDK_PATH=$(dirname $(dirname "$FLUTTER_BIN"))
echo "✅ Flutter SDK found at: $FLUTTER_SDK_PATH"

echo "🔐 This script needs sudo access ONLY to clean the Flutter SDK attributes."
echo "   Please enter your password if requested."
sudo -v # Refresh sudo credentials to ensure we can run the next command

echo "🧹 Step 1: Cleaning Flutter SDK attributes..."
sudo xattr -rc "$FLUTTER_SDK_PATH"

echo "🧹 Step 2: Cleaning Project attributes..."
xattr -rc .

echo "🗑️ Step 3: Deep Clean..."
flutter clean
rm -rf ios/Pods ios/Podfile.lock ios/.symlinks ios/Flutter/Flutter.framework ios/Flutter/App.framework

echo "⬇️ Step 4: Fetching dependencies..."
flutter pub get

echo "📦 Step 5: Installing Pods..."
cd ios
pod install
cd ..

echo "✨ Step 6: Final Attribute Sweep..."
xattr -rc .

echo "🚀 Step 7: Launching Release Build..."
flutter run --release
