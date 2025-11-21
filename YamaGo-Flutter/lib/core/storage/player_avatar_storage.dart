import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firebase_providers.dart';

/// Handles uploading player avatars to Firebase Storage.
class PlayerAvatarStorage {
  PlayerAvatarStorage(this._storage);

  final FirebaseStorage _storage;

  Future<String> uploadAvatar({
    required String uid,
    required Uint8List bytes,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage
        .ref()
        .child('avatars')
        .child(uid)
        .child('$timestamp.jpg');
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      cacheControl: 'public,max-age=604800',
    );
    await ref.putData(bytes, metadata);
    return ref.getDownloadURL();
  }

  Future<void> deleteAvatarByUrl(String avatarUrl) async {
    final ref = _storage.refFromURL(avatarUrl);
    await ref.delete();
  }
}

final playerAvatarStorageProvider =
    FutureProvider<PlayerAvatarStorage>((ref) async {
  await ref.watch(firebaseAppProvider.future);
  final storage = ref.watch(firebaseStorageProvider);
  return PlayerAvatarStorage(storage);
});
