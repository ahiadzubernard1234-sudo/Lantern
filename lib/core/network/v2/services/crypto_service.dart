import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:lantern/core/database/database_service.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Result of checking a peer's identity key against the pinned (trusted) key.
enum TrustState { newPeer, trusted, changed }

/// Raised when a known device presents a different identity key.
class TrustAlert {
  final String deviceId;
  final String oldFingerprint;
  final String newFingerprint;
  const TrustAlert(this.deviceId, this.oldFingerprint, this.newFingerprint);
}

/// A hello packet whose signature has been verified.
class VerifiedHello {
  final String deviceId;
  final String identityKey;
  final String ephemeralKey;
  const VerifiedHello(this.deviceId, this.identityKey, this.ephemeralKey);
}

/// Our side of a handshake: ephemeral key pair plus the JSON we send.
class LocalHello {
  final KeyPair ephemeral;
  final String ephemeralKey;
  final Map<String, dynamic> json;
  const LocalHello(this.ephemeral, this.ephemeralKey, this.json);
}

/// Directional session keys derived for one connection.
class SessionKeys {
  final SecretKey send;
  final SecretKey receive;
  const SessionKeys(this.send, this.receive);
}

/// Identity, authenticated key exchange, encryption and peer key pinning.
///
/// - Each install has a long-term Ed25519 identity key.
/// - Each connection does an X25519 exchange; the ephemeral key is signed by
///   the identity key, binding the session to a device identity.
/// - Frames are encrypted with ChaCha20-Poly1305 using per-direction keys.
/// - Peers are pinned on first use (TOFU). A changed key is rejected.
class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  final Logger _logger = Logger();
  final Ed25519 _ed = Ed25519();
  final X25519 _x = X25519();
  final Chacha20 _aead = Chacha20.poly1305Aead();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);

  static const String _seedPref = 'lantern_identity_seed';
  static const String _pubPref = 'lantern_identity_pub';

  late SimpleKeyPairData _identity;
  late String _identityKeyB64;
  bool _ready = false;

  final StreamController<TrustAlert> _alerts =
      StreamController<TrustAlert>.broadcast();
  final Map<String, String> _pendingKeys = {};

  Stream<TrustAlert> get alerts => _alerts.stream;

  /// Load (or create) this device's identity key.
  Future<void> initialize() async {
    if (_ready) return;
    final prefs = await SharedPreferences.getInstance();
    final seed = prefs.getString(_seedPref);
    final pub = prefs.getString(_pubPref);

    if (seed != null && pub != null) {
      _identity = SimpleKeyPairData(
        base64Decode(seed),
        publicKey: SimplePublicKey(base64Decode(pub), type: KeyPairType.ed25519),
        type: KeyPairType.ed25519,
      );
    } else {
      final kp = await _ed.newKeyPair();
      _identity = await kp.extract() as SimpleKeyPairData;
      await prefs.setString(_seedPref, base64Encode(_identity.bytes));
      await prefs.setString(
          _pubPref, base64Encode(_identity.publicKey.bytes));
    }

    _identityKeyB64 = base64Encode(_identity.publicKey.bytes);
    _ready = true;
    _logger.i('Crypto identity ready: $localFingerprint');
  }

  /// This device's public identity key (base64).
  String get identityKey => _identityKeyB64;

  /// Human-readable fingerprint of this device's identity key.
  String get localFingerprint => fingerprintOf(_identityKeyB64);

  /// Short readable fingerprint (8 groups of 4 hex characters).
  String fingerprintOf(String keyB64) {
    final digest = hash.sha256.convert(base64Decode(keyB64)).toString().toUpperCase();
    return List.generate(8, (i) => digest.substring(i * 4, i * 4 + 4)).join(' ');
  }

  List<int> _helloBytes(String deviceId, String ephemeralKey) =>
      utf8.encode('lantern-hello-v1|$deviceId|$ephemeralKey');

  /// Build our hello: fresh ephemeral key, signed with the identity key.
  Future<LocalHello> createHello(String deviceId) async {
    final eph = await _x.newKeyPair();
    final ephPub = await eph.extractPublicKey() as SimplePublicKey;
    final ephB64 = base64Encode(ephPub.bytes);
    final sig = await _ed.sign(_helloBytes(deviceId, ephB64), keyPair: _identity);
    return LocalHello(eph, ephB64, {
      'v': 1,
      'deviceId': deviceId,
      'identityKey': _identityKeyB64,
      'ephemeralKey': ephB64,
      'signature': base64Encode(sig.bytes),
    });
  }

  /// Verify a peer's hello. Returns null when malformed or the signature fails.
  Future<VerifiedHello?> verifyHello(Map<String, dynamic> hello) async {
    try {
      if (hello['v'] != 1) return null;
      final deviceId = hello['deviceId'];
      final idKey = hello['identityKey'];
      final eph = hello['ephemeralKey'];
      final sig = hello['signature'];
      if (deviceId is! String || deviceId.isEmpty || deviceId.length > 128) return null;
      if (idKey is! String || eph is! String || sig is! String) return null;

      final idBytes = base64Decode(idKey);
      final ephBytes = base64Decode(eph);
      if (idBytes.length != 32 || ephBytes.length != 32) return null;

      final ok = await _ed.verify(
        _helloBytes(deviceId, eph),
        signature: Signature(
          base64Decode(sig),
          publicKey: SimplePublicKey(idBytes, type: KeyPairType.ed25519),
        ),
      );
      return ok ? VerifiedHello(deviceId, idKey, eph) : null;
    } catch (e) {
      _logger.w('Hello verification failed: $e');
      return null;
    }
  }

  /// Trust on first use: pin the key the first time, reject changes later.
  Future<TrustState> checkTrust(String deviceId, String identityKey) async {
    final db = DatabaseService().database;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query('trusted_peers',
        where: 'device_id = ?', whereArgs: [deviceId], limit: 1);

    if (rows.isEmpty) {
      await db.insert('trusted_peers', {
        'device_id': deviceId,
        'public_key': identityKey,
        'fingerprint': fingerprintOf(identityKey),
        'verified': 0,
        'first_seen': now,
        'last_seen': now,
      });
      _logger.i('Pinned new peer $deviceId');
      return TrustState.newPeer;
    }

    final stored = rows.first['public_key'] as String;
    if (stored == identityKey) {
      await db.update('trusted_peers', {'last_seen': now},
          where: 'device_id = ?', whereArgs: [deviceId]);
      return TrustState.trusted;
    }

    _pendingKeys[deviceId] = identityKey;
    _alerts.add(TrustAlert(
        deviceId, fingerprintOf(stored), fingerprintOf(identityKey)));
    _logger.w('Identity key CHANGED for $deviceId. Connection rejected.');
    return TrustState.changed;
  }

  /// Fingerprint of a pinned peer (null if never seen).
  Future<String?> peerFingerprint(String deviceId) async {
    final rows = await DatabaseService().database.query('trusted_peers',
        columns: ['fingerprint'],
        where: 'device_id = ?',
        whereArgs: [deviceId],
        limit: 1);
    return rows.isEmpty ? null : rows.first['fingerprint'] as String;
  }

  /// True if the peer presented a new key that was rejected and is waiting
  /// for the user to decide.
  bool hasPendingKeyChange(String deviceId) =>
      _pendingKeys.containsKey(deviceId);

  /// Fingerprint of the rejected new key (null if none is pending).
  String? pendingFingerprint(String deviceId) {
    final key = _pendingKeys[deviceId];
    return key == null ? null : fingerprintOf(key);
  }

  /// Whether the user confirmed this peer's fingerprint out of band.
  Future<bool> isVerified(String deviceId) async {
    final rows = await DatabaseService().database.query('trusted_peers',
        columns: ['verified'],
        where: 'device_id = ?',
        whereArgs: [deviceId],
        limit: 1);
    return rows.isNotEmpty && rows.first['verified'] == 1;
  }

  /// Mark a peer as verified after the user compared fingerprints.
  Future<void> markVerified(String deviceId) async {
    await DatabaseService().database.update('trusted_peers', {'verified': 1},
        where: 'device_id = ?', whereArgs: [deviceId]);
  }

  /// Accept the most recently rejected key for a device (user decision).
  Future<bool> acceptKeyChange(String deviceId) async {
    final key = _pendingKeys.remove(deviceId);
    if (key == null) return false;
    await DatabaseService().database.update(
      'trusted_peers',
      {
        'public_key': key,
        'fingerprint': fingerprintOf(key),
        'verified': 0,
        'last_seen': DateTime.now().toIso8601String(),
      },
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
    return true;
  }

  /// Derive directional session keys from the X25519 shared secret.
  Future<SessionKeys> deriveSession({
    required KeyPair myEphemeral,
    required String myEphemeralKey,
    required String theirEphemeralKey,
  }) async {
    final shared = await _x.sharedSecretKey(
      keyPair: myEphemeral,
      remotePublicKey: SimplePublicKey(
        base64Decode(theirEphemeralKey),
        type: KeyPairType.x25519,
      ),
    );

    final iAmLow = myEphemeralKey.compareTo(theirEphemeralKey) < 0;
    final low = iAmLow ? myEphemeralKey : theirEphemeralKey;
    final high = iAmLow ? theirEphemeralKey : myEphemeralKey;

    final okm = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('$low|$high'),
      info: utf8.encode('lantern-session-v1'),
    );
    final bytes = await okm.extractBytes();
    final first = SecretKey(bytes.sublist(0, 32));
    final second = SecretKey(bytes.sublist(32, 64));
    return iAmLow ? SessionKeys(first, second) : SessionKeys(second, first);
  }

  /// Encrypt a payload. Output is nonce + ciphertext + MAC.
  Future<List<int>> encrypt(SecretKey key, List<int> plain) async {
    final box = await _aead.encrypt(plain, secretKey: key);
    return box.concatenation();
  }

  /// Decrypt and authenticate a payload. Throws if tampered with.
  Future<List<int>> decrypt(SecretKey key, List<int> data) async {
    final nonceLen = _aead.nonceLength;
    final macLen = _aead.macAlgorithm.macLength;
    if (data.length < nonceLen + macLen) {
      throw const FormatException('Ciphertext too short');
    }
    final box = SecretBox.fromConcatenation(
      data,
      nonceLength: nonceLen,
      macLength: macLen,
    );
    return _aead.decrypt(box, secretKey: key);
  }
}
