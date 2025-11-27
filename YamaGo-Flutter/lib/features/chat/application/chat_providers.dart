import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_repository.dart';
import '../domain/chat_message.dart';

final chatMessagesByChannelProvider = StreamProvider.family
    .autoDispose<List<ChatMessage>, ({String gameId, ChatChannel channel})>(
        (ref, args) {
  ref.keepAlive();
  final repo = ref.watch(chatRepositoryProvider);
  return repo.watchMessages(args.gameId, args.channel);
});
