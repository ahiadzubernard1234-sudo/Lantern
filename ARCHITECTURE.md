# LANtern Architecture Document

## Overview

LANtern follows a **Clean Architecture** pattern with **MVVM** (Model-View-ViewModel) presentation layer and **Riverpod** for state management.

```
┌─────────────────────────────────────────┐
│         PRESENTATION LAYER              │
│  (UI, Widgets, State Management)        │
├─────────────────────────────────────────┤
│         DOMAIN LAYER                    │
│  (Entities, Repositories, Interfaces)   │
├─────────────────────────────────────────┤
│         DATA LAYER                      │
│  (Datasources, Models, Implementations) │
├─────────────────────────────────────────┤
│         FRAMEWORK LAYER                 │
│  (Database, Network, OS Services)       │
└─────────────────────────────────────────┘
```

## Layer Details

### Presentation Layer

**Responsibility**: UI rendering and user interaction

**Components**:
- **Pages**: Full-screen widgets (HomeScreen, ChatScreen)
- **Widgets**: Reusable UI components (MessageBubble, UserCard)
- **Providers**: Riverpod state management
- **Navigation**: Bottom navigation, route management

**State Management Flow**:
```
User Action → Provider Update → UI Rebuild
      ↓
   Network/Database Call
      ↓
   Provider State Change
      ↓
   Rebuild Listener
```

**Key Files**:
- `lib/features/*/presentation/pages/`: Page widgets
- `lib/features/*/presentation/providers/`: Riverpod providers
- `lib/features/*/presentation/widgets/`: Reusable components

### Domain Layer

**Responsibility**: Business logic rules (framework-independent)

**Components**:
- **Entities**: Pure Dart objects (no Flutter dependencies)
- **Repositories**: Abstract interfaces defining contracts
- **Usecases**: Business logic operations (future expansion)

**Design Principles**:
- No dependencies on lower layers
- No framework-specific code
- Pure Dart, testable code
- Clear contracts for data access

**Example Entity**:
```dart
class Message extends Equatable {
  final String id;
  final String senderId;
  final String receiverId;
  final String content;

  const Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
  });
}
```

**Example Repository Interface**:
```dart
abstract class MessageRepository {
  Future<void> sendMessage({
    required String senderId,
    required String receiverId,
    required String content,
  });

  Future<List<Message>> getConversation(String peerId);
}
```

### Data Layer

**Responsibility**: Data access and transformation

**Components**:
- **Datasources**: Local/remote data operations
- **Models**: Data transfer objects (entities + serialization)
- **Repository Implementations**: Concrete implementations
- **Mappers**: Entity ↔ Model conversion

**Local Datasource Pattern**:
```dart
class LocalMessageDatasource {
  final DatabaseService _db;

  Future<void> saveMessage(...) async {
    await _db.database.insert('messages', model.toMap());
  }

  Future<List<Message>> getMessages() async {
    final results = await _db.database.query('messages');
    return results.map((m) => Message.fromMap(m)).toList();
  }
}
```

**Repository Implementation Pattern**:
```dart
class MessageRepositoryImpl implements MessageRepository {
  final LocalMessageDatasource _datasource;
  final NetworkService _network;

  @override
  Future<void> sendMessage({...}) async {
    // Save locally first
    await _datasource.saveMessage(...);

    // Send via network
    await _network.sendMessageToPeer(...);

    // Update delivery status
    await _datasource.markAsDelivered(...);
  }
}
```

### Framework Layer

**Responsibility**: Platform-specific implementations

**Core Services**:

#### DatabaseService
- SQLite initialization
- Schema management
- Connection pooling
- Query execution

#### NetworkService
- TCP socket management
- UDP broadcast
- Peer connections
- Message transmission

#### PeerDiscoveryService
- UDP discovery packets
- Peer tracking
- Online/offline status
- Listener notifications

## Data Flow

### Sending a Message

```
1. User types message and taps send
   └─> ChatScreen calls messageNotifier.sendMessage()

2. MessageNotifier (StateNotifier)
   └─> Sets state to loading

3. MessageRepository.sendMessage()
   └─> Calls LocalMessageDatasource.saveMessage()
       Saves to SQLite locally
   └─> Calls NetworkService.sendMessageToPeer()
       Sends via TCP to recipient

4. On success
   └─> Sets message state to delivered
   └─> Updates UI via Riverpod listeners

5. On failure
   └─> Retries with backoff
   └─> Shows error toast to user
```

### Receiving a Message

```
1. NetworkService receives data on TCP socket
   └─> Parses JSON message packet

2. Invokes registered listeners
   └─> Sends to appropriate handler

3. MessageRepository updates local state
   └─> Saves message to database
   └─> Updates conversation timestamp

4. Notifies Riverpod listeners
   └─> ConversationProvider rebuilds
   └─> UI shows new message

5. Sends delivery acknowledgment
   └─> NetworkService sends ACK back
```

### Discovering Peers

```
1. App starts discovery (Settings or Home)
   └─> PeerDiscoveryService.startDiscovery()

2. Periodic UDP broadcast
   └─> Every 5 seconds sends discovery packet
   └─> Contains: username, device ID, IP, port

3. Receives incoming discovery packets
   └─> UDP socket listener triggers
   └─> Parses peer information

4. Updates peer registry
   └─> Stores in _discoveredPeers map
   └─> Notifies listeners

5. Timeout check
   └─> Peers inactive 30+ seconds marked offline
   └─> UI updates to show offline status
```

## State Management with Riverpod

### Provider Types Used

#### 1. StateProvider
For simple mutable state (theme, UI flags)
```dart
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
```

#### 2. FutureProvider
For async data fetching
```dart
final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  return ref.watch(profileRepositoryProvider).getProfile();
});
```

#### 3. StateNotifierProvider
For complex state with methods
```dart
final profileNotifier = StateNotifierProvider<ProfileNotifier, AsyncValue<Profile?>>((ref) {
  final repo = ref.watch(profileRepositoryProvider);
  return ProfileNotifier(repo);
});
```

#### 4. Provider
For computed/derived values
```dart
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ServiceLocator().profileRepository;
});
```

### Dependency Injection

Uses manual service locator pattern:

```dart
// Service Locator setup
class ServiceLocator {
  static final _instance = ServiceLocator._internal();

  late DatabaseService _database;
  late NetworkService _network;
  late ProfileRepository _profileRepo;

  Future<void> initialize() async {
    _database = DatabaseService();
    await _database.initialize();

    _network = NetworkService();
    _profileRepo = ProfileRepositoryImpl(_database, _network);
  }
}

// Use in providers
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ServiceLocator().profileRepository;
});
```

## Networking Architecture

### Discovery Protocol

**UDP Broadcast on Port 15554**

Discovery packet structure:
```json
{
  "type": "discovery",
  "username": "string",
  "ipAddress": "string",
  "port": number,
  "deviceId": "string",
  "deviceName": "string",
  "timestamp": "ISO8601"
}
```

### Message Protocol

**TCP on Port 15555**

Direct message:
```json
{
  "type": "message",
  "id": "uuid",
  "senderId": "uuid",
  "receiverId": "uuid",
  "content": "string",
  "messageType": "text|image|audio|pdf|file",
  "timestamp": "ISO8601"
}
```

File transfer:
```json
{
  "type": "file",
  "id": "uuid",
  "senderId": "uuid",
  "receiverId": "uuid",
  "fileName": "string",
  "fileSize": number,
  "fileBytes": "base64",
  "timestamp": "ISO8601"
}
```

Channel broadcast:
```json
{
  "type": "channel_message",
  "channelId": "uuid",
  "senderId": "uuid",
  "content": "string",
  "timestamp": "ISO8601"
}
```

## Database Schema

```sql
-- User Profiles
CREATE TABLE profiles (
  id TEXT PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  avatar_path TEXT,
  device_name TEXT,
  device_id TEXT UNIQUE,
  ip_address TEXT,
  port INTEGER,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Direct Messages
CREATE TABLE messages (
  id TEXT PRIMARY KEY,
  sender_id TEXT NOT NULL,
  receiver_id TEXT NOT NULL,
  content TEXT NOT NULL,
  message_type TEXT DEFAULT 'text',
  file_path TEXT,
  file_name TEXT,
  file_size INTEGER,
  created_at TEXT NOT NULL,
  delivered_at TEXT,
  read_at TEXT
);

-- Channels
CREATE TABLE channels (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  owner_id TEXT NOT NULL,
  member_count INTEGER DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Channel Members
CREATE TABLE channel_members (
  id TEXT PRIMARY KEY,
  channel_id TEXT NOT NULL,
  member_id TEXT NOT NULL,
  joined_at TEXT NOT NULL,
  muted BOOLEAN DEFAULT 0,
  UNIQUE(channel_id, member_id)
);

-- Channel Messages
CREATE TABLE channel_messages (
  id TEXT PRIMARY KEY,
  channel_id TEXT NOT NULL,
  sender_id TEXT NOT NULL,
  content TEXT NOT NULL,
  message_type TEXT DEFAULT 'text',
  file_path TEXT,
  file_name TEXT,
  file_size INTEGER,
  created_at TEXT NOT NULL
);

-- Discovered Peers
CREATE TABLE peers (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL,
  ip_address TEXT NOT NULL,
  port INTEGER NOT NULL,
  device_id TEXT NOT NULL,
  device_name TEXT,
  avatar_path TEXT,
  last_seen TEXT NOT NULL,
  is_online BOOLEAN DEFAULT 1
);
```

## Error Handling Strategy

### Network Errors
- Automatic retry with exponential backoff
- Fallback to local storage if network unavailable
- User notification for persistent failures

### Database Errors
- Transaction rollback on conflicts
- Detailed error logging
- Graceful degradation

### File Transfer Errors
- Partial file cleanup
- Resume capability for large files
- Checksum verification

## Performance Optimizations

### Peer Discovery
- Configurable broadcast interval (default 5s)
- Lazy socket initialization
- Automatic timeout cleanup

### Database
- Indexed queries on frequently searched fields
- Pagination for large result sets
- Connection pooling

### Memory
- Stream-based data loading
- Periodic memory cleanup
- Resource disposal on app exit

### Network
- Connection reuse (persistent sockets)
- Message batching for channels
- Compression for large files

## Testing Architecture

### Unit Tests
- Domain entities and business logic
- Repository implementations (mocked datasources)
- State management (Riverpod providers)

### Integration Tests
- Feature-level testing with real database
- Network protocol testing with mock servers
- End-to-end user flows

### Widget Tests
- UI component rendering
- User interaction handling
- State updates and rebuilds

## Extension Points

The architecture supports future extensions without major refactoring:

1. **Voice/Video**: Add WebRTC integration
2. **Encryption**: Implement TLS/Noise protocol
3. **Persistence**: Add cloud sync layer
4. **Authentication**: Add user auth system
5. **Analytics**: Add telemetry layer

## Scalability Considerations

### Current Limits
- 100+ peers on single LAN
- 1000+ messages per conversation
- 10MB file transfers
- 50+ simultaneous connections

### Optimization for Scale
- Message pagination and lazy loading
- Peer caching with periodic refresh
- Connection pooling and reuse
- Database query optimization

### Future Scaling
- Message archiving and cleanup
- Distributed peer discovery
- Message indexing and search
- Bandwidth optimization
