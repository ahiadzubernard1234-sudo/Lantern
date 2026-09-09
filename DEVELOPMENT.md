# LANtern Development Guide

## Quick Start

### 1. Setup Development Environment

```bash
# Install Flutter (if not already installed)
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$PATH:/path/to/flutter/bin"

# Verify installation
flutter doctor
```

### 2. Clone and Setup Project

```bash
cd lantern
flutter pub get
```

### 3. Android Setup

```bash
# Create local.properties with Android SDK path
echo "flutter.sdk=$(which flutter | sed 's/\/bin\/flutter$//')" > android/local.properties
echo "sdk.dir=$ANDROID_SDK_ROOT" >> android/local.properties
```

### 4. Run on Device/Emulator

```bash
# List connected devices
flutter devices

# Run on default device
flutter run

# Run with verbose logging
flutter run -v

# Run with performance monitoring
flutter run --profile
```

## Development Workflow

### Testing Features Locally

#### Test Peer Discovery
1. Run app on two devices on same WiFi
2. Enable discovery in Settings tab
3. Verify peers appear in Peers tab within 5 seconds

#### Test Direct Messaging
1. Create profiles on two devices
2. Open peer conversation
3. Send text and file messages
4. Verify delivery status updates

#### Test Channels
1. Create channel on Device A
2. Join channel on Device B
3. Send message from Device A
4. Verify message appears on Device B

#### Test File Sharing
1. Pick image from Device A
2. Send to Device B
3. Verify file appears in conversation
4. Repeat for PDF, audio files

### Performance Testing

```bash
# Profile mode (optimized but with profiling)
flutter run --profile

# Check memory usage
flutter run --release

# Timeline profiling
flutter run --trace-startup
```

### Running Tests

```bash
# Run all unit and widget tests
flutter test

# Run specific test file
flutter test test/features/profile/profile_test.dart

# Generate coverage report
flutter test --coverage
```

## Project Structure Deep Dive

### lib/core/ - Core Services

**database/**
- `database_service.dart`: SQLite initialization and management
- Schema creation and migrations
- Database initialization on app startup

**network/**
- `network_service.dart`: Low-level TCP/UDP operations
- Socket management and connection pooling
- Message sending/receiving primitives

- `peer_discovery_service.dart`: High-level peer discovery
- UDP broadcast discovery protocol
- Peer timeout and status management

**di/**
- `service_locator.dart`: Dependency injection setup
- Service initialization order
- Repository and datasource wiring

**theme/**
- `app_theme.dart`: Material 3 color schemes
- Light and dark theme definitions
- Typography and component styling

### lib/features/ - Feature Modules

Each feature follows Clean Architecture with three layers:

**domain/**
- Entities: Pure business logic models (no dependencies)
- Repositories: Abstract interface definitions
- Usecases: Business logic operations

**data/**
- Datasources: Local/remote data access implementations
- Repositories: Concrete implementations of domain repositories
- Models: Data transfer objects (extend entities)

**presentation/**
- Pages: Full-screen widgets
- Widgets: Reusable UI components
- Providers: Riverpod state management
- Bloc/Cubit: For complex state management

### Feature: Profile

Manages user identity and device information.

- Profile creation (first launch)
- Profile updates
- Device identification
- Avatar selection

### Feature: Chat

Direct peer-to-peer messaging.

- Send/receive messages
- File transfer
- Message history
- Delivery status tracking
- Conversation management

### Feature: Channels

Group communication and moderation.

- Create/delete channels
- Join/leave channels
- Channel membership management
- Broadcast messaging
- Admin controls (mute, remove users)

## State Management with Riverpod

### Providers Pattern

```dart
// Simple value provider
final counterProvider = StateProvider<int>((ref) => 0);

// Async data provider
final profileProvider = FutureProvider<Profile?>((ref) async {
  return ref.watch(profileRepositoryProvider).getProfile();
});

// State notifier for complex state
final profileNotifier = StateNotifierProvider<ProfileNotifier, AsyncValue<Profile?>>((ref) {
  final repo = ref.watch(profileRepositoryProvider);
  return ProfileNotifier(repo);
});
```

### Using Providers in Widgets

```dart
class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch provider - rebuilds when value changes
    final data = ref.watch(profileProvider);

    // Read provider - get value once
    final repository = ref.read(profileRepositoryProvider);

    // Update state notifier
    ref.read(profileNotifier.notifier).updateProfile(...);

    return data.when(
      data: (profile) => Text(profile?.username ?? 'No profile'),
      loading: () => CircularProgressIndicator(),
      error: (error, stack) => Text('Error: $error'),
    );
  }
}
```

## Networking Details

### UDP Broadcast Discovery (Port 15554)

Packet format (JSON):
```json
{
  "type": "discovery",
  "username": "john_doe",
  "ipAddress": "192.168.1.100",
  "port": 15555,
  "deviceId": "device_id_123",
  "deviceName": "My Phone",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

### TCP Message Protocol (Port 15555)

Text message:
```json
{
  "type": "message",
  "id": "msg_id_123",
  "senderId": "user_id_123",
  "receiverId": "user_id_456",
  "content": "Hello!",
  "messageType": "text",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

File transfer:
```json
{
  "type": "file",
  "id": "msg_id_124",
  "senderId": "user_id_123",
  "receiverId": "user_id_456",
  "fileName": "photo.jpg",
  "fileSize": 2097152,
  "fileBytes": "base64_encoded_data...",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

Channel message:
```json
{
  "type": "channel_message",
  "channelId": "channel_id_123",
  "senderId": "user_id_123",
  "content": "Channel announcement",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

## Extending the App

### Adding a New Feature

1. Create feature folder: `lib/features/myfeature/`
2. Create domain layer: `domain/entities/` and `domain/repositories/`
3. Create data layer: `data/datasources/` and `data/repositories/`
4. Create presentation layer: `presentation/providers/` and `presentation/pages/`
5. Wire up in service locator

### Adding Network Packet Type

1. Define packet structure (JSON format)
2. Add handling in `PeerDiscoveryService` or create new service
3. Parse in appropriate listener
4. Update database schema if needed
5. Create UI for new feature

### Adding Database Table

1. Create schema in `DatabaseService._createTables()`
2. Create datasource for CRUD operations
3. Create entity and model classes
4. Implement repository
5. Create Riverpod provider

## Debugging

### Enable Verbose Logging

```bash
flutter run -v
```

### Android Logcat

```bash
# View all logs
adb logcat

# Filter Flutter logs
adb logcat | grep "flutter"

# Filter specific app
adb logcat --pid=$(adb shell pidof com.lantern.app)
```

### Dart DevTools

```bash
# Start DevTools
flutter pub global activate devtools
devtools

# Run app with DevTools
flutter run --observatory-port=50300
```

### Network Inspection

```dart
// In main.dart or any file
import 'dart:developer' as developer;

// Debug print
developer.log('Debug message: $value');
```

## Common Issues and Solutions

### Issue: Peers Not Discovered
**Solution**:
1. Verify WiFi connectivity: Settings > Network Diagnostics
2. Check firewall rules for UDP 15554
3. Restart peer discovery service
4. Check device IP addresses are on same subnet

### Issue: Messages Not Delivering
**Solution**:
1. Verify TCP port 15555 is accessible
2. Check network connectivity
3. Enable verbose logging to see network errors
4. Test with shorter messages first

### Issue: Database Locked
**Solution**:
```dart
// In debug console
await DatabaseService().deleteDatabase();
// App will recreate on next launch
```

### Issue: Memory Leak
**Solution**:
1. Check all StreamSubscriptions are disposed
2. Verify Timer objects are cancelled
3. Remove listeners in dispose()
4. Use profile mode: `flutter run --profile`

## Best Practices

1. **Error Handling**: Always wrap async operations in try-catch
2. **Resource Cleanup**: Cancel streams, timers, and network connections
3. **UI Updates**: Use Riverpod for reactive state management
4. **Logging**: Use Logger package for structured logging
5. **Testing**: Write unit tests for repositories and usecases
6. **Performance**: Profile regularly, optimize hot paths
7. **Security**: Implement TLS for production network traffic
8. **Documentation**: Keep code comments current, explain "why" not "what"

## Release Checklist

- [ ] Run full test suite
- [ ] Run code analysis: `flutter analyze`
- [ ] Update version in pubspec.yaml
- [ ] Update README with new features
- [ ] Build release APK: `flutter build apk --release`
- [ ] Test on physical device
- [ ] Create release notes
- [ ] Tag git commit with version

## Resources

- [Flutter Documentation](https://flutter.dev/docs)
- [Riverpod Documentation](https://riverpod.dev)
- [Clean Architecture in Flutter](https://resocoder.com/flutter-clean-architecture)
- [Material Design 3](https://m3.material.io/)
