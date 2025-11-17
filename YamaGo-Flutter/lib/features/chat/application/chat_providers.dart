import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../game/domain/player.dart';
import '../data/chat_repository.dart';
import '../domain/chat_message.dart';

final chatMessagesProvider = StreamProvider.family
    .autoDispose<List<ChatMessage>, ({String gameId, PlayerRole role})>(
        (ref, args) {
  final repo = ref.watch(chatRepositoryProvider);
  final chatRole = args.role == PlayerRole.oni ? ChatRole.oni : ChatRole.runner;
  return repo.watchMessages(args.gameId, chatRole);
});
