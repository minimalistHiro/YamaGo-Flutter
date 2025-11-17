import 'package:cloud_firestore/cloud_firestore.dart';

enum ChatRole { oni, runner }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.uid,
    required this.nickname,
    required this.message,
    required this.timestamp,
    required this.role,
  });

  final String id;
  final String uid;
  final String nickname;
  final String message;
  final DateTime timestamp;
  final ChatRole role;

  static ChatMessage fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required ChatRole role,
  }) {
    final data = doc.data() ?? {};
    return ChatMessage(
      id: doc.id,
      uid: data['uid'] as String? ?? '',
      nickname: data['nickname'] as String? ?? 'No name',
      message: data['message'] as String? ?? '',
      timestamp: _toDate(data['timestamp']) ?? DateTime.now(),
      role: role,
    );
  }
}

DateTime? _toDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
