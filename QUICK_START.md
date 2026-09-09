# LANtern - Quick Start Guide

## What You've Received

A complete, production-quality Flutter application with:
- **Full source code** with Clean Architecture
- **State management** using Riverpod
- **Local networking** with UDP discovery and TCP messaging
- **SQLite database** with schema and migrations
- **Android configuration** for API 21-34+
- **Material 3 UI** with light/dark themes
- **Complete documentation** and development guides

## Installation Steps

### 1. Extract the Project

```bash
tar -xzf lantern_complete_project.tar.gz
cd lantern_project
```

### 2. Install Flutter (if not already installed)

```bash
# Download Flutter SDK
git clone https://github.com/flutter/flutter.git -b stable

# Add to PATH (macOS/Linux)
export PATH="$PATH:$(pwd)/flutter/bin"

# Or on Windows, add to System Environment Variables
# C:\path\to\flutter\bin

# Verify installation
flutter doctor
```

### 3. Setup Android Environment

```bash
# Create local.properties with SDK paths
cat > android/local.properties << EOF
flutter.sdk=<path-to-flutter-sdk>
sdk.dir=<path-to-android-sdk>
EOF

# For macOS:
echo "flutter.sdk=$(which flutter | sed 's/\/bin\/flutter$//')" > android/local.properties
echo "sdk.dir=$ANDROID_SDK_ROOT" >> android/local.properties
```

### 4. Get Dependencies

```bash
flutter pub get
```

### 5. Run the App

**On Physical Device:**
```bash
# Connect Android device via USB
flutter devices  # Verify device is listed
flutter run
```

**On Emulator:**
```bash
# Start Android emulator first
flutter run
```

**With Verbose Output:**
```bash
flutter run -v
```

## Project Structure

```
lantern_project/
├── android/                    # Android native code & config
├── ios/                        # iOS native code & config
├── lib/
│   ├── main.dart              # App entry point
│   ├── core/
│   │   ├── database/          # SQLite service
│   │   ├── di/                # Dependency injection
│   │   ├── network/           # Networking services
│   │   └── theme/             # Material 3 theme
│   └── features/
│       ├── app/               # App shell, navigation
│       ├── chat/              # Direct messaging
│       ├── channels/          # Group channels
│       └── profile/           # User profile
├── pubspec.yaml               # Flutter dependencies
├── pubspec.lock               # Locked dependency versions
├── README.md                  # Project overview
├── DEVELOPMENT.md             # Development guide
├── ARCHITECTURE.md            # Architecture documentation
├── analysis_options.yaml      # Dart analysis rules
└── build.sh                   # Build script
```

## First Time Setup Checklist

- [ ] Extracted project files
- [ ] Installed Flutter SDK
- [ ] Configured Android SDK path
- [ ] Ran `flutter pub get`
- [ ] Connected device or started emulator
- [ ] Ran `flutter run` successfully
- [ ] Created profile on first launch
- [ ] Verified peer discovery works

## What to Test First

### 1. Profile Creation
- App launches to profile creation screen
- Can enter username and select avatar
- Profile saves and persists

### 2. Network Discovery
- Navigate to Peers tab
- Verify discovery status shows "Active"
- Launch app on second device on same WiFi

### 3. Peer-to-Peer Messaging (2 Devices Required)
- Run app on Device A and Device B
- Wait for peers to discover each other
- Tap peer on Device A to open chat
- Send text message
- Verify message appears on Device B

### 4. File Sharing
- In chat, use file picker
- Select image or PDF
- Send file
- Verify received on other device

### 5. Channel Creation
- Go to Channels tab
- Create a new channel
- Join with second device
- Send channel message
- Verify appears for all members

## Build for Release

### APK (Android Installation File)

```bash
# Build release APK
flutter build apk --release

# Output location: build/app/outputs/flutter-apk/app-release.apk

# Install on device
adb install build/app/outputs/flutter-apk/app-release.apk
```

### App Bundle (Google Play Store)

```bash
flutter build appbundle --release

# Output: build/app/outputs/bundle/release/app-release.aab
```

## Key Features Overview

### ✅ Profile Management
- First-launch setup with avatar selection
- Device identification and naming
- Persistent local storage

### ✅ Peer Discovery
- Automatic WiFi scanning
- UDP broadcast discovery
- Real-time online/offline status
- < 5 second detection

### ✅ Direct Messaging
- Text message exchange
- File sharing (images, audio, PDFs)
- Message delivery status
- Message timestamps
- Local conversation history

### ✅ Channels
- Create named chat rooms
- Add/remove members
- Channel messages
- Admin controls (mute, remove)
- Persistent member list

### ✅ File Sharing
- Image transfer
- Audio file sharing
- PDF document sharing
- Generic file support
- Transfer progress

### ✅ User Experience
- Material Design 3 UI
- Light/Dark theme support
- Responsive layouts
- Smooth animations
- Network diagnostics

## Android Requirements Met

- ✅ API 21+ support (down to Android 5.0)
- ✅ Target API 34 (Android 14+)
- ✅ Local network permissions
- ✅ WiFi discovery permissions
- ✅ Storage access for files
- ✅ Notification support (Android 13+)

## Networking Details

### Discovery (UDP)
- **Port**: 15554
- **Protocol**: UDP Broadcast
- **Interval**: 5 seconds
- **Timeout**: 30 seconds

### Messaging (TCP)
- **Port**: 15555
- **Protocol**: TCP Sockets
- **Format**: JSON packets
- **Support**: Text, images, files

### Supported Features
- ✅ Direct peer-to-peer messaging
- ✅ Group channel broadcasting
- ✅ File transfer with validation
- ✅ Message delivery tracking
- ✅ Offline mode support

## Troubleshooting

### "No devices found"
```bash
# Check adb connection
adb devices

# Accept device prompt on Android phone
# Try: adb kill-server && adb start-server
```

### "Peer discovery not working"
1. Verify both devices on same WiFi network
2. Check no firewall blocking UDP 15554
3. Check network diagnostics in Settings tab
4. Restart peer discovery: toggle off/on in Settings

### "Messages not delivering"
1. Verify TCP port 15555 is accessible
2. Check device IP addresses match subnet
3. Enable verbose logging: `flutter run -v`
4. Test with shorter messages first

### "Build failing"
```bash
# Clean build artifacts
flutter clean

# Get fresh dependencies
flutter pub get

# Run analysis
flutter analyze

# Try build again
flutter run
```

### "Database errors"
```dart
// In Dart DevTools console, or add to code:
await DatabaseService().deleteDatabase();
// App recreates on next launch
```

## Development Environment

### Recommended IDE Setup

**VS Code**
```bash
code .
# Install extensions:
# - Flutter (Dart)
# - Dart
# - SQLite Viewer
```

**Android Studio**
```bash
# Open project in Android Studio
# SDK Manager automatically detects Android SDK
# Emulator Manager to create virtual device
```

### Useful Commands

```bash
# Run with verbose output
flutter run -v

# Profile mode (optimized but with debugging)
flutter run --profile

# Release mode
flutter run --release

# Run code analysis
flutter analyze

# Run tests
flutter test

# Generate coverage
flutter test --coverage

# Update dependencies
flutter pub upgrade

# Clean build
flutter clean
```

## Next Steps

1. **Understand Architecture**: Read `ARCHITECTURE.md`
2. **Learn Development**: Read `DEVELOPMENT.md`
3. **Explore Code**: Start with `lib/main.dart`
4. **Test Features**: Follow feature test guides
5. **Customize**: Modify theme, add features, etc.
6. **Deploy**: Build release APK for distribution

## Documentation Files

- **README.md** - Project overview and features
- **ARCHITECTURE.md** - System design and layer details
- **DEVELOPMENT.md** - Development guide and debugging

## Support & Next Features

### Future Enhancement Ideas (Hooks Already in Place)

- Voice/video calls via WebRTC
- End-to-end encryption (TLS/Noise)
- Message search and indexing
- User presence indicators
- Typing notifications
- Read receipts
- Message reactions
- User blocking
- Channel pinned messages
- LAN radio broadcasting
- Screen sharing
- Game integration

## System Requirements

### Development
- Flutter 3.0+
- Dart 3.0+
- Android SDK 21+
- Java 11+

### Runtime (Android)
- Android 5.0+ (API 21)
- 50MB storage
- WiFi network access

## Performance Targets

- Peer discovery: < 5 seconds
- Message delivery: < 200ms (LAN)
- File transfer: 10-50 MB/s
- UI: 60 FPS
- Memory: 80-150MB
- Battery: < 5% per hour

## License

LANtern is open source and available under the MIT License.

## Questions?

Refer to the included documentation:
- Architecture questions → `ARCHITECTURE.md`
- Development questions → `DEVELOPMENT.md`
- Feature questions → `README.md`

---

**You're all set!** Extract the archive, follow the installation steps, and you'll have a fully functional local-network communication app running on your device.
