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
      version: 3,
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
        read_at TEXT
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


    await db.execute('''
      CREATE TABLE IF NOT EXISTS file_transfers (
        id TEXT PRIMARY KEY,
        session_id TEXT UNIQUE NOT NULL,
        file_name TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        sender_id TEXT NOT NULL,
        receiver_id TEXT NOT NULL,
        total_chunks INTEGER NOT NULL,
        received_chunks INTEGER NOT NULL DEFAULT 0,
        progress REAL DEFAULT 0,
        is_complete INTEGER DEFAULT 0,
        is_failed INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // Create indexes for better query performance
    await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_receiver ON messages(receiver_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_channel_messages_channel ON channel_messages(channel_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_channel_members_channel ON channel_members(channel_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_peers_device_id ON peers(device_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_peers_online ON peers(is_online)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_file_transfers_session ON file_transfers(session_id)');
  }

  Future<void> _upgradeTables(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
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
      await db.execute('''
        CREATE TABLE IF NOT EXISTS file_transfers (
          id TEXT PRIMARY KEY,
          session_id TEXT UNIQUE NOT NULL,
          file_name TEXT NOT NULL,
          file_size INTEGER NOT NULL,
          sender_id TEXT NOT NULL,
          receiver_id TEXT NOT NULL,
          total_chunks INTEGER NOT NULL,
          received_chunks INTEGER NOT NULL DEFAULT 0,
          progress REAL DEFAULT 0,
          is_complete INTEGER DEFAULT 0,
          is_failed INTEGER DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_peers_device_id ON peers(device_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_peers_online ON peers(is_online)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_file_transfers_session ON file_transfers(session_id)');
    }
    await db.execute('CREATE INDEX IF NOT EXISTS idx_peers_device_id ON peers(device_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_peers_online ON peers(is_online)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_file_transfers_session ON file_transfers(session_id)');
    if (oldVersion < 3) {
      // Remote device IDs are not local profile primary keys. Rebuild message tables
      // without the incorrect profile foreign keys.
      await db.transaction((txn) async {
        await txn.execute('ALTER TABLE messages RENAME TO messages_old');
        await txn.execute('''CREATE TABLE messages (
          id TEXT PRIMARY KEY, sender_id TEXT NOT NULL, receiver_id TEXT NOT NULL,
          content TEXT NOT NULL, message_type TEXT DEFAULT 'text', file_path TEXT,
          file_name TEXT, file_size INTEGER, created_at TEXT NOT NULL,
          delivered_at TEXT, read_at TEXT)''');
        await txn.execute('''INSERT INTO messages (id,sender_id,receiver_id,content,message_type,file_path,file_name,file_size,created_at,delivered_at,read_at)
          SELECT id,sender_id,receiver_id,content,message_type,file_path,file_name,file_size,created_at,delivered_at,read_at FROM messages_old''');
        await txn.execute('DROP TABLE messages_old');

        await txn.execute('ALTER TABLE channel_messages RENAME TO channel_messages_old');
        await txn.execute('''CREATE TABLE channel_messages (
          id TEXT PRIMARY KEY, channel_id TEXT NOT NULL, sender_id TEXT NOT NULL,
          content TEXT NOT NULL, message_type TEXT DEFAULT 'text', file_path TEXT,
          file_name TEXT, file_size INTEGER, created_at TEXT NOT NULL,
          FOREIGN KEY (channel_id) REFERENCES channels(id))''');
        await txn.execute('''INSERT INTO channel_messages (id,channel_id,sender_id,content,message_type,file_path,file_name,file_size,created_at)
          SELECT id,channel_id,sender_id,content,message_type,file_path,file_name,file_size,created_at FROM channel_messages_old''');
        await txn.execute('DROP TABLE channel_messages_old');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id)');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_messages_receiver ON messages(receiver_id)');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at)');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_channel_messages_channel ON channel_messages(channel_id)');
      });
    }
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
