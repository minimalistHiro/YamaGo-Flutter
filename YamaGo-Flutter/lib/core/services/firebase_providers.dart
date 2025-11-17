import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../firebase_options.dart';

/// Initializes Firebase once and exposes strongly typed providers.
final firebaseAppProvider = FutureProvider<FirebaseApp>((ref) async {
  return Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
});

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  ref.watch(firebaseAppProvider);
  return FirebaseAuth.instance;
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  ref.watch(firebaseAppProvider);
  return FirebaseFirestore.instance;
});

final firebaseStorageProvider = Provider<FirebaseStorage>((ref) {
  ref.watch(firebaseAppProvider);
  return FirebaseStorage.instance;
});
