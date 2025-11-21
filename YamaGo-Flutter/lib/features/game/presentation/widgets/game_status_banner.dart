import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/firebase_providers.dart';
import '../../domain/game.dart';
import '../../../game/application/game_control_controller.dart';

class GameStatusBanner extends ConsumerWidget {
  const GameStatusBanner({
    super.key,
    required this.gameState,
    required this.gameId,
  });

  final AsyncValue<Game?> gameState;
  final String gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return gameState.when(
      data: (game) {
        if (game == null) {
          return const _BannerCard(
            title: 'ゲーム情報が見つかりません',
            subtitle: '正しいゲームIDで再参加してください',
          );
        }
        final auth = ref.watch(firebaseAuthProvider);
        final user = auth.currentUser;
        final isOwner = user?.uid == game.ownerUid;
        final actionWidgets =
            isOwner ? _buildActions(context, ref, game) : const <Widget>[];

        return _BannerCard(
          title: _titleForStatus(game.status),
          subtitle: _subtitleForGame(game),
          actions: actionWidgets.isEmpty ? null : actionWidgets,
        );
      },
      loading: () => const _BannerCard(
        title: 'ゲーム情報を読み込み中',
        subtitle: 'しばらくお待ちください',
      ),
      error: (error, _) => _BannerCard(
        title: 'ゲーム情報の取得に失敗しました',
        subtitle: error.toString(),
      ),
    );
  }

  String _titleForStatus(GameStatus status) {
    switch (status) {
      case GameStatus.pending:
        return '待機中';
      case GameStatus.countdown:
        return 'カウントダウン中';
      case GameStatus.running:
        return 'ゲーム進行中';
      case GameStatus.ended:
        return 'ゲーム終了';
    }
  }

  String _subtitleForGame(Game game) {
    switch (game.status) {
      case GameStatus.pending:
        return '参加者を待っています';
      case GameStatus.countdown:
        return 'まもなく開始します';
      case GameStatus.running:
        final remaining = game.runningRemainingSeconds;
        if (remaining != null) {
          return '残り時間\n${_formatHms(remaining)}';
        }
        final elapsed = game.runningElapsedSeconds;
        if (elapsed == null) return '位置情報を共有しましょう';
        return '経過時間 ${_formatSeconds(elapsed)}';
      case GameStatus.ended:
        return '結果画面で振り返りましょう';
    }
  }

  String _formatSeconds(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes > 0) {
      return '$minutes分${secs.toString().padLeft(2, '0')}秒';
    }
    return '$secs秒';
  }

  String _formatHms(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final hours = safeSeconds ~/ 3600;
    final minutes = (safeSeconds % 3600) ~/ 60;
    final secs = safeSeconds % 60;
    return '${hours}時間'
        '${minutes.toString().padLeft(2, '0')}分'
        '${secs.toString().padLeft(2, '0')}秒';
  }

  List<Widget> _buildActions(
    BuildContext context,
    WidgetRef ref,
    Game game,
  ) {
    final controller = ref.read(gameControlControllerProvider);
    switch (game.status) {
      case GameStatus.pending:
      case GameStatus.ended:
        return const [];
      case GameStatus.countdown:
        return const [];
      case GameStatus.running:
        return const [];
    }
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    required this.title,
    required this.subtitle,
    this.actions,
  });

  final String title;
  final String subtitle;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surface.withOpacity(0.9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall,
            ),
            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions!
                    .map((action) => Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: action,
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
