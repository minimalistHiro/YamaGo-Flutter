import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yamago_flutter/core/services/firebase_providers.dart';
import 'package:yamago_flutter/features/game/application/player_providers.dart';
import 'package:yamago_flutter/features/game/data/player_repository.dart';
import 'package:yamago_flutter/features/game/domain/player.dart';

class RoleAssignmentPage extends ConsumerStatefulWidget {
  const RoleAssignmentPage({
    super.key,
    required this.gameId,
  });

  static const routeName = 'role-assignment';
  static const routePath = '/game/:gameId/role-assignment';
  static String path(String gameId) => '/game/$gameId/role-assignment';

  final String gameId;

  @override
  ConsumerState<RoleAssignmentPage> createState() => _RoleAssignmentPageState();
}

class _RoleAssignmentPageState extends ConsumerState<RoleAssignmentPage> {
  bool _isProcessing = false;
  String? _errorMessage;
  String? _deletingUid;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(firebaseAuthProvider);
    final currentUid = auth.currentUser?.uid;
    if (currentUid == null) {
      return const Scaffold(
        body: Center(
          child: Text('サインイン情報を取得できませんでした'),
        ),
      );
    }

    final gameState = ref.watch(gameStreamProvider(widget.gameId));
    final canManage = gameState.maybeWhen(
      data: (game) => game != null && game.ownerUid == currentUid,
      orElse: () => false,
    );
    final playersState = ref.watch(playersStreamProvider(widget.gameId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('役職振り分け'),
      ),
      body: SafeArea(
        child: playersState.when(
          data: (players) => _buildContent(players,
              canManage: canManage, currentUid: currentUid),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('プレイヤー情報の取得に失敗しました: $error')),
        ),
      ),
    );
  }

  Widget _buildContent(
    List<Player> players, {
    required bool canManage,
    required String currentUid,
  }) {
    final sortedPlayers = [...players]..sort(
        (a, b) => a.nickname.toLowerCase().compareTo(b.nickname.toLowerCase()),
      );
    final oniPlayers =
        sortedPlayers.where((player) => player.role == PlayerRole.oni).toList();
    final runnerPlayers = sortedPlayers
        .where((player) => player.role == PlayerRole.runner)
        .toList();
    final oniCount = oniPlayers.length;
    final runnerCount = runnerPlayers.length;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_errorMessage != null) ...[
              _buildErrorCard(context, _errorMessage!),
              const SizedBox(height: 16),
            ],
            if (!canManage) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '役職の変更やプレイヤーの削除はゲームオーナーのみが実施できます。',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            _buildSummaryCard(context,
                oniCount: oniCount, runnerCount: runnerCount),
            const SizedBox(height: 16),
            if (players.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('まだ参加者がいません'),
                ),
              )
            else
              _buildRoleLists(
                context,
                oniPlayers: oniPlayers,
                runnerPlayers: runnerPlayers,
                canManage: canManage,
                currentUid: currentUid,
              ),
            const SizedBox(height: 16),
            if (canManage && players.length >= 2)
              _buildRandomizeCard(
                context,
                players: players,
                oniCount: oniCount,
                runnerCount: runnerCount,
              ),
            const SizedBox(height: 16),
            _buildInstructionCard(context),
          ],
        ),
        if (_isProcessing) ...[
          ModalBarrier(
            dismissible: false,
            color: Colors.black.withOpacity(0.2),
          ),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    );
  }

  Widget _buildErrorCard(BuildContext context, String message) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          style: TextStyle(color: theme.colorScheme.onErrorContainer),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context, {
    required int oniCount,
    required int runnerCount,
  }) {
    final total = oniCount + runnerCount;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '役職割り当て状況',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _SummaryTile(
                    label: '鬼',
                    count: oniCount,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryTile(
                    label: '逃走者',
                    count: runnerCount,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '合計: $total人',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleLists(
    BuildContext context, {
    required List<Player> oniPlayers,
    required List<Player> runnerPlayers,
    required bool canManage,
    required String currentUid,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final oniCard = _RoleListCard(
          title: '鬼 (${oniPlayers.length}人)',
          color: Colors.redAccent,
          players: oniPlayers,
          hintText: 'タップで逃走者に変更',
          canManage: canManage,
          currentUid: currentUid,
          onChangeRole: (player) =>
              _handleRoleChange(player, PlayerRole.runner),
          onDelete: (player) => _handleDeletePlayer(player),
          deletingUid: _deletingUid,
        );
        final runnerCard = _RoleListCard(
          title: '逃走者 (${runnerPlayers.length}人)',
          color: Colors.green,
          players: runnerPlayers,
          hintText: 'タップで鬼に変更',
          canManage: canManage,
          currentUid: currentUid,
          onChangeRole: (player) => _handleRoleChange(player, PlayerRole.oni),
          onDelete: (player) => _handleDeletePlayer(player),
          deletingUid: _deletingUid,
        );

        if (constraints.maxWidth < 640) {
          return Column(
            children: [
              oniCard,
              const SizedBox(height: 16),
              runnerCard,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: oniCard),
            const SizedBox(width: 16),
            Expanded(child: runnerCard),
          ],
        );
      },
    );
  }

  Widget _buildRandomizeCard(
    BuildContext context, {
    required List<Player> players,
    required int oniCount,
    required int runnerCount,
  }) {
    final canRandomize = oniCount > 0 && runnerCount > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '役職をランダムに振り分け',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '現在の鬼 $oniCount 人 / 逃走者 $runnerCount 人のバランスは維持したまま、役職をランダムに再割り当てします。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!canRandomize) ...[
              const SizedBox(height: 12),
              Text(
                '鬼と逃走者が最低1人ずついる時のみシャッフルできます。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: !_isProcessing && canRandomize
                  ? () => _confirmRandomize(players)
                  : null,
              style: ElevatedButton.styleFrom(
                shape: const StadiumBorder(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
              icon: const Icon(Icons.shuffle),
              label: const Text('ランダムに振り分け'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              '役職振り分けのヒント',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('• 左が鬼、右が逃走者のリストです。'),
            SizedBox(height: 4),
            Text('• プレイヤーをタップすると反対の役職に切り替えられます。'),
            SizedBox(height: 4),
            Text('• ランダム振り分けでは現在の人数を保ったままシャッフルします。'),
            SizedBox(height: 4),
            Text('• ゲーム開始後でも役職の変更は可能です。'),
          ],
        ),
      ),
    );
  }

  Future<void> _handleRoleChange(Player player, PlayerRole nextRole) async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });
    final repo = ref.read(playerRepositoryProvider);
    try {
      await repo.updatePlayerRole(
        gameId: widget.gameId,
        uid: player.uid,
        role: nextRole,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${player.nickname} を${nextRole == PlayerRole.oni ? '鬼' : '逃走者'}に変更しました',
            ),
          ),
        );
      }
    } catch (error) {
      setState(() {
        _errorMessage = '役職の変更に失敗しました: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _confirmRandomize(List<Player> players) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ランダムに振り分け'),
        content: const Text('現在の人数を維持したまま役職をランダムに振り分けます。よろしいですか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('実行する'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _randomizeRoles(players);
    }
  }

  Future<void> _randomizeRoles(List<Player> players) async {
    if (_isProcessing || players.isEmpty) return;
    final oniCount =
        players.where((player) => player.role == PlayerRole.oni).length;
    final runnerCount = players.length - oniCount;
    if (oniCount == 0 || runnerCount == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('鬼と逃走者が最低1人ずつ必要です'),
          ),
        );
      }
      return;
    }
    final shuffled = List<Player>.from(players)..shuffle(math.Random());
    final updates = <({String uid, PlayerRole role})>[];
    for (var i = 0; i < shuffled.length; i++) {
      final targetRole = i < oniCount ? PlayerRole.oni : PlayerRole.runner;
      final player = shuffled[i];
      if (player.role != targetRole) {
        updates.add((uid: player.uid, role: targetRole));
      }
    }
    if (updates.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('役職はすでに現在の構成どおりに割り当てられています')),
        );
      }
      return;
    }
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });
    final repo = ref.read(playerRepositoryProvider);
    try {
      await Future.wait(
        updates.map(
          (update) => repo.updatePlayerRole(
            gameId: widget.gameId,
            uid: update.uid,
            role: update.role,
          ),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('役職をランダムに再割り当てしました')),
        );
      }
    } catch (error) {
      setState(() {
        _errorMessage = '役職のランダム振り分けに失敗しました: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _handleDeletePlayer(Player player) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('プレイヤーを削除'),
        content: Text(
          '${player.nickname} を削除しますか？\n位置情報も含めて削除されます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _deletingUid = player.uid;
      _errorMessage = null;
    });
    final repo = ref.read(playerRepositoryProvider);
    try {
      await repo.deletePlayer(gameId: widget.gameId, uid: player.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${player.nickname} を削除しました')),
        );
      }
    } catch (error) {
      setState(() {
        _errorMessage = 'プレイヤーの削除に失敗しました: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _deletingUid = null;
        });
      }
    }
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                label == '鬼' ? Icons.whatshot : Icons.directions_run,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$count人',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}

class _RoleListCard extends StatelessWidget {
  const _RoleListCard({
    required this.title,
    required this.color,
    required this.players,
    required this.hintText,
    required this.canManage,
    required this.currentUid,
    required this.onChangeRole,
    required this.onDelete,
    required this.deletingUid,
  });

  final String title;
  final Color color;
  final List<Player> players;
  final String hintText;
  final bool canManage;
  final String currentUid;
  final void Function(Player player) onChangeRole;
  final void Function(Player player) onDelete;
  final String? deletingUid;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (players.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.2)),
                ),
                child: const Center(
                  child: Text('プレイヤーがいません'),
                ),
              )
            else
              Column(
                children: [
                  for (final player in players) ...[
                    Material(
                      color: color.withOpacity(canManage ? 0.08 : 0.04),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: canManage ? () => onChangeRole(player) : null,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                backgroundColor: color.withOpacity(0.15),
                                child: Icon(
                                  player.role == PlayerRole.oni
                                      ? Icons.whatshot
                                      : Icons.directions_run,
                                  color: color,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            player.nickname,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        if (player.uid == currentUid)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surfaceVariant,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              '自分',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _playerStateLabel(player),
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    if (canManage) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        hintText,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: color),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (canManage && player.uid != currentUid)
                                    IconButton(
                                      icon: deletingUid == player.uid
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.person_remove_alt_1,
                                            ),
                                      onPressed: deletingUid == player.uid
                                          ? null
                                          : () => onDelete(player),
                                    ),
                                  Icon(
                                    Icons.swap_horiz,
                                    color: color,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _playerStateLabel(Player player) {
    final statusLabel = switch (player.status) {
      PlayerStatus.downed => 'ダウン中',
      PlayerStatus.eliminated => '脱落',
      PlayerStatus.active => 'アクティブ',
    };
    if (!player.isActive) {
      return '$statusLabel / 離脱扱い';
    }
    return statusLabel;
  }
}
