import 'package:cloud_firestore/cloud_firestore.dart';

enum GameEventType { rescue, unknown }

class GameEvent {
  const GameEvent({
    required this.id,
    required this.type,
    required this.createdAt,
    this.rescuerUid,
    this.rescuerName,
    this.victimUid,
    this.victimName,
  });

  final String id;
  final GameEventType type;
  final DateTime? createdAt;
  final String? rescuerUid;
  final String? rescuerName;
  final String? victimUid;
  final String? victimName;

  factory GameEvent.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdAt = data['createdAt'];
    DateTime? createdAtDate;
    if (createdAt is Timestamp) {
      createdAtDate = createdAt.toDate();
    } else if (createdAt is DateTime) {
      createdAtDate = createdAt;
    }
    return GameEvent(
      id: doc.id,
      type: _parseType(data['type'] as String?),
      createdAt: createdAtDate,
      rescuerUid: data['rescuerUid'] as String?,
      rescuerName: data['rescuerName'] as String?,
      victimUid: data['victimUid'] as String?,
      victimName: data['victimName'] as String?,
    );
  }

  static GameEventType _parseType(String? type) {
    switch (type) {
      case 'rescue':
        return GameEventType.rescue;
      default:
        return GameEventType.unknown;
    }
  }
}
