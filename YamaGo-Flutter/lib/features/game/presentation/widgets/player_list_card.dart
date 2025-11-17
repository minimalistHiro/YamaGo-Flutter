import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/player.dart';
import '../../../game/application/player_providers.dart';
import '../../../game/data/player_repository.dart';
import '../../../game/data/game_repository.dart';

class PlayerListCard extends ConsumerWidget {
  const PlayerListCard({
    super.key,
    required this.gameId,
    required this.canManage,
    required this.ownerUid,
    required this.currentUid,
  });

  final String gameId;
  final bool canManage;
  final String ownerUid;
  final String currentUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playersState = ref.watch(playersStreamProvider(gameId));

    return playersState.when(
      data: (players) {
        if (players.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('まだ参加者がいません'),
            ),
          );
        }
        return Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '参加者一覧',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              ...players.map(
                (player) => _PlayerListTile(
                  player: player,
                  gameId: gameId,
                  canManage: canManage,
                  ownerUid: ownerUid,
                  currentUid: currentUid,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('参加者一覧の取得に失敗しました: $error'),
        ),
      ),
    );
  }
}

class _PlayerListTile extends ConsumerWidget {
  const _PlayerListTile({
    required this.player,
    required this.gameId,
    required this.canManage,
    required this.ownerUid,
    required this.currentUid,
  });

  final Player player;
  final String gameId;
  final bool canManage;
  final String ownerUid;
  final String currentUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isSelf = currentUid == player.uid;
    final isOwnerRow = player.uid == ownerUid;
    final repo = ref.watch(playerRepositoryProvider);
    final gameRepo = ref.watch(gameRepositoryProvider);

    return ListTile(
      leading: Icon(
        player.role == PlayerRole.oni ? Icons.whatshot : Icons.directions_run,
        color: player.role == PlayerRole.oni ? Colors.redAccent : Colors.green,
      ),
      title: Text(player.nickname),
      subtitle: Text(_statusText(player)),
      trailing: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            player.role == PlayerRole.oni ? '鬼' : '逃走者',
            style: theme.textTheme.labelMedium,
          ),
          if (isOwnerRow)
            Chip(
              label: Text(
                'オーナー',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onPrimary),
              ),
              backgroundColor: theme.colorScheme.primary,
            ),
          if (canManage && !isSelf)
            PopupMenuButton<String>(
              onSelected: (value) async {
                switch (value) {
                  case 'toggleActive':
                    await repo.setPlayerActive(
                      gameId: gameId,
                      uid: player.uid,
                      isActive: !player.isActive,
                    );
                    break;
                  case 'toggleRole':
                    final newRole = player.role == PlayerRole.oni
                        ? PlayerRole.runner
                        : PlayerRole.oni;
                    await repo.updatePlayerRole(
                      gameId: gameId,
                      uid: player.uid,
                      role: newRole,
                    );
                    break;
                  case 'transferOwner':
                    final confirmed = await _confirmAction(
                      context,
                      title: 'オーナー権限を譲渡',
                      message: '${player.nickname} にオーナーを移譲します。よろしいですか？',
                    );
                    if (confirmed == true) {
                      await gameRepo.updateOwner(
                        gameId: gameId,
                        newOwnerUid: player.uid,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${player.nickname} に権限を譲渡しました'),
                          ),
                        );
                      }
                    }
                    break;
                  case 'kick':
                    final confirmed = await _confirmAction(
                      context,
                      title: 'プレイヤーを退出させる',
                      message: '${player.nickname} をこのゲームから退出させます。よろしいですか？',
                    );
                    if (confirmed == true) {
                      await repo.deletePlayer(
                        gameId: gameId,
                        uid: player.uid,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${player.nickname} を退出させました'),
                          ),
                        );
                      }
                    }
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'toggleActive',
                  child: Text(
                    player.isActive ? '表示を停止（離脱扱い）' : '再表示（参加中に戻す）',
                  ),
                ),
                PopupMenuItem(
                  value: 'toggleRole',
                  child: Text(
                    player.role == PlayerRole.oni ? '逃走者に変更' : '鬼に変更',
                  ),
                ),
                const PopupMenuItem(
                  value: 'kick',
                  child: Text('このプレイヤーを退出'),
                ),
                if (!isOwnerRow)
                  const PopupMenuItem(
                    value: 'transferOwner',
                    child: Text('このプレイヤーにオーナー権限を譲渡'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  String _statusText(Player player) {
    if (!player.isActive) return '離脱';
    switch (player.status) {
      case PlayerStatus.active:
        return 'アクティブ';
      case PlayerStatus.downed:
        return 'ダウン中';
      case PlayerStatus.eliminated:
        return '脱落';
    }
  }

  Future<bool?> _confirmAction(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('実行'),
          ),
        ],
      ),
    );
  }
}
