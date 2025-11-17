import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/player.dart';

class PlayerHud extends StatelessWidget {
  const PlayerHud({
    super.key,
    required this.playersState,
  });

  final AsyncValue<List<Player>> playersState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return playersState.when(
      data: (players) {
        final activePlayers = players.where((p) => p.isActive).toList();
        final oniCount =
            activePlayers.where((p) => p.role == PlayerRole.oni).length;
        final runnerCount = activePlayers.length - oniCount;
        final downedCount =
            activePlayers.where((p) => p.status == PlayerStatus.downed).length;
        return Card(
          color: theme.colorScheme.surface.withOpacity(0.9),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'プレイヤー状況',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                _buildStatRow(theme, 'オンライン', activePlayers.length),
                _buildStatRow(theme, '鬼', oniCount),
                _buildStatRow(theme, '逃走者', runnerCount),
                _buildStatRow(theme, 'ダウン中', downedCount),
              ],
            ),
          ),
        );
      },
      loading: () => const _HudLoading(),
      error: (error, _) => _HudError(message: error.toString()),
    );
  }

  Widget _buildStatRow(ThemeData theme, String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(
            '$value',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _HudLoading extends StatelessWidget {
  const _HudLoading();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('プレイヤーを取得中...'),
          ],
        ),
      ),
    );
  }
}

class _HudError extends StatelessWidget {
  const _HudError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'プレイヤー情報の取得に失敗しました\n$message',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.redAccent),
        ),
      ),
    );
  }
}
