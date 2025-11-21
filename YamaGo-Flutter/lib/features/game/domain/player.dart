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
  });

  final String uid;
  final String nickname;
  final PlayerRole role;
  final bool isActive;
  final LatLng? position;
  final DateTime? updatedAt;
  final PlayerStatus status;
  final String? avatarUrl;

  Player copyWith({
    String? nickname,
    PlayerRole? role,
    bool? isActive,
    LatLng? position,
    DateTime? updatedAt,
    PlayerStatus? status,
    String? avatarUrl,
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
