import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_providers.dart';
import '../domain/chat_message.dart';

class ChatRepository {
  ChatRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _messagesCollection(
    String gameId,
    ChatChannel channel,
  ) {
    final collectionKey = switch (channel) {
      ChatChannel.oni => 'messages_oni',
      ChatChannel.runner => 'messages_runner',
      ChatChannel.general => 'messages_general',
    };
    return _firestore.collection('games').doc(gameId).collection(collectionKey);
  }

  Stream<List<ChatMessage>> watchMessages(String gameId, ChatChannel channel) {
    return _messagesCollection(gameId, channel)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(
              (doc) => ChatMessage.fromFirestore(
                doc,
                channel: channel,
              ),
            )
            .toList());
  }

  Future<void> sendMessage({
    required String gameId,
    required ChatChannel channel,
    required String uid,
    required String nickname,
    required String message,
  }) {
    final roleValue = switch (channel) {
      ChatChannel.oni => 'oni',
      ChatChannel.runner => 'runner',
      ChatChannel.general => 'general',
    };
    return _messagesCollection(gameId, channel).add({
      'uid': uid,
      'nickname': nickname,
      'message': message,
      'timestamp': FieldValue.serverTimestamp(),
      'role': roleValue,
      'channel': roleValue,
      'type': 'user',
    });
  }
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return ChatRepository(firestore);
});
