import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import '../models/network_models.dart';

typedef FileTransferCallback = void Function(FileTransferSession session);

class FileTransferService {
  static final FileTransferService _instance = FileTransferService._internal();
  final Logger _logger = Logger();

  final Map<String, FileTransferSession> _transfers = {};
  final List<FileTransferCallback> _callbacks = [];
  final Map<String, Set<int>> _receivedChunkIndexes = {};
  final Map<String, String> _expectedHashes = {};

  static const int CHUNK_SIZE = 65536; // 64KB chunks

  factory FileTransferService() => _instance;
  FileTransferService._internal();

  /// Start file transfer
  Future<FileTransferSession> startTransfer({
    required String filePath,
    required String recipientDeviceId,
    required String senderDeviceId,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File not found: $filePath');
      }

      final fileSize = await file.length();
      final fileName = file.path.split('/').last;
      final totalChunks = fileSize == 0 ? 0 : (fileSize / CHUNK_SIZE).ceil();
      final fileHash = sha256.convert(await file.readAsBytes()).toString();

      final sessionId = const Uuid().v4();

      final session = FileTransferSession(
        sessionId: sessionId,
        fileName: fileName,
        fileSize: fileSize,
        senderDeviceId: senderDeviceId,
        receiverDeviceId: recipientDeviceId,
        totalChunks: totalChunks,
        receivedChunks: 0,
        progress: 0.0,
        isComplete: false,
        isFailed: false,
      );

      _transfers[sessionId] = session;
      _expectedHashes[sessionId] = fileHash;
      _logger.i('File transfer started: $fileName ($fileSize bytes)');
      _notifyTransfer(session);

      return session;
    } catch (e) {
      _logger.e('Failed to start file transfer: $e');
      rethrow;
    }
  }

  /// Send every chunk using the supplied network callback.
  Future<void> sendTransfer({
    required FileTransferSession session,
    required String filePath,
    required Future<void> Function(NetworkMessage message) send,
  }) async {
    try {
      if (session.totalChunks == 0) {
        final packet = createTransferPacket(
          session: session,
          chunkIndex: 0,
          chunkData: const <int>[],
        );
        await send(packet);
        return;
      }
      for (var index = 0; index < session.totalChunks; index++) {
        final chunk = await readChunk(filePath: filePath, chunkIndex: index);
        final packet = createTransferPacket(
          session: session,
          chunkIndex: index,
          chunkData: chunk,
        );
        await send(packet);
      }
    } catch (e) {
      await cancelTransfer(session.sessionId);
      rethrow;
    }
  }

  /// Read file chunk
  Future<List<int>> readChunk({
    required String filePath,
    required int chunkIndex,
  }) async {
    try {
      final file = File(filePath);
      final fileSize = await file.length();

      final start = chunkIndex * CHUNK_SIZE;
      final end = (start + CHUNK_SIZE).clamp(0, fileSize);

      final bytes = await file.openRead(start, end).fold<List<int>>(
            <int>[],
            (previous, element) => previous..addAll(element),
          );

      _logger.d('Read chunk $chunkIndex: ${bytes.length} bytes');
      return bytes;
    } catch (e) {
      _logger.e('Failed to read chunk: $e');
      rethrow;
    }
  }

  /// Create file transfer packet
  NetworkMessage createTransferPacket({
    required FileTransferSession session,
    required int chunkIndex,
    required List<int> chunkData,
  }) {
    final encoded = base64Encode(chunkData);

    return NetworkMessage(
      id: '${session.sessionId}-$chunkIndex',
      senderId: session.senderDeviceId,
      receiverId: session.receiverDeviceId,
      type: MessageType.file,
      content: encoded,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      metadata: {
        'sessionId': session.sessionId,
        'fileName': session.fileName,
        'fileSize': session.fileSize,
        'totalChunks': session.totalChunks,
        'chunkIndex': chunkIndex,
        'chunkSize': chunkData.length,
        'fileHash': _expectedHashes[session.sessionId],
      },
    );
  }

  /// Handle received file chunk
  Future<void> handleFileChunk({
    required NetworkMessage message,
    required String outputDirectory,
  }) async {
    try {
      final metadata = message.metadata;
      if (metadata == null) return;

      final sessionId = metadata['sessionId'];
      final chunkIndex = metadata['chunkIndex'];
      final fileName = metadata['fileName'];
      final fileSize = metadata['fileSize'];
      final totalChunks = metadata['totalChunks'];
      final fileHash = metadata['fileHash'];

      if (sessionId is! String || sessionId.isEmpty || chunkIndex is! int || chunkIndex < 0 || fileName is! String || fileName.isEmpty) {
        _logger.w('Invalid file transfer metadata');
        return;
      }

      // Create or get session
      var session = _transfers[sessionId];
      if (session == null) {
        session = FileTransferSession(
          sessionId: sessionId,
          fileName: path.basename(fileName),
          fileSize: fileSize is int ? fileSize : 0,
          senderDeviceId: message.senderId,
          receiverDeviceId: message.receiverId,
          totalChunks: totalChunks is int && totalChunks >= 0 ? totalChunks : 0,
          receivedChunks: 0,
          progress: 0.0,
          isComplete: false,
          isFailed: false,
        );
        _transfers[sessionId] = session;
        _receivedChunkIndexes[sessionId] = <int>{};
        if (fileHash is String && fileHash.length == 64) _expectedHashes[sessionId] = fileHash;
      }

      final received = _receivedChunkIndexes.putIfAbsent(sessionId, () => <int>{});
      if (received.contains(chunkIndex)) {
        _logger.d('Ignoring duplicate chunk $chunkIndex for $sessionId');
        return;
      }
      if (session.totalChunks == 0) {
        if (chunkIndex != 0 || message.content.isNotEmpty) return;
        final filePath = path.join(path.normalize(outputDirectory), path.basename(fileName));
        final file = File(filePath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(const <int>[], flush: true);
        final completed = FileTransferSession(
          sessionId: session.sessionId,
          fileName: session.fileName,
          fileSize: 0,
          senderDeviceId: session.senderDeviceId,
          receiverDeviceId: session.receiverDeviceId,
          totalChunks: 0,
          receivedChunks: 0,
          progress: 1.0,
          isComplete: true,
          isFailed: false,
        );
        _transfers[sessionId] = completed;
        _notifyTransfer(completed);
        return;
      }
      if (chunkIndex >= session.totalChunks) {
        _logger.w('Invalid chunk index $chunkIndex for $sessionId');
        return;
      }

      // Decode chunk data
      final chunkData = base64Decode(message.content);

      // Write to file
      final safeFileName = path.basename(fileName);
      if (safeFileName != fileName || safeFileName == '.' || safeFileName == '..') {
        _logger.w('Rejected unsafe file name: $fileName');
        return;
      }
      final outputDir = path.normalize(outputDirectory);
      final filePath = path.join(outputDir, safeFileName);
      final relativePath = path.relative(filePath, from: outputDir);
      if (relativePath == '..' || relativePath.startsWith('..${path.separator}')) {
        _logger.w('Rejected file path outside output directory');
        return;
      }
      final file = File(filePath);
      await file.parent.create(recursive: true);
      final expectedChunkSize = chunkIndex == session.totalChunks - 1
          ? (session.fileSize - (chunkIndex * CHUNK_SIZE)).clamp(0, CHUNK_SIZE)
          : CHUNK_SIZE;
      if (chunkData.length != expectedChunkSize) {
        _logger.w('Invalid chunk size ${chunkData.length}, expected $expectedChunkSize');
        return;
      }
      final raf = await file.open(mode: FileMode.write);
      await raf.setPosition(chunkIndex * CHUNK_SIZE);
      await raf.writeFrom(chunkData);
      await raf.close();

      // Update session
      received.add(chunkIndex);
      final newReceivedChunks = received.length;
      final progress = (newReceivedChunks / session.totalChunks).clamp(0.0, 1.0);
      final isComplete = newReceivedChunks == session.totalChunks;

      final updatedSession = FileTransferSession(
        sessionId: session.sessionId,
        fileName: session.fileName,
        fileSize: session.fileSize,
        senderDeviceId: session.senderDeviceId,
        receiverDeviceId: session.receiverDeviceId,
        totalChunks: session.totalChunks,
        receivedChunks: newReceivedChunks,
        progress: progress,
        isComplete: isComplete,
        isFailed: false,
      );

      _transfers[sessionId] = updatedSession;
      _notifyTransfer(updatedSession);

      _logger.d('Chunk received: $chunkIndex/$totalChunks (${(progress * 100).toStringAsFixed(1)}%)');

      if (isComplete) {
        final expectedHash = _expectedHashes[sessionId];
        if (expectedHash != null) {
          final actualHash = sha256.convert(await file.readAsBytes()).toString();
          if (actualHash != expectedHash) {
            _logger.e('File integrity check failed for $fileName');
            await cancelTransfer(sessionId);
            return;
          }
        }
        _logger.i('File transfer complete: $safeFileName');
      }
    } catch (e) {
      _logger.e('Failed to handle file chunk: $e');
    }
  }

  /// Cancel transfer
  Future<void> cancelTransfer(String sessionId) async {
    try {
      final session = _transfers[sessionId];
      if (session != null) {
        final failedSession = FileTransferSession(
          sessionId: session.sessionId,
          fileName: session.fileName,
          fileSize: session.fileSize,
          senderDeviceId: session.senderDeviceId,
          receiverDeviceId: session.receiverDeviceId,
          totalChunks: session.totalChunks,
          receivedChunks: session.receivedChunks,
          progress: session.progress,
          isComplete: false,
          isFailed: true,
        );

        _transfers[sessionId] = failedSession;
        _notifyTransfer(failedSession);
        _logger.i('Transfer cancelled: $sessionId');
      }
    } catch (e) {
      _logger.e('Error cancelling transfer: $e');
    }
  }

  /// Get transfer session
  FileTransferSession? getTransfer(String sessionId) {
    return _transfers[sessionId];
  }

  /// Get all transfers
  List<FileTransferSession> getAllTransfers() {
    return _transfers.values.toList();
  }

  /// Add transfer callback
  void addCallback(FileTransferCallback callback) {
    _callbacks.add(callback);
  }

  /// Remove transfer callback
  void removeCallback(FileTransferCallback callback) {
    _callbacks.remove(callback);
  }

  /// Notify callbacks
  void _notifyTransfer(FileTransferSession session) {
    for (final callback in _callbacks) {
      try {
        callback(session);
      } catch (e) {
        _logger.e('Error in transfer callback: $e');
      }
    }
  }

  /// Clean completed transfers
  void cleanupCompletedTransfers() {
    final toRemove = _transfers.entries
        .where((e) => e.value.isComplete || e.value.isFailed)
        .map((e) => e.key)
        .toList();

    for (final sessionId in toRemove) {
      _transfers.remove(sessionId);
      _receivedChunkIndexes.remove(sessionId);
      _expectedHashes.remove(sessionId);
    }

    _logger.d('Cleaned up ${toRemove.length} completed transfers');
  }

  /// Get statistics
  Map<String, dynamic> getStats() {
    final active = _transfers.values.where((t) => !t.isComplete && !t.isFailed);
    final completed = _transfers.values.where((t) => t.isComplete);
    final failed = _transfers.values.where((t) => t.isFailed);

    return {
      'active': active.length,
      'completed': completed.length,
      'failed': failed.length,
      'totalTransferred': active.fold<int>(0, (sum, t) => sum + (t.totalChunks == 0 ? 0 : (t.fileSize * t.receivedChunks ~/ t.totalChunks))),
    };
  }
}
