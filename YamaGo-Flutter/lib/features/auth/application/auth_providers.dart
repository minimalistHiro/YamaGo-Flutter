import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_providers.dart';

/// Exposes FirebaseAuth state changes to the UI layer.
final authStateStreamProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return auth.authStateChanges();
});

/// Ensures a signed-in Firebase user (anonymous by default).
final ensureAnonymousSignInProvider = FutureProvider<User>((ref) async {
  await ref.watch(firebaseAppProvider.future);
  final auth = ref.read(firebaseAuthProvider);
  final existing = auth.currentUser;
  if (existing != null) {
    return existing;
  }
  final credential = await auth.signInAnonymously();
  final user = credential.user;
  if (user == null) {
    throw StateError('FirebaseAuth returned null user after anonymous sign-in');
  }
  return user;
});
