import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yamago_flutter/core/services/firebase_providers.dart';
import 'package:yamago_flutter/features/game/application/player_providers.dart';
import 'package:yamago_flutter/features/game/data/game_repository.dart';
import 'package:yamago_flutter/features/game/domain/game.dart';
import 'package:yamago_flutter/features/game/domain/player.dart';
import 'package:yamago_flutter/features/pins/data/pin_repository.dart';
import 'package:yamago_flutter/features/pins/presentation/pin_editor_page.dart';

class GameSettingsPage extends ConsumerStatefulWidget {
  const GameSettingsPage({
    super.key,
    required this.gameId,
  });

  static const routeName = 'game-settings';
  static const routePath = '/game/:gameId/settings';
  static String path(String gameId) => '/game/$gameId/settings';

  final String gameId;

  @override
  ConsumerState<GameSettingsPage> createState() => _GameSettingsPageState();
}

class _GameSettingsPageState extends ConsumerState<GameSettingsPage> {
  static const _defaultPinCount = 10;
  static const _defaultCaptureRadius = 100;
  static const _defaultRunnerSeeKiller = 500;
  static const _defaultRunnerSeeRunner = 1000;
  static const _defaultRunnerSeeGenerator = 3000;
  static const _defaultKillerDetectRunner = 500;
  static const _defaultKillerSeeGenerator = 3000;
  static const _defaultCountdownSeconds = 900;
  static const _defaultGeneratorClearSeconds = 180;
  static const _defaultGameDurationMinutes = 120;

  bool _formInitialized = false;
  double _pinCount = _defaultPinCount.toDouble();
  double _captureRadius = _defaultCaptureRadius.toDouble();
  double _runnerSeeKiller = _defaultRunnerSeeKiller.toDouble();
  double _runnerSeeRunner = _defaultRunnerSeeRunner.toDouble();
  double _runnerSeeGenerator = _defaultRunnerSeeGenerator.toDouble();
  double _killerDetectRunner = _defaultKillerDetectRunner.toDouble();
  double _killerSeeGenerator = _defaultKillerSeeGenerator.toDouble();
  double _gameDurationMinutes = _defaultGameDurationMinutes.toDouble();
  double _generatorClearDurationSeconds =
      _defaultGeneratorClearSeconds.toDouble();
  int _countdownMinutes = _defaultCountdownSeconds ~/ 60;
  int _countdownSeconds = _defaultCountdownSeconds % 60;
  int? _initialPinCount;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final gameAsync = ref.watch(gameStreamProvider(widget.gameId));
    final auth = ref.watch(firebaseAuthProvider);
    final currentUid = auth.currentUser?.uid;
    final playerAsync = currentUid == null
        ? null
        : ref.watch(
            playerStreamProvider(
              (gameId: widget.gameId, uid: currentUid),
            ),
          );
    return Scaffold(
      appBar: AppBar(
        title: const Text('ゲーム設定'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _buildAppBarAvatar(context, playerAsync),
          ),
        ],
      ),
      body: SafeArea(
        child: gameAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('ゲーム情報の取得に失敗しました: $error')),
          data: (game) {
            if (game == null) {
              return const Center(child: Text('ゲーム情報が見つかりません'));
            }
            _maybeInitializeForm(game);
            return Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_errorMessage != null) ...[
                      Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _buildPinCountCard(context),
                    const SizedBox(height: 16),
                    _buildGameDurationCard(),
                    const SizedBox(height: 16),
                    _buildCaptureRadiusCard(),
                    const SizedBox(height: 16),
                    _buildVisibilityCard(
                      title: '逃走者が発電所を視認できる距離',
                      value: _runnerSeeGenerator,
                      min: 100,
                      max: 10000,
                      divisions: 99,
                      onChanged: (next) =>
                          setState(() => _runnerSeeGenerator = next),
                      description: '逃走者のマップに発電所（黄色ピン）が表示される距離です。'
                          '近いほど探索が難しくなります。',
                    ),
                    const SizedBox(height: 16),
                    _buildVisibilityCard(
                      title: '鬼が発電所を視認できる距離',
                      value: _killerSeeGenerator,
                      min: 100,
                      max: 10000,
                      divisions: 99,
                      onChanged: (next) =>
                          setState(() => _killerSeeGenerator = next),
                      description: '鬼のマップに発電所が表示される距離です。'
                          '逃走者と同様に 100〜10,000m の範囲で調整できます。',
                    ),
                    const SizedBox(height: 16),
                    _buildVisibilityCard(
                      title: '逃走者同士の視認距離',
                      value: _runnerSeeRunner,
                      min: 100,
                      max: 10000,
                      divisions: 99,
                      onChanged: (next) =>
                          setState(() => _runnerSeeRunner = next),
                      description: '逃走者同士でお互いの位置が表示される距離です。'
                          '連携しやすさのバランスを取ってください。',
                    ),
                    const SizedBox(height: 16),
                    _buildVisibilityCard(
                      title: '逃走者が鬼を検知する距離',
                      value: _runnerSeeKiller,
                      min: 100,
                      max: 5000,
                      divisions: 49,
                      onChanged: (next) =>
                          setState(() => _runnerSeeKiller = next),
                      description: '逃走者が鬼の位置を警告として受け取る距離です。',
                    ),
                    const SizedBox(height: 16),
                    _buildVisibilityCard(
                      title: '鬼が逃走者を検知する距離',
                      value: _killerDetectRunner,
                      min: 100,
                      max: 5000,
                      divisions: 49,
                      onChanged: (next) =>
                          setState(() => _killerDetectRunner = next),
                      description: '鬼のマップに逃走者が表示される最大距離です。',
                    ),
                    const SizedBox(height: 16),
                    _buildGeneratorClearDurationCard(),
                    const SizedBox(height: 16),
                    _buildCountdownCard(),
                    const SizedBox(height: 16),
                    _buildSaveButton(context),
                  ],
                ),
                if (_isSaving) ...[
                  ModalBarrier(
                    dismissible: false,
                    color: Colors.black.withOpacity(0.2),
                  ),
                  const Center(child: CircularProgressIndicator()),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  void _maybeInitializeForm(Game game) {
    if (_formInitialized) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final countdownSeconds =
          (game.countdownDurationSec ?? _defaultCountdownSeconds)
              .clamp(0, 24 * 60 * 60);
      final gameDurationMinutes =
          ((game.gameDurationSec ?? (_defaultGameDurationMinutes * 60)) / 60)
              .clamp(10, 480)
              .toDouble();
      setState(() {
        _pinCount = (game.pinCount ?? _defaultPinCount).clamp(1, 20).toDouble();
        _captureRadius = (game.captureRadiusM ?? _defaultCaptureRadius)
            .clamp(10, 200)
            .toDouble();
        _runnerSeeKiller =
            (game.runnerSeeKillerRadiusM ?? _defaultRunnerSeeKiller)
                .clamp(100, 5000)
                .toDouble();
        _runnerSeeRunner =
            (game.runnerSeeRunnerRadiusM ?? _defaultRunnerSeeRunner)
                .clamp(100, 10000)
                .toDouble();
        _runnerSeeGenerator =
            (game.runnerSeeGeneratorRadiusM ?? _defaultRunnerSeeGenerator)
                .clamp(100, 10000)
                .toDouble();
        _killerDetectRunner =
            (game.killerDetectRunnerRadiusM ?? _defaultKillerDetectRunner)
                .clamp(100, 5000)
                .toDouble();
        _killerSeeGenerator =
            (game.killerSeeGeneratorRadiusM ?? _defaultKillerSeeGenerator)
                .clamp(100, 10000)
                .toDouble();
        _gameDurationMinutes = gameDurationMinutes;
        _generatorClearDurationSeconds =
            (game.generatorClearDurationSec ?? _defaultGeneratorClearSeconds)
                .clamp(10, 600)
                .toDouble();
        _countdownMinutes = countdownSeconds ~/ 60;
        _countdownSeconds = countdownSeconds % 60;
        _formInitialized = true;
        _initialPinCount ??= _pinCount.toInt();
      });
    });
  }

  Widget _buildPinCountCard(BuildContext context) {
    final sliderTheme = SliderTheme.of(context).copyWith(
      showValueIndicator: ShowValueIndicator.always,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '発電所の数',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('設置数: ${_pinCount.toInt()} 個'),
            SliderTheme(
              data: sliderTheme,
              child: Slider(
                min: 1,
                max: 20,
                divisions: 19,
                label: '${_pinCount.toInt()}',
                value: _pinCount,
                onChanged: _isSaving
                    ? null
                    : (value) => setState(() => _pinCount = value),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('1'),
                Text('20'),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'ゲーム開始時にマップへ配置される発電所（黄色ピン）の数です。'
              '必要に応じて 1〜20 個の範囲で設定してください。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameDurationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ゲーム時間',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
                '長さ: ${_formatGameDurationLabel(_gameDurationMinutes.toInt())}'),
            Slider(
              min: 10,
              max: 480,
              divisions: (480 - 10) ~/ 5,
              label: '${_gameDurationMinutes.toInt()}分',
              value: _gameDurationMinutes,
              onChanged: _isSaving
                  ? null
                  : (value) => setState(() => _gameDurationMinutes = value),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('10分'),
                Text('8時間'),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'ゲーム開始から終了までの制限時間です。'
              '10分〜8時間の範囲で指定できます（推奨: 120分）。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneratorClearDurationCard() {
    final seconds = _generatorClearDurationSeconds.toInt();
    final formatted = _formatShortDuration(seconds);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '発電所解除時間',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('解除に必要な時間: $formatted'),
            Slider(
              min: 10,
              max: 600,
              divisions: 590,
              label: formatted,
              value: _generatorClearDurationSeconds,
              onChanged: _isSaving
                  ? null
                  : (value) =>
                      setState(() => _generatorClearDurationSeconds = value),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('10秒'),
                Text('10分'),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '逃走者が発電所を解除する際のカウントダウン時間です。'
              '10秒〜10分の範囲で設定できます（推奨: 3分）。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptureRadiusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '捕獲半径',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('半径: ${_captureRadius.toInt()}m'),
            Slider(
              min: 10,
              max: 200,
              divisions: 19,
              label: '${_captureRadius.toInt()}m',
              value: _captureRadius,
              onChanged: _isSaving
                  ? null
                  : (value) => setState(() => _captureRadius = value),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('10m'),
                Text('200m'),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '鬼が逃走者を捕獲できる距離です。エリアの広さに応じて調整してください。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisibilityCard({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String description,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('半径: ${_formatDistanceLabel(value.toInt())}'),
            Slider(
              min: min,
              max: max,
              divisions: divisions,
              label: _formatDistanceLabel(value.toInt()),
              value: value,
              onChanged: _isSaving ? null : onChanged,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDistanceLabel(min.toInt())),
                Text(_formatDistanceLabel(max.toInt())),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdownCard() {
    final textTheme = Theme.of(context).textTheme;
    final items = List.generate(60, (index) => index);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'カウントダウン時間',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                DropdownButton<int>(
                  value: _countdownMinutes,
                  items: items
                      .map(
                        (value) => DropdownMenuItem<int>(
                          value: value,
                          child: Text('$value'),
                        ),
                      )
                      .toList(),
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _countdownMinutes = value);
                        },
                ),
                const SizedBox(width: 8),
                const Text('分'),
                const SizedBox(width: 24),
                DropdownButton<int>(
                  value: _countdownSeconds,
                  items: items
                      .map(
                        (value) => DropdownMenuItem<int>(
                          value: value,
                          child: Text('$value'),
                        ),
                      )
                      .toList(),
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _countdownSeconds = value);
                        },
                ),
                const SizedBox(width: 8),
                const Text('秒'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '合計: ${_countdownMinutes * 60 + _countdownSeconds} 秒'
              ' (${_countdownMinutes}分${_countdownSeconds}秒)',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'ゲーム開始ボタンを押してからカウントダウンが終了するまでの時間です。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton(BuildContext context) {
    return ElevatedButton(
      onPressed: _isSaving ? null : () => _confirmSave(context),
      child: Text(_isSaving ? '保存中...' : '設定を保存'),
    );
  }

  Future<void> _confirmSave(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('設定を保存'),
        content: const Text('現在の設定を保存し、設定画面に戻ります。よろしいですか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存する'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _handleSave(context);
    }
  }

  Future<void> _handleSave(BuildContext context) async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final repo = ref.read(gameRepositoryProvider);
      final pinRepo = ref.read(pinRepositoryProvider);
      final previousPinCount = _initialPinCount;
      final newPinCount = _pinCount.toInt();
      final pinCountChanged =
          previousPinCount != null && previousPinCount != newPinCount;
      final settings = GameSettingsInput(
        captureRadiusM: _captureRadius.toInt(),
        runnerSeeKillerRadiusM: _runnerSeeKiller.toInt(),
        runnerSeeRunnerRadiusM: _runnerSeeRunner.toInt(),
        runnerSeeGeneratorRadiusM: _runnerSeeGenerator.toInt(),
        killerDetectRunnerRadiusM: _killerDetectRunner.toInt(),
        killerSeeGeneratorRadiusM: _killerSeeGenerator.toInt(),
        pinCount: newPinCount,
        countdownDurationSec: _countdownMinutes * 60 + _countdownSeconds,
        gameDurationSec: _gameDurationMinutes.toInt() * 60,
        generatorClearDurationSec:
            _generatorClearDurationSeconds.clamp(10, 600).toInt(),
      );
      await repo.updateGameSettings(gameId: widget.gameId, settings: settings);
      if (pinCountChanged) {
        await pinRepo.reseedPinsWithRandomLocations(
          gameId: widget.gameId,
          targetCount: newPinCount,
        );
      }
      _initialPinCount = newPinCount;
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      setState(() {
        _errorMessage = '保存に失敗しました: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String _formatGameDurationLabel(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    final parts = <String>[];
    if (hours > 0) {
      parts.add('${hours}時間');
    }
    if (mins > 0) {
      parts.add('${mins}分');
    }
    if (parts.isEmpty) {
      return '0分';
    }
    return parts.join(' ');
  }

  String _formatDistanceLabel(int meters) {
    if (meters >= 1000) {
      final km = meters / 1000;
      return km % 1 == 0 ? '${km.toInt()}km' : '${km.toStringAsFixed(1)}km';
    }
    return '${meters}m';
  }

  String _formatShortDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes <= 0) {
      return '${secs}秒';
    }
    if (secs == 0) {
      return '${minutes}分';
    }
    return '${minutes}分${secs}秒';
  }

  Widget _buildAppBarAvatar(
    BuildContext context,
    AsyncValue<Player?>? playerAsync,
  ) {
    Widget buildAvatar(String? avatarUrl) => Center(
          child: _buildAvatarView(
            context,
            avatarUrl,
            size: 36,
            borderWidth: 2,
          ),
        );
    final placeholder = buildAvatar(null);
    if (playerAsync == null) {
      return placeholder;
    }
    return playerAsync.when(
      data: (player) => buildAvatar(player?.avatarUrl),
      loading: () => const Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: Padding(
            padding: EdgeInsets.all(8),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, __) => placeholder,
    );
  }

  Widget _buildAvatarView(
    BuildContext context,
    String? avatarUrl, {
    double size = 96,
    double borderWidth = 3,
  }) {
    final borderColor = Theme.of(context).colorScheme.primary.withOpacity(0.3);
    final fallbackIconSize = size * 0.5;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: ClipOval(
        child: avatarUrl != null && avatarUrl.isNotEmpty
            ? Image.network(
                avatarUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.person_rounded,
                  size: fallbackIconSize,
                ),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
              )
            : Icon(
                Icons.person_rounded,
                size: fallbackIconSize,
              ),
      ),
    );
  }

}
