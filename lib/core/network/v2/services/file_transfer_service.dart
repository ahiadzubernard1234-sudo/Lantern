import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'network_models.dart';

typedef FileTransferCallback = void Function(FileTransferSession session);

class FileTransferService {
  static final FileTransferService _instance = FileTransferService._internal();
  final Logger _logger = Logger();

  final Map<String, FileTransferSession> _transfers = {};
  final List<FileTransferCallback> _callbacks = [];

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
      final totalChunks = (fileSize / CHUNK_SIZE).ceil();

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
      _logger.i('File transfer started: $fileName ($fileSize bytes)');
      _notifyTransfer(session);

      return session;
    } catch (e) {
      _logger.e('Failed to start file transfer: $e');
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

      final sessionId = metadata['sessionId'] as String?;
      final chunkIndex = metadata['chunkIndex'] as int?;
      final fileName = metadata['fileName'] as String?;
      final fileSize = metadata['fileSize'] as int?;
      final totalChunks = metadata['totalChunks'] as int?;

      if (sessionId == null || chunkIndex == null || fileName == null) {
        _logger.w('Invalid file transfer metadata');
        return;
      }

      // Create or get session
      var session = _transfers[sessionId];
      if (session == null) {
        session = FileTransferSession(
          sessionId: sessionId,
          fileName: fileName,
          fileSize: fileSize ?? 0,
          senderDeviceId: message.senderId,
          receiverDeviceId: message.receiverId,
          totalChunks: totalChunks ?? 0,
          receivedChunks: 0,
          progress: 0.0,
          isComplete: false,
          isFailed: false,
        );
        _transfers[sessionId] = session;
      }

      // Decode chunk data
      final chunkData = base64Decode(message.content);

      // Write to file
      final filePath = '$outputDirectory/$fileName';
      final file = File(filePath);
      final raf = await file.open(mode: FileMode.write);
      await raf.setPosition(chunkIndex * CHUNK_SIZE);
      await raf.writeFrom(chunkData);
      await raf.close();

      // Update session
      final newReceivedChunks = session.receivedChunks + 1;
      final progress = (newReceivedChunks / session.totalChunks).clamp(0.0, 1.0);
      final isComplete = newReceivedChunks >= session.totalChunks;

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
        _logger.i('File transfer complete: $fileName');
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
      'totalTransferred': active.fold<int>(0, (sum, t) => sum + (t.fileSize * t.receivedChunks ~/ t.totalChunks)),
    };
  }
}
