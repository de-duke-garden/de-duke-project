import 'package:flutter_test/flutter_test.dart';

import 'package:de_duke_mobile/features/chat/data/chat_models.dart';

void main() {
  group('ChatMessage.isSystemMessage', () {
    test('is true for messageType "system"', () {
      final message = ChatMessage(
        id: 'm1',
        conversationId: 'c1',
        senderId: null,
        senderRole: null,
        messageType: 'system',
        body: 'De-Duke Staff joined to assist',
        deliveryStatus: ChatDeliveryStatus.sent,
        sentAt: DateTime.now(),
      );
      expect(message.isSystemMessage, isTrue);
    });

    test('is false for messageType "text"', () {
      final message = ChatMessage(
        id: 'm2',
        conversationId: 'c1',
        senderId: 'user-1',
        senderRole: 'client',
        messageType: 'text',
        body: 'Hello',
        deliveryStatus: ChatDeliveryStatus.sent,
        sentAt: DateTime.now(),
      );
      expect(message.isSystemMessage, isFalse);
    });
  });

  group('ChatConversation', () {
    test('holds the three participant identifiers from schema.md', () {
      final conversation = ChatConversation(
        id: 'conv-1',
        listingId: 'listing-1',
        clientId: 'user-client',
        propertyManagementId: 'user-pm',
        assignedStaffId: null,
        lastMessageAt: DateTime.utc(2026, 7, 1),
        createdAt: DateTime.utc(2026, 6, 30),
      );

      expect(conversation.clientId, 'user-client');
      expect(conversation.propertyManagementId, 'user-pm');
      expect(conversation.assignedStaffId, isNull);
    });
  });

  group('ChatDeliveryStatus', () {
    test('has exactly the five values defined in schema.md', () {
      expect(
        ChatDeliveryStatus.values.map((v) => v.name).toSet(),
        {'sending', 'sent', 'delivered', 'read', 'failed'},
      );
    });
  });
}
