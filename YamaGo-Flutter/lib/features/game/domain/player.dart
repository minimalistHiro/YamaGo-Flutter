import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum PlayerRole { oni, runner }

enum PlayerStatus { active, downed, eliminated }

class Player {
  const Player({
    required this.uid,
    required this.nickname,
    required this.role,
    required this.isActive,
    required this.position,
    required this.updatedAt,
    required this.status,
    this.avatarUrl,
    this.stats = const PlayerStats(),
  });

  final String uid;
  final String nickname;
  final PlayerRole role;
  final bool isActive;
  final LatLng? position;
  final DateTime? updatedAt;
  final PlayerStatus status;
  final String? avatarUrl;
  final PlayerStats stats;

  Player copyWith({
    String? nickname,
    PlayerRole? role,
    bool? isActive,
    LatLng? position,
    DateTime? updatedAt,
    PlayerStatus? status,
    String? avatarUrl,
    PlayerStats? stats,
  }) {
    return Player(
      uid: uid,
      nickname: nickname ?? this.nickname,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      position: position ?? this.position,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      stats: stats ?? this.stats,
    );
  }

  static Player fromFirestore(String uid, Map<String, dynamic> data) {
    final role = (data['role'] as String? ?? 'runner') == 'oni'
        ? PlayerRole.oni
        : PlayerRole.runner;
    final status = _parseStatus(data['status'] as String?);
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    final timestamp = data['updatedAt'];
    DateTime? updatedAt;
    if (timestamp is Timestamp) {
      updatedAt = timestamp.toDate();
    } else if (timestamp is DateTime) {
      updatedAt = timestamp;
    }
    return Player(
      uid: uid,
      nickname: data['nickname'] as String? ?? 'No name',
      role: role,
      isActive: data['active'] as bool? ?? true,
      position: lat != null && lng != null ? LatLng(lat, lng) : null,
      updatedAt: updatedAt,
      status: status,
      avatarUrl: data['avatarUrl'] as String?,
      stats: PlayerStats.fromMap(
        (data['stats'] as Map<String, dynamic>?),
      ),
    );
  }
}

class PlayerStats {
  const PlayerStats({
    this.captures = 0,
    this.capturedTimes = 0,
    this.rescues = 0,
    this.rescuedTimes = 0,
  });

  final int captures;
  final int capturedTimes;
  final int rescues;
  final int rescuedTimes;

  PlayerStats copyWith({
    int? captures,
    int? capturedTimes,
    int? rescues,
    int? rescuedTimes,
  }) {
    return PlayerStats(
      captures: captures ?? this.captures,
      capturedTimes: capturedTimes ?? this.capturedTimes,
      rescues: rescues ?? this.rescues,
      rescuedTimes: rescuedTimes ?? this.rescuedTimes,
    );
  }

  static PlayerStats fromMap(Map<String, dynamic>? data) {
    if (data == null) {
      return const PlayerStats();
    }
    return PlayerStats(
      captures: (data['captures'] as num?)?.toInt() ?? 0,
      capturedTimes: (data['capturedTimes'] as num?)?.toInt() ?? 0,
      rescues: (data['rescues'] as num?)?.toInt() ?? 0,
      rescuedTimes: (data['rescuedTimes'] as num?)?.toInt() ?? 0,
    );
  }
}

PlayerStatus _parseStatus(String? value) {
  switch (value) {
    case 'downed':
      return PlayerStatus.downed;
    case 'eliminated':
      return PlayerStatus.eliminated;
    default:
      return PlayerStatus.active;
  }
}
