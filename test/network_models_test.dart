import 'package:flutter_test/flutter_test.dart';
import 'package:lantern/core/network/v2/models/network_models.dart';

void main() {
  test('NetworkMessage round trips through JSON encoding', () {
    const original = NetworkMessage(
      id: 'id-1',
      senderId: 'sender',
      receiverId: 'receiver',
      type: MessageType.text,
      content: 'hello',
      timestamp: 123456,
      metadata: {'ok': true},
    );

    final decoded = NetworkMessage.decode(original.encode());
    expect(decoded, equals(original));
  });
}
