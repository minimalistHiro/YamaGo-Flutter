import 'package:cloud_firestore/cloud_firestore.dart';

enum GameStatus { pending, countdown, running, ended }

enum GameEndResult { runnerVictory, oniVictory, draw }

class Game {
  const Game({
    required this.id,
    required this.status,
    required this.ownerUid,
    this.startAt,
    this.countdownStartAt,
    this.countdownEndAt,
    this.countdownDurationSec,
    this.generatorClearDurationSec,
    this.pinCount,
    this.captureRadiusM,
    this.runnerSeeKillerRadiusM,
    this.runnerSeeRunnerRadiusM,
    this.runnerSeeGeneratorRadiusM,
    this.killerDetectRunnerRadiusM,
    this.killerSeeGeneratorRadiusM,
    this.gameDurationSec,
    this.endResult,
    this.timedEventActive = false,
    this.timedEventActiveStartedAt,
    this.timedEventActiveDurationSec,
    this.timedEventActiveQuarter,
  });

  final String id;
  final GameStatus status;
  final String ownerUid;
  final DateTime? startAt;
  final DateTime? countdownStartAt;
  final DateTime? countdownEndAt;
  final int? countdownDurationSec;
  final int? generatorClearDurationSec;
  final int? pinCount;
  final int? captureRadiusM;
  final int? runnerSeeKillerRadiusM;
  final int? runnerSeeRunnerRadiusM;
  final int? runnerSeeGeneratorRadiusM;
  final int? killerDetectRunnerRadiusM;
  final int? killerSeeGeneratorRadiusM;
  final int? gameDurationSec;
  final GameEndResult? endResult;
  final bool timedEventActive;
  final DateTime? timedEventActiveStartedAt;
  final int? timedEventActiveDurationSec;
  final int? timedEventActiveQuarter;

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

  int? get runningRemainingSeconds {
    if (status != GameStatus.running ||
        startAt == null ||
        gameDurationSec == null) {
      return null;
    }
    final elapsed = DateTime.now().difference(startAt!).inSeconds;
    final remaining = gameDurationSec! - elapsed;
    if (remaining < 0) return 0;
    return remaining;
  }

  static Game fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Game(
      id: doc.id,
      status: _parseStatus(data['status'] as String?),
      ownerUid: data['ownerUid'] as String? ?? '',
      startAt: _toDate(data['startAt']),
      countdownStartAt: _toDate(data['countdownStartAt']),
      countdownEndAt: _toDate(data['countdownEndAt']),
      countdownDurationSec: (data['countdownDurationSec'] as num?)?.toInt(),
      generatorClearDurationSec:
          (data['generatorClearDurationSec'] as num?)?.toInt(),
      pinCount: (data['pinCount'] as num?)?.toInt(),
      captureRadiusM: (data['captureRadiusM'] as num?)?.toInt(),
      runnerSeeKillerRadiusM: (data['runnerSeeKillerRadiusM'] as num?)?.toInt(),
      runnerSeeRunnerRadiusM: (data['runnerSeeRunnerRadiusM'] as num?)?.toInt(),
      runnerSeeGeneratorRadiusM:
          (data['runnerSeeGeneratorRadiusM'] as num?)?.toInt(),
      killerDetectRunnerRadiusM:
          (data['killerDetectRunnerRadiusM'] as num?)?.toInt(),
      killerSeeGeneratorRadiusM:
          (data['killerSeeGeneratorRadiusM'] as num?)?.toInt(),
      gameDurationSec: (data['gameDurationSec'] as num?)?.toInt(),
      endResult: parseGameEndResult(data['endResult'] as String?),
      timedEventActive: data['timedEventActive'] as bool? ?? false,
      timedEventActiveStartedAt: _toDate(data['timedEventActiveStartedAt']),
      timedEventActiveDurationSec:
          (data['timedEventActiveDurationSec'] as num?)?.toInt(),
      timedEventActiveQuarter:
          (data['timedEventActiveQuarter'] as num?)?.toInt(),
    );
  }

  bool isTimedEventActive({DateTime? referenceTime}) {
    if (!timedEventActive) return false;
    final startedAt = timedEventActiveStartedAt;
    final durationSec = timedEventActiveDurationSec;
    if (startedAt == null || durationSec == null) {
      return timedEventActive;
    }
    final now = referenceTime ?? DateTime.now();
    final endsAt = startedAt.add(Duration(seconds: durationSec));
    return now.isBefore(endsAt);
  }

  int? timedEventRemainingSeconds({DateTime? referenceTime}) {
    if (!timedEventActive) return null;
    final startedAt = timedEventActiveStartedAt;
    final durationSec = timedEventActiveDurationSec;
    if (startedAt == null || durationSec == null) {
      return null;
    }
    final now = referenceTime ?? DateTime.now();
    final endsAt = startedAt.add(Duration(seconds: durationSec));
    final remaining = endsAt.difference(now).inSeconds;
    if (remaining <= 0) {
      return 0;
    }
    return remaining;
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

GameEndResult? parseGameEndResult(String? value) {
  switch (value) {
    case 'runner_victory':
      return GameEndResult.runnerVictory;
    case 'oni_victory':
      return GameEndResult.oniVictory;
    case 'draw':
      return GameEndResult.draw;
    default:
      return null;
  }
}

String gameEndResultToRawValue(GameEndResult result) {
  switch (result) {
    case GameEndResult.runnerVictory:
      return 'runner_victory';
    case GameEndResult.oniVictory:
      return 'oni_victory';
    case GameEndResult.draw:
      return 'draw';
  }
}
