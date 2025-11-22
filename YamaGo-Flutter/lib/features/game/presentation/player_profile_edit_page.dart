import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yamago_flutter/core/storage/local_profile_store.dart';
import 'package:yamago_flutter/core/storage/player_avatar_storage.dart';
import 'package:yamago_flutter/features/game/application/player_providers.dart';
import 'package:yamago_flutter/features/game/data/player_repository.dart';
import 'package:yamago_flutter/features/game/domain/player.dart';
import 'package:yamago_flutter/core/services/firebase_providers.dart';

class PlayerProfileEditPage extends ConsumerStatefulWidget {
  const PlayerProfileEditPage({super.key, required this.gameId});

  static const routeName = 'player-profile-edit';
  static const routePath = '/game/:gameId/profile/edit';
  static String path(String gameId) => '/game/$gameId/profile/edit';

  final String gameId;

  @override
  ConsumerState<PlayerProfileEditPage> createState() =>
      _PlayerProfileEditPageState();
}

class _PlayerProfileEditPageState extends ConsumerState<PlayerProfileEditPage> {
  final _nicknameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();

  bool _nicknameInitialized = false;
  bool _isSaving = false;
  bool _removeAvatar = false;
  Uint8List? _pickedImageBytes;
  String? _errorMessage;

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(firebaseAuthProvider);
    final user = auth.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('サインイン情報を取得できませんでした')),
      );
    }

    final playerState = ref.watch(
      playerStreamProvider((gameId: widget.gameId, uid: user.uid)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('ユーザー情報を編集'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: playerState.when(
        data: (player) {
          if (player == null) {
            return const Center(child: Text('プレイヤー情報が見つかりません'));
          }
          if (!_nicknameInitialized) {
            _nicknameController.text = player.nickname;
            _nicknameInitialized = true;
          }
          return Stack(
            children: [
              _buildForm(context, player),
              if (_isSaving)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 4),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('プレイヤー情報の取得に失敗しました: $error')),
      ),
    );
  }

  Widget _buildForm(BuildContext context, Player player) {
    final theme = Theme.of(context);
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_errorMessage != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _errorMessage!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '基本情報',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nicknameController,
                    enabled: !_isSaving,
                    decoration: const InputDecoration(
                      labelText: 'ニックネーム',
                      helperText: '20文字まで。ゲーム内の表示名になります。',
                    ),
                    maxLength: 20,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'ニックネームを入力してください';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'アイコン画像',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildAvatarPreview(player),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _isSaving ? null : _pickImage,
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('画像を選択'),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _isSaving
                                  ? null
                                  : () {
                                      setState(() {
                                        _pickedImageBytes = null;
                                        _removeAvatar = true;
                                      });
                                    },
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('画像を削除'),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '推奨: 正方形の画像（最大5MB）。\nアップロード済みの場合は置き換えまたは削除できます。',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.hintColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isSaving ? null : () => _handleSave(player),
            child: const Text('変更を保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarPreview(Player player) {
    final hasPickedImage = _pickedImageBytes != null;
    final showNetworkAvatar = !_removeAvatar &&
        !hasPickedImage &&
        (player.avatarUrl?.isNotEmpty ?? false);

    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.grey.shade300,
          width: 3,
        ),
      ),
      child: ClipOval(
        child: hasPickedImage
            ? Image.memory(_pickedImageBytes!, fit: BoxFit.cover)
            : showNetworkAvatar
                ? Image.network(
                    player.avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildAvatarFallback(),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      );
                    },
                  )
                : _buildAvatarFallback(),
      ),
    );
  }

  Widget _buildAvatarFallback() {
    return Container(
      color: Colors.grey.shade100,
      child: Icon(
        Icons.person,
        size: 48,
        color: Colors.grey.shade400,
      ),
    );
  }

  Future<void> _pickImage() async {
    setState(() {
      _errorMessage = null;
    });
    final result = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (result == null) {
      return;
    }
    final bytes = await result.readAsBytes();
    const maxBytes = 5 * 1024 * 1024;
    if (bytes.lengthInBytes > maxBytes) {
      setState(() {
        _errorMessage = '画像サイズは5MB以下にしてください';
      });
      return;
    }
    setState(() {
      _pickedImageBytes = bytes;
      _removeAvatar = false;
    });
  }

  Future<void> _handleSave(Player player) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final nickname = _nicknameController.text.trim();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      String? avatarUrl = _removeAvatar ? '' : (player.avatarUrl ?? '');

      if (_pickedImageBytes != null) {
        final storage = await ref.read(playerAvatarStorageProvider.future);
        avatarUrl = await storage.uploadAvatar(
          uid: player.uid,
          bytes: _pickedImageBytes!,
        );
      }

      final repo = ref.read(playerRepositoryProvider);
      await repo.updatePlayerProfile(
        gameId: widget.gameId,
        uid: player.uid,
        nickname: nickname,
        avatarUrl: avatarUrl,
      );

      final profileStore = await ref.read(localProfileStoreProvider.future);
      await profileStore.saveNickname(nickname);

      if (!mounted) return;
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('プロフィールを更新しました')),
      );
      context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '更新に失敗しました: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}
