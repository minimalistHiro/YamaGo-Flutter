import 'package:cloud_firestore/cloud_firestore.dart';

enum PinStatus { pending, clearing, cleared }

class PinPoint {
  const PinPoint({
    required this.id,
    required this.lat,
    required this.lng,
    required this.type,
    required this.status,
    required this.cleared,
    required this.createdAt,
  });

  final String id;
  final double lat;
  final double lng;
  final String type;
  final PinStatus status;
  final bool cleared;
  final DateTime? createdAt;

  PinPoint copyWith({
    double? lat,
    double? lng,
    String? type,
    PinStatus? status,
    bool? cleared,
    DateTime? createdAt,
  }) {
    return PinPoint(
      id: id,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      type: type ?? this.type,
      status: status ?? this.status,
      cleared: cleared ?? this.cleared,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static PinPoint fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final lat = (data['lat'] as num?)?.toDouble() ?? 0;
    final lng = (data['lng'] as num?)?.toDouble() ?? 0;
    final type = data['type'] as String? ?? 'yellow';
    final status = _parseStatus(data['status'] as String?);
    final cleared = data['cleared'] as bool? ?? status == PinStatus.cleared;
    final createdAt = _toDate(data['createdAt']);
    return PinPoint(
      id: doc.id,
      lat: lat,
      lng: lng,
      type: type,
      status: status,
      cleared: cleared,
      createdAt: createdAt,
    );
  }
}

PinStatus _parseStatus(String? value) {
  switch (value) {
    case 'clearing':
      return PinStatus.clearing;
    case 'cleared':
      return PinStatus.cleared;
    case 'pending':
    default:
      return PinStatus.pending;
  }
}

DateTime? _toDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
