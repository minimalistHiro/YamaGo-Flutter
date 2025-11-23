import 'package:cloud_firestore/cloud_firestore.dart';

enum GameEventType { rescue, capture, unknown }

class GameEvent {
  const GameEvent({
    required this.id,
    required this.type,
    required this.createdAt,
    this.actorUid,
    this.actorName,
    this.targetUid,
    this.targetName,
  });

  final String id;
  final GameEventType type;
  final DateTime? createdAt;
  final String? actorUid;
  final String? actorName;
  final String? targetUid;
  final String? targetName;

  factory GameEvent.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdAt = data['createdAt'] ?? data['at'];
    DateTime? createdAtDate;
    if (createdAt is Timestamp) {
      createdAtDate = createdAt.toDate();
    } else if (createdAt is DateTime) {
      createdAtDate = createdAt;
    }
    final actorUid =
        data['actorUid'] as String? ?? data['rescuerUid'] as String?;
    final actorName =
        data['actorName'] as String? ?? data['rescuerName'] as String?;
    final targetUid =
        data['targetUid'] as String? ?? data['victimUid'] as String?;
    final targetName =
        data['targetName'] as String? ?? data['victimName'] as String?;
    return GameEvent(
      id: doc.id,
      type: _parseType(data['type'] as String?),
      createdAt: createdAtDate,
      actorUid: actorUid,
      actorName: actorName,
      targetUid: targetUid,
      targetName: targetName,
    );
  }

  static GameEventType _parseType(String? type) {
    switch (type) {
      case 'rescue':
        return GameEventType.rescue;
      case 'capture':
        return GameEventType.capture;
      default:
        return GameEventType.unknown;
    }
  }
}
