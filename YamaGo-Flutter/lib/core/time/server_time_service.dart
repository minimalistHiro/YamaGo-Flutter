import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firebase_providers.dart';

class ServerTimeService {
  ServerTimeService(this._firestore);

  final FirebaseFirestore _firestore;
  Duration? _offset;
  Completer<void>? _syncCompleter;

  Duration? get offset => _offset;

  DateTime now() {
    return DateTime.now().add(_offset ?? Duration.zero);
  }

  Future<DateTime> fetchServerTime() async {
    await ensureSynchronized();
    return now();
  }

  Future<void> ensureSynchronized() async {
    if (_offset != null) return;
    await _synchronize();
  }

  Future<void> refresh() async {
    await _synchronize(force: true);
  }

  Future<void> _synchronize({bool force = false}) async {
    if (!force && _offset != null) {
      return;
    }
    final existingCompleter = _syncCompleter;
    if (existingCompleter != null) {
      return existingCompleter.future;
    }
    final completer = Completer<void>();
    _syncCompleter = completer;
    try {
      final docRef =
          _firestore.collection('_meta').doc('server_time_sync_probe');
      final clientSendTime = DateTime.now();
      await docRef.set(
        {'timestamp': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      final snapshot =
          await docRef.get(const GetOptions(source: Source.server));
      final clientReceiveTime = DateTime.now();
      final serverTimestamp = snapshot.data()?['timestamp'];
      if (serverTimestamp is Timestamp) {
        final roundTrip = clientReceiveTime.difference(clientSendTime);
        final midpoint = clientSendTime.add(
          Duration(microseconds: roundTrip.inMicroseconds ~/ 2),
        );
        _offset = serverTimestamp.toDate().difference(midpoint);
      } else {
        debugPrint('ServerTimeService: Missing timestamp in probe document.');
      }
    } catch (error, stackTrace) {
      debugPrint('ServerTimeService: Failed to synchronize time: $error');
      debugPrint('$stackTrace');
      rethrow;
    } finally {
      completer.complete();
      _syncCompleter = null;
    }
  }
}

final serverTimeServiceProvider = Provider<ServerTimeService>((ref) {
  ref.watch(firebaseAppProvider);
  final firestore = FirebaseFirestore.instance;
  return ServerTimeService(firestore);
});
