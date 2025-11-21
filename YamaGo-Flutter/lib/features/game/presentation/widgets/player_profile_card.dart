import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/player.dart';

class PlayerProfileCard extends StatelessWidget {
  const PlayerProfileCard({
    super.key,
    required this.player,
    required this.gameId,
    this.onEditProfile,
  });

  final Player player;
  final String gameId;
  final VoidCallback? onEditProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roleColor = _roleColor(theme);
    final statusColor = _statusColor(theme);
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildAvatarView(context),
                if (onEditProfile != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onEditProfile,
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'ユーザー情報を編集',
                  ),
                ] else
                  const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        player.nickname,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildInfoBadge(
                            theme,
                            _roleLabel(player.role),
                            roleColor,
                          ),
                          _buildInfoBadge(
                            theme,
                            _statusLabel(player.status),
                            statusColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            _buildGameIdRow(context, theme),
            _buildUserIdRow(context, theme),
            _buildRow(theme, 'ニックネーム', player.nickname),
            _buildRow(theme, '役割', _roleLabel(player.role)),
            _buildRow(theme, '状態', _statusLabel(player.status)),
            _buildRow(theme, 'ステータス', player.isActive ? '参加中' : '離脱'),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarView(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.primary.withOpacity(0.2);
    final hasAvatar = player.avatarUrl != null && player.avatarUrl!.isNotEmpty;
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 3),
      ),
      child: ClipOval(
        child: hasAvatar
            ? Image.network(
                player.avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildAvatarFallback(theme),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                },
              )
            : _buildAvatarFallback(theme),
      ),
    );
  }

  Widget _buildAvatarFallback(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
      child: Icon(
        Icons.person,
        size: 40,
        color: theme.colorScheme.primary.withOpacity(0.6),
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

  Widget _buildInfoBadge(ThemeData theme, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Color _roleColor(ThemeData theme) {
    return player.role == PlayerRole.oni
        ? theme.colorScheme.error
        : Colors.green;
  }

  Color _statusColor(ThemeData theme) {
    switch (player.status) {
      case PlayerStatus.active:
        return Colors.green.shade700;
      case PlayerStatus.downed:
        return Colors.orange;
      case PlayerStatus.eliminated:
        return theme.colorScheme.error;
    }
  }

  Widget _buildGameIdRow(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('ゲームID', style: theme.textTheme.bodySmall),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    gameId,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'ゲームIDをコピー',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: gameId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('ゲームIDをコピーしました')),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserIdRow(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('ユーザーID', style: theme.textTheme.bodySmall),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    player.uid,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'ユーザーIDをコピー',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: player.uid));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('ユーザーIDをコピーしました')),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
