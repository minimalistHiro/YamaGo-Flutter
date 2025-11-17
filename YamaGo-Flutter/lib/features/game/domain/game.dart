import 'package:cloud_firestore/cloud_firestore.dart';

enum GameStatus { pending, countdown, running, ended }

class Game {
  const Game({
    required this.id,
    required this.status,
    required this.ownerUid,
    this.startAt,
    this.countdownStartAt,
    this.countdownDurationSec,
    this.pinCount,
  });

  final String id;
  final GameStatus status;
  final String ownerUid;
  final DateTime? startAt;
  final DateTime? countdownStartAt;
  final int? countdownDurationSec;
  final int? pinCount;

  int? get countdownRemainingSeconds {
    if (status != GameStatus.countdown ||
        countdownStartAt == null ||
        countdownDurationSec == null) {
      return null;
    }
    final elapsed = DateTime.now()
        .difference(countdownStartAt!)
        .inSeconds
        .clamp(0, countdownDurationSec!);
    return (countdownDurationSec! - elapsed).clamp(0, countdownDurationSec!);
  }

  int? get runningElapsedSeconds {
    if (status != GameStatus.running || startAt == null) return null;
    return DateTime.now().difference(startAt!).inSeconds;
  }

  static Game fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Game(
      id: doc.id,
      status: _parseStatus(data['status'] as String?),
      ownerUid: data['ownerUid'] as String? ?? '',
      startAt: _toDate(data['startAt']),
      countdownStartAt: _toDate(data['countdownStartAt']),
      countdownDurationSec: (data['countdownDurationSec'] as num?)?.toInt(),
      pinCount: (data['pinCount'] as num?)?.toInt(),
    );
  }
}

GameStatus _parseStatus(String? value) {
  switch (value) {
    case 'countdown':
      return GameStatus.countdown;
    case 'running':
      return GameStatus.running;
    case 'ended':
      return GameStatus.ended;
    default:
      return GameStatus.pending;
  }
}

DateTime? _toDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
