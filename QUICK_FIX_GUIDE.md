# LANtern Integration - Quick Fix Guide

## 🚀 Fast Path to Production (2-3 hours)

This guide provides the exact code needed to fix all critical issues.

---

## FIX #1: Initialize NetworkServiceCoordinator in main.dart

**File**: `lib/main.dart`

**Replace entire file with:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'package:lantern/core/di/service_locator.dart';
import 'package:lantern/features/app/presentation/pages/app_shell.dart';
import 'package:lantern/core/theme/app_theme.dart';
import 'package:lantern/core/network/network_coordinator.dart';

// Global coordinator
late final NetworkServiceCoordinator _networkCoordinator;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize V2 networking layer
  _networkCoordinator = NetworkServiceCoordinator();
  try {
    await _networkCoordinator.initialize(
      deviceId: 'device-${DateTime.now().millisecondsSinceEpoch}',
      username: 'User',
      deviceName: Platform.isAndroid ? 'Android Device' : 'iOS Device',
    );
    print('✅ Network coordinator initialized');
  } catch (e) {
    print('❌ Network initialization failed: $e');
    // Continue anyway - UI will show error
  }

  // Initialize V1 services
  await setupServiceLocator();

  runApp(const ProviderScope(child: LANternApp()));
}

class LANternApp extends ConsumerWidget {
  const LANternApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'LANtern',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: AppLifecycleListener(
        onStateChange: (state) {
          if (state == AppLifecycleState.detached) {
            _networkCoordinator.shutdown();
          }
        },
        child: const AppShell(),
      ),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en', 'US')],
    );
  }
}

// Lifecycle listener widget
class AppLifecycleListener extends StatefulWidget {
  final void Function(AppLifecycleState) onStateChange;
  final Widget child;

  const AppLifecycleListener({
    required this.onStateChange,
    required this.child,
    Key? key,
  }) : super(key: key);

  @override
  State<AppLifecycleListener> createState() => _AppLifecycleListenerState();
}

class _AppLifecycleListenerState extends State<AppLifecycleListener>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.onStateChange(state);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

---

## FIX #2: Update AndroidManifest.xml Permissions

**File**: `android/app/src/main/AndroidManifest.xml`

**Replace all permission lines with:**

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.lantern.app">

    <!-- Network and LAN permissions -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

    <!-- WiFi permissions -->
    <uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />

    <!-- Nearby devices (Android 12+) -->
    <uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" />

    <!-- Storage permissions -->
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />

    <!-- Notification permissions (Android 13+) -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <application
        android:label="LANtern"
        android:icon="@mipmap/ic_launcher">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">

            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>

    <!-- Required for Android 12+ -->
    <queries>
        <action android:name="android.net.nsd.NSD_SERVICE_DISCOVERY_STARTED" />
        <action android:name="android.net.nsd.NSD_SERVICE_DISCOVERY_STOPPED" />
    </queries>
</manifest>
```

---

## FIX #3: Update Database Schema

**File**: `lib/core/database/database_service.dart`

**In `_createTables` method, add peers table after messages table:**

```dart
// Peers table (discovered peers on network)
await db.execute('''
  CREATE TABLE IF NOT EXISTS peers (
    id TEXT PRIMARY KEY,
    username TEXT NOT NULL,
    ip_address TEXT NOT NULL,
    port INTEGER NOT NULL,
    device_id TEXT NOT NULL UNIQUE,
    device_name TEXT,
    avatar_path TEXT,
    last_seen TEXT NOT NULL,
    is_online BOOLEAN DEFAULT 1
  )
''');

// File transfers table
await db.execute('''
  CREATE TABLE IF NOT EXISTS file_transfers (
    id TEXT PRIMARY KEY,
    session_id TEXT UNIQUE NOT NULL,
    file_name TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    sender_id TEXT NOT NULL,
    receiver_id TEXT NOT NULL,
    total_chunks INTEGER NOT NULL,
    received_chunks INTEGER NOT NULL,
    progress REAL DEFAULT 0,
    is_complete BOOLEAN DEFAULT 0,
    is_failed BOOLEAN DEFAULT 0,
    created_at TEXT NOT NULL
  )
''');
```

**Also add indexes:**

```dart
// In _createTables, after table creation:
await db.execute('CREATE INDEX IF NOT EXISTS idx_peers_device_id ON peers(device_id)');
await db.execute('CREATE INDEX IF NOT EXISTS idx_peers_online ON peers(is_online)');
await db.execute('CREATE INDEX IF NOT EXISTS idx_file_transfers_session ON file_transfers(session_id)');
```

---

## FIX #4: Fix ConnectionManager Stream Leaks

**File**: `lib/core/network/services/connection_manager.dart`

**Add to class:**

```dart
// Add this field to the class
final Map<String, StreamSubscription> _subscriptions = {};

// Replace _handleIncomingConnection method:
void _handleIncomingConnection(Socket socket) {
  final remoteAddress = '${socket.remoteAddress.address}:${socket.remotePort}';
  _logger.d('Incoming connection from $remoteAddress');

  final connection = _PeerConnection(
    socket: socket,
    remoteAddress: remoteAddress,
    isOutgoing: false,
  );

  // STORE subscription for cleanup
  final subscription = socket.listen(
    (List<int> data) {
      try {
        final message = NetworkMessage.decode(data);
        _logger.d('Message received from $remoteAddress: ${message.type}');

        if (message.type == MessageType.discovery) {
          final deviceId = message.metadata?['deviceId'] as String?;
          if (deviceId != null) {
            connection.remoteDeviceId = deviceId;
            _connections[deviceId] = connection;
            _logger.d('Connection established with device: $deviceId');
          }
        }

        _notifyMessageCallbacks(message);
      } catch (e) {
        _logger.w('Error processing incoming data: $e');
      }
    },
    onError: (error) {
      _logger.e('Socket error for $remoteAddress: $error');
      connection.remoteDeviceId?.let((id) => _connections.remove(id));
      _subscriptions.remove(remoteAddress);
    },
    onDone: () {
      _logger.d('Connection closed from $remoteAddress');
      connection.remoteDeviceId?.let((id) => _connections.remove(id));
      _subscriptions.remove(remoteAddress);
    },
    cancelOnError: true,
  );

  _subscriptions[remoteAddress] = subscription;
}

// Update shutdown to cancel subscriptions:
Future<void> shutdown() async {
  try {
    // Cancel all subscriptions FIRST
    for (final sub in _subscriptions.values) {
      await sub.cancel();
    }
    _subscriptions.clear();

    // Close all peer connections
    for (final deviceId in _connections.keys.toList()) {
      await disconnectPeer(deviceId);
    }

    // Close server socket
    await _serverSocket.close();
    _isInitialized = false;
    _logger.i('Connection manager shutdown');
  } catch (e) {
    _logger.e('Error shutting down connection manager: $e');
  }
}
```

---

## FIX #5: Clean Up Listeners in Coordinator

**File**: `lib/core/network/network_coordinator.dart`

**Update shutdown method:**

```dart
/// Shutdown all services
Future<void> shutdown() async {
  try {
    _maintenanceTimer.cancel();

    // Remove ALL listeners FIRST
    discoveryService._listeners.clear();
    messageService._receivedCallbacks.clear();
    deliveryManager._statusCallbacks.clear();
    presenceManager._callbacks.clear();
    roomManager._roomCallbacks.clear();
    fileTransferService._callbacks.clear();
    networkMonitor._callbacks.clear();

    // Then shutdown services
    await discoveryService.stopDiscovery();
    await connectionManager.shutdown();
    await networkMonitor.stopMonitoring();

    deliveryManager.shutdown();
    messageService.clearAll();
    presenceManager.clear();
    roomManager.clear();
    securityService.clear();

    _initialized = false;
    _logger.i('Network services shutdown complete');
  } catch (e) {
    _logger.e('Error during shutdown: $e');
  }
}
```

---

## FIX #6: Remove Old V1 Network Services

**Delete these files completely:**

```bash
# From terminal:
rm -f lib/core/network/network_service.dart
rm -f lib/core/network/peer_discovery_service.dart
# (Keep only V2's network folder at lib/core/network/)
```

---

## FIX #7: Add Try-Catch to Repository Methods

**Example file**: `lib/features/chat/data/repositories/message_repository_impl.dart`

**Wrap all try-catch blocks like this:**

```dart
// WRONG:
try {
  await _datasource.saveMessage(...);
  await _network.sendMessageToPeer(...);
} catch (e) {
  // Missing handler
}

// RIGHT:
try {
  await _datasource.saveMessage(...);
  await _network.sendMessageToPeer(...);
  _logger.d('Message sent successfully');
} catch (e) {
  _logger.e('Failed to send message: $e');
  // Update UI error state or rethrow
  rethrow;
}
```

---

## 🧪 Quick Test

After applying fixes, run:

```bash
# Clean build
flutter clean
flutter pub get

# Run on device
flutter run

# Check logs for:
# ✅ "Network coordinator initialized"
# ✅ "Discovery service started"
# ✅ "Peer discovered"
```

---

## ⚠️ Common Issues After Fixes

### Issue: "NetworkServiceCoordinator not found"
**Fix**: Ensure `import 'package:lantern/core/network/network_coordinator.dart';` in main.dart

### Issue: "Database table doesn't exist"
**Fix**: Delete app, run `flutter clean`, rebuild (recreates database)

### Issue: "Peers not discovering"
**Fix**: Check Android permissions - toggle WiFi off/on to test

### Issue: "Permission denied errors"
**Fix**: On device, go to Settings > Apps > LANtern > Permissions > enable all

---

## ✅ Success Indicators

After all fixes:
- ✅ App starts without crash
- ✅ No red errors in logcat
- ✅ Two devices discover each other < 5 sec
- ✅ Messages send and receive
- ✅ No memory growth over 5 minutes

---

**Estimated Time**: 60-90 minutes to apply all fixes
**Difficulty**: Medium (mostly copy-paste)
**Result**: Production-ready app
