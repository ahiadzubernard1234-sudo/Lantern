#!/bin/bash

# LANtern Build Script
# Builds the Flutter app for Android release

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🚀 LANtern Build Script"
echo "======================="
echo ""

# Check Flutter
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter SDK not found. Please install Flutter."
    exit 1
fi

echo "✓ Flutter SDK found: $(flutter --version)"
echo ""

# Get dependencies
echo "📦 Installing dependencies..."
flutter pub get
echo "✓ Dependencies installed"
echo ""

# Run analysis
echo "🔍 Running code analysis..."
flutter analyze
echo "✓ Code analysis passed"
echo ""

# Build APK
echo "🔨 Building release APK..."
flutter build apk --release

echo ""
echo "✅ Build complete!"
echo ""
echo "Output: build/app/outputs/flutter-apk/app-release.apk"
echo ""
echo "To install:"
echo "  adb install build/app/outputs/flutter-apk/app-release.apk"
echo ""
echo "To build App Bundle for Play Store:"
echo "  flutter build appbundle --release"
