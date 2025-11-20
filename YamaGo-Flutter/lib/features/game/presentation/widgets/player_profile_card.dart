import 'package:flutter/material.dart';
import '../../domain/player.dart';

class PlayerProfileCard extends StatelessWidget {
  const PlayerProfileCard({
    super.key,
    required this.player,
    required this.gameId,
  });

  final Player player;
  final String gameId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'あなたのプロフィール',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildRow(theme, 'ゲームID', gameId),
            _buildRow(theme, 'ニックネーム', player.nickname),
            _buildRow(theme, '役割', _roleLabel(player.role)),
            _buildRow(theme, '状態', _statusLabel(player.status)),
            _buildRow(theme, 'ステータス', player.isActive ? '参加中' : '離脱'),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _roleLabel(PlayerRole role) {
    return role == PlayerRole.oni ? '鬼' : '逃走者';
  }

  String _statusLabel(PlayerStatus status) {
    switch (status) {
      case PlayerStatus.active:
        return 'アクティブ';
      case PlayerStatus.downed:
        return 'ダウン中';
      case PlayerStatus.eliminated:
        return '離脱';
    }
  }
}
