import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yamago_flutter/core/storage/local_profile_store.dart';

import '../application/onboarding_notifier.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  static const routeName = 'welcome';
  static const routePath = '/welcome';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('YamaGo'),
        actions: [
          TextButton(
            onPressed: () => context.go(JoinPage.routePath),
            child: const Text('参加'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '山手線リアル鬼ごっこ',
              style: textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'ウェブ版と同じプレイ体験をネイティブアプリで提供するためのプレースホルダー画面です。',
              style: textTheme.bodyLarge,
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => context.go(CreateGamePage.routePath),
              child: const Text('ゲームを作成'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go(JoinPage.routePath),
              child: const Text('ゲームに参加'),
            ),
          ],
        ),
      ),
    );
  }
}

class JoinPage extends ConsumerStatefulWidget {
  const JoinPage({super.key});

  static const routeName = 'join';
  static const routePath = '/join';

  @override
  ConsumerState<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends ConsumerState<JoinPage> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  final _gameIdController = TextEditingController();
  bool _prefilled = false;

  @override
  void dispose() {
    _nicknameController.dispose();
    _gameIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboardingState = ref.watch(onboardingControllerProvider);
    final isLoading = onboardingState.isLoading;
    final profileStore = ref.watch(localProfileStoreProvider);

    profileStore.whenData((store) {
      if (_prefilled) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _prefilled) return;
        final nickname = store.nickname ?? '';
        final lastGameId = store.lastGameId ?? '';
        if (_nicknameController.text.isEmpty && nickname.isNotEmpty) {
          _nicknameController.text = nickname;
        }
        if (_gameIdController.text.isEmpty && lastGameId.isNotEmpty) {
          _gameIdController.text = lastGameId;
        }
        _prefilled = true;
      });
    });

    return Scaffold(
      appBar: AppBar(title: const Text('ゲームに参加')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nicknameController,
                decoration: const InputDecoration(labelText: 'ニックネーム'),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'ニックネームを入力してください'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _gameIdController,
                decoration: const InputDecoration(labelText: 'ゲームID'),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'ゲームIDを入力してください'
                    : null,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: isLoading ? null : _handleJoin,
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: const Text('ゲームに参加'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleJoin() async {
    if (!_formKey.currentState!.validate()) return;
    final gameId = _gameIdController.text.trim();
    final nickname = _nicknameController.text.trim();
    final controller = ref.read(onboardingControllerProvider.notifier);
    try {
      await controller.joinGame(gameId: gameId, nickname: nickname);
      if (!mounted) return;
      context.go('/game/$gameId/map');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('参加に失敗しました: $error')),
      );
    }
  }
}

class CreateGamePage extends ConsumerStatefulWidget {
  const CreateGamePage({super.key});

  static const routeName = 'create';
  static const routePath = '/create';

  @override
  ConsumerState<CreateGamePage> createState() => _CreateGamePageState();
}

class _CreateGamePageState extends ConsumerState<CreateGamePage> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  String? _createdGameId;
  bool _prefilled = false;

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboardingState = ref.watch(onboardingControllerProvider);
    final isLoading = onboardingState.isLoading;
    final profileStore = ref.watch(localProfileStoreProvider);

    profileStore.whenData((store) {
      if (_prefilled) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _prefilled) return;
        final nickname = store.nickname ?? '';
        if (_nicknameController.text.isEmpty && nickname.isNotEmpty) {
          _nicknameController.text = nickname;
        }
        _prefilled = true;
      });
    });

    return Scaffold(
      appBar: AppBar(title: const Text('ゲームを作成')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nicknameController,
                decoration: const InputDecoration(labelText: 'ニックネーム'),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'ニックネームを入力してください'
                    : null,
              ),
              if (_createdGameId != null) ...[
                const SizedBox(height: 24),
                Text('作成されたゲームID: $_createdGameId'),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => context.go('/game/${_createdGameId!}/map'),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('ゲーム画面へ移動'),
                ),
              ],
              const Spacer(),
              FilledButton.icon(
                onPressed: isLoading ? null : _handleCreate,
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_circle_outline),
                label: const Text('ゲームを作成'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleCreate() async {
    if (!_formKey.currentState!.validate()) return;
    final nickname = _nicknameController.text.trim();
    final controller = ref.read(onboardingControllerProvider.notifier);
    try {
      final gameId = await controller.createGame(nickname: nickname);
      if (!mounted) return;
      setState(() {
        _createdGameId = gameId;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ゲームを作成しました: $gameId')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ゲーム作成に失敗しました: $error')),
      );
    }
  }
}
