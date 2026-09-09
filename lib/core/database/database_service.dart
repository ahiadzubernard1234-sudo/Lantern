import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  late Database _database;

  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  Future<void> initialize() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final dbPath = join(documentsDirectory.path, 'lantern.db');

    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: _createTables,
      onUpgrade: _upgradeTables,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    // Profiles table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS profiles (
        id TEXT PRIMARY KEY,
        username TEXT UNIQUE NOT NULL,
        avatar_path TEXT,
        device_name TEXT,
        device_id TEXT UNIQUE NOT NULL,
        ip_address TEXT,
        port INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Messages table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
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
        read_at TEXT,
        FOREIGN KEY (sender_id) REFERENCES profiles(id),
        FOREIGN KEY (receiver_id) REFERENCES profiles(id)
      )
    ''');

    // Channels table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS channels (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        owner_id TEXT NOT NULL,
        member_count INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (owner_id) REFERENCES profiles(id)
      )
    ''');

    // Channel members table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS channel_members (
        id TEXT PRIMARY KEY,
        channel_id TEXT NOT NULL,
        member_id TEXT NOT NULL,
        joined_at TEXT NOT NULL,
        muted BOOLEAN DEFAULT 0,
        FOREIGN KEY (channel_id) REFERENCES channels(id),
        FOREIGN KEY (member_id) REFERENCES profiles(id),
        UNIQUE(channel_id, member_id)
      )
    ''');

    // Channel messages table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS channel_messages (
        id TEXT PRIMARY KEY,
        channel_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        content TEXT NOT NULL,
        message_type TEXT DEFAULT 'text',
        file_path TEXT,
        file_name TEXT,
        file_size INTEGER,
        created_at TEXT NOT NULL,
        FOREIGN KEY (channel_id) REFERENCES channels(id),
        FOREIGN KEY (sender_id) REFERENCES profiles(id)
      )
    ''');

    // Peers table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS peers (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        ip_address TEXT NOT NULL,
        port INTEGER NOT NULL,
        device_id TEXT NOT NULL,
        device_name TEXT,
        avatar_path TEXT,
        last_seen TEXT NOT NULL,
        is_online BOOLEAN DEFAULT 1
      )
    ''');

    // Create indexes for better query performance
    await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_receiver ON messages(receiver_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_channel_messages_channel ON channel_messages(channel_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_channel_members_channel ON channel_members(channel_id)');
  }

  Future<void> _upgradeTables(Database db, int oldVersion, int newVersion) async {
    // Handle database upgrades here
  }

  Database get database => _database;

  Future<void> close() async {
    await _database.close();
  }

  Future<void> deleteDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final dbPath = join(documentsDirectory.path, 'lantern.db');
    await databaseFactory.deleteDatabase(dbPath);
  }
}
