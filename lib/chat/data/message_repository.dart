import '../models/conversation.dart';
import '../models/message.dart';

abstract interface class MessageRepository {
  Future<List<Conversation>> loadConversations();

  Future<List<ChatMessage>> loadMessages(String conversationId);

  Future<ChatMessage> sendText({
    required String conversationId,
    required String clientMessageId,
    required String text,
    String? replyToMessageId,
  });
}

class DemoMessageRepository implements MessageRepository {
  DemoMessageRepository() : _createdAt = DateTime.now();

  final DateTime _createdAt;

  @override
  Future<List<Conversation>> loadConversations() async {
    return [
      Conversation(
        id: 'conv-design',
        kind: ConversationKind.group,
        title: '产品设计组',
        subtitle: '6 人在线',
        participantIds: const ['self', 'lin', 'zhou'],
        lastMessagePreview: '林晓：交互稿已经更新',
        lastMessageAt: _createdAt.subtract(const Duration(minutes: 8)),
        unreadCount: 3,
        isPinned: true,
        encryptionState: ConversationEncryptionState.unavailable,
        createdAt: _createdAt.subtract(const Duration(days: 90)),
        updatedAt: _createdAt.subtract(const Duration(minutes: 8)),
      ),
      Conversation(
        id: 'conv-friend',
        kind: ConversationKind.direct,
        title: '周岚',
        subtitle: '在线',
        participantIds: const ['self', 'zhou'],
        lastMessagePreview: '明天上午见',
        lastMessageAt: _createdAt.subtract(const Duration(hours: 2)),
        encryptionState: ConversationEncryptionState.unavailable,
        createdAt: _createdAt.subtract(const Duration(days: 30)),
        updatedAt: _createdAt.subtract(const Duration(hours: 2)),
      ),
      Conversation(
        id: 'conv-family',
        kind: ConversationKind.group,
        title: '家人',
        subtitle: '4 位成员',
        participantIds: const ['self', 'member-a', 'member-b'],
        lastMessagePreview: '[语音] 00:18',
        lastMessageAt: _createdAt.subtract(const Duration(days: 1)),
        isMuted: true,
        encryptionState: ConversationEncryptionState.unavailable,
        createdAt: _createdAt.subtract(const Duration(days: 300)),
        updatedAt: _createdAt.subtract(const Duration(days: 1)),
      ),
    ];
  }

  @override
  Future<List<ChatMessage>> loadMessages(String conversationId) async {
    return [
      ChatMessage(
        id: 'msg-1-$conversationId',
        conversationId: conversationId,
        senderId: 'other',
        clientMessageId: 'client-1-$conversationId',
        kind: ChatMessageKind.text,
        status: ChatMessageStatus.read,
        encryptionState: MessageEncryptionState.plain,
        text: '今晚的版本已经可以体验了，你方便帮忙看看吗？',
        createdAt: _createdAt.subtract(const Duration(minutes: 18)),
      ),
      ChatMessage(
        id: 'msg-2-$conversationId',
        conversationId: conversationId,
        senderId: 'self',
        clientMessageId: 'client-2-$conversationId',
        kind: ChatMessageKind.text,
        status: ChatMessageStatus.read,
        encryptionState: MessageEncryptionState.plain,
        text: '可以，我先检查消息和通话流程。',
        createdAt: _createdAt.subtract(const Duration(minutes: 15)),
      ),
      ChatMessage(
        id: 'msg-3-$conversationId',
        conversationId: conversationId,
        senderId: 'other',
        clientMessageId: 'client-3-$conversationId',
        kind: ChatMessageKind.audio,
        status: ChatMessageStatus.delivered,
        encryptionState: MessageEncryptionState.plain,
        text: '18',
        createdAt: _createdAt.subtract(const Duration(minutes: 8)),
      ),
    ];
  }

  @override
  Future<ChatMessage> sendText({
    required String conversationId,
    required String clientMessageId,
    required String text,
    String? replyToMessageId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 260));
    return ChatMessage(
      id: 'msg-$clientMessageId',
      conversationId: conversationId,
      senderId: 'self',
      clientMessageId: clientMessageId,
      kind: ChatMessageKind.text,
      status: ChatMessageStatus.sent,
      encryptionState: MessageEncryptionState.plain,
      text: text,
      replyToMessageId: replyToMessageId,
      createdAt: DateTime.now(),
    );
  }
}
