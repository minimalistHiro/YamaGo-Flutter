import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/player.dart';

const _hudBackground = Color(0xEB03161B);
const _cyberGreen = Color(0xFF22B59B);
const _cyberPink = Color(0xFFFF47C2);
const _cyberGold = Color(0xFFFFD166);
const _cyberGlow = Color(0xFF5FFBF1);

class PlayerHud extends StatefulWidget {
  const PlayerHud({
    super.key,
    required this.playersState,
    this.totalGenerators,
    this.clearedGenerators,
  });

  final AsyncValue<List<Player>> playersState;
  final int? totalGenerators;
  final int? clearedGenerators;

  @override
  State<PlayerHud> createState() => _PlayerHudState();
}

class _PlayerHudState extends State<PlayerHud> {
  bool _isCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: widget.playersState.when(
        data: (players) => _PlayerStatsContent(
          players: players,
          totalGenerators: widget.totalGenerators,
          clearedGenerators: widget.clearedGenerators,
        ),
        loading: () => const _HudLoadingContent(),
        error: (error, _) => _HudErrorContent(message: error.toString()),
      ),
    );

    return _HudCard(
      isCollapsed: _isCollapsed,
      onToggleCollapsed: () {
        setState(() {
          _isCollapsed = !_isCollapsed;
        });
      },
      child: body,
    );
  }
}

class _HudCard extends StatelessWidget {
  const _HudCard({
    required this.child,
    required this.isCollapsed,
    required this.onToggleCollapsed,
  });

  final Widget child;
  final bool isCollapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: _hudBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _cyberGreen.withOpacity(0.4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0xA0040C18),
            blurRadius: 40,
            offset: Offset(0, 18),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'プレイヤー状況',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        letterSpacing: 2.4,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onToggleCollapsed,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _cyberGreen.withOpacity(0.35)),
                  ),
                  child: Icon(
                    isCollapsed ? Icons.expand_more : Icons.expand_less,
                    size: 20,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
          AnimatedCrossFade(
            firstChild: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: child,
            ),
            secondChild: const SizedBox.shrink(),
            crossFadeState: isCollapsed
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
            sizeCurve: Curves.easeOut,
          ),
        ],
      ),
    );
  }
}

class _PlayerStatsContent extends StatelessWidget {
  const _PlayerStatsContent({
    required this.players,
    required this.totalGenerators,
    required this.clearedGenerators,
  });

  final List<Player> players;
  final int? totalGenerators;
  final int? clearedGenerators;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activePlayers = players.where((p) => p.isActive).toList();
    final totalPlayers = players.length;
    final oniCount =
        activePlayers.where((p) => p.role == PlayerRole.oni).length;
    final runnerCount = activePlayers.length - oniCount;
    final downedCount =
        activePlayers.where((p) => p.status == PlayerStatus.downed).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _cyberGlow.withOpacity(0.4)),
              gradient: LinearGradient(
                colors: [
                  _cyberGlow.withOpacity(0.08),
                  Colors.white.withOpacity(0.02),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '参加者',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                    letterSpacing: 2.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$totalPlayers人',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _HudDivider(),
        const SizedBox(height: 16),
        _HudStatRow(
          label: 'オンライン',
          value: '${activePlayers.length}人',
          color: _cyberGreen,
        ),
        _HudStatRow(
          label: '鬼',
          value: '${oniCount}人',
          color: _cyberPink,
        ),
        _HudStatRow(
          label: '逃走者',
          value: '${runnerCount}人',
          color: _cyberGreen,
        ),
        _HudStatRow(
          label: 'ダウン中',
          value: '${downedCount}人',
          color: Colors.white60,
        ),
        _HudStatRow(
          label: '解除済み',
          value: _formatGeneratorProgress(),
          color: _cyberGold,
        ),
      ],
    );
  }

  String _formatGeneratorProgress() {
    final numerator = clearedGenerators;
    final denominator = totalGenerators;
    final numeratorText = numerator != null ? '$numerator' : '--';
    final denominatorText = denominator != null ? '$denominator' : '--';
    return '$numeratorText/$denominatorText';
  }
}

class _HudStatRow extends StatelessWidget {
  const _HudStatRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                letterSpacing: 2.4,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _HudDivider extends StatelessWidget {
  const _HudDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            _cyberGreen.withOpacity(0.8),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

class _HudLoadingContent extends StatelessWidget {
  const _HudLoadingContent();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(_cyberGreen),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'プレイヤーを取得中...',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                  letterSpacing: 1.8,
                ),
          ),
        ),
      ],
    );
  }
}

class _HudErrorContent extends StatelessWidget {
  const _HudErrorContent({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'プレイヤー情報の取得に失敗しました',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.redAccent,
                      letterSpacing: 1.4,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white70,
              ),
        ),
      ],
    );
  }
}
