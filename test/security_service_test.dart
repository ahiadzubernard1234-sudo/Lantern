import 'package:flutter_test/flutter_test.dart';
import 'package:lantern/core/network/v2/models/network_models.dart';
import 'package:lantern/core/network/v2/services/security_service.dart';

void main() {
  test('SecurityService rejects replayed message IDs and future timestamps', () async {
    final security = SecurityService();
    await security.initialize(deviceId: 'local');
    final now = DateTime.now().millisecondsSinceEpoch;
    final message = NetworkMessage(
      id: 'unique-1',
      senderId: 'remote',
      receiverId: 'local',
      type: MessageType.text,
      content: 'hello',
      timestamp: now,
    );

    expect(security.validatePacket(message), isTrue);
    expect(security.validatePacket(message), isFalse);

    final futureMessage = NetworkMessage(
      id: 'unique-2',
      senderId: 'remote',
      receiverId: 'local',
      type: MessageType.text,
      content: 'future',
      timestamp: now + 301000,
    );
    expect(security.validatePacket(futureMessage), isFalse);
  });
}
