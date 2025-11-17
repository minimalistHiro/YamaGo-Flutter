import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_providers.dart';
import '../domain/chat_message.dart';

class ChatRepository {
  ChatRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _messagesCollection(
    String gameId,
    ChatRole role,
  ) {
    final roleKey = role == ChatRole.oni ? 'messages_oni' : 'messages_runner';
    return _firestore.collection('games').doc(gameId).collection(roleKey);
  }

  Stream<List<ChatMessage>> watchMessages(String gameId, ChatRole role) {
    return _messagesCollection(gameId, role)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ChatMessage.fromFirestore(doc, role: role))
            .toList());
  }

  Future<void> sendMessage({
    required String gameId,
    required ChatRole role,
    required String uid,
    required String nickname,
    required String message,
  }) {
    return _messagesCollection(gameId, role).add({
      'uid': uid,
      'nickname': nickname,
      'message': message,
      'timestamp': FieldValue.serverTimestamp(),
      'role': role == ChatRole.oni ? 'oni' : 'runner',
      'type': 'user',
    });
  }
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return ChatRepository(firestore);
});
