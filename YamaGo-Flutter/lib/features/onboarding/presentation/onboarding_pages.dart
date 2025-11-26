import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yamago_flutter/features/auth/application/auth_providers.dart';
import 'package:yamago_flutter/core/services/firebase_providers.dart';
import 'package:yamago_flutter/core/storage/local_profile_store.dart';
import 'package:yamago_flutter/features/game_shell/presentation/game_shell_page.dart';

import '../application/onboarding_notifier.dart';
import '../application/startup_cleanup_provider.dart';

class WelcomePage extends ConsumerWidget {
  const WelcomePage({super.key});

  static const routeName = 'welcome';
  static const routePath = '/welcome';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebaseState = ref.watch(firebaseAppProvider);
    final authState = ref.watch(ensureAnonymousSignInProvider);
    ref.watch(startupCleanupProvider);
    final initError =
        firebaseState.hasError ? firebaseState.error : authState.error;
    final isLoading = firebaseState.isLoading || authState.isLoading;
    final isReady =
        firebaseState.hasValue && authState.hasValue && initError == null;

    final theme = Theme.of(context);
    final mutedStyle = theme.textTheme.bodySmall?.copyWith(
      color: _OnboardingColors.mutedText,
      letterSpacing: 3,
      fontSize: 11,
    );

    return Scaffold(
      backgroundColor: _OnboardingColors.background,
      body: Stack(
        children: [
          _NeonBackground(
            centerContent: true,
            glows: const [
              _GlowSpec(
                alignment: Alignment.topLeft,
                size: 280,
                offset: Offset(-160, -120),
                colors: [
                  Color(0xFF0B1F2E),
                  Color(0xFF091726),
                ],
                opacity: 0.5,
              ),
              _GlowSpec(
                alignment: Alignment.bottomRight,
                size: 360,
                offset: Offset(160, 140),
                colors: [
                  Color(0xFF151B3A),
                  Color(0xFF0C1224),
                ],
                opacity: 0.5,
              ),
            ],
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 420),
                    padding: const EdgeInsets.fromLTRB(28, 48, 28, 36),
                    decoration: BoxDecoration(
                      color: const Color(0xF0041A22),
                      borderRadius: BorderRadius.circular(48),
                      border: Border.all(
                        color: _OnboardingColors.neonGreen.withOpacity(0.25),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x8022B59B),
                          blurRadius: 40,
                          offset: Offset(0, 20),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 12),
                        Text(
                          'YAMAGO',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 8,
                            color: _OnboardingColors.titleText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '山手線リアル鬼ごっこ',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            letterSpacing: 5,
                            color: _OnboardingColors.mutedText,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Column(
                          children: [
                            _LandingButton(
                              label: 'ゲームに参加',
                              gradient: const LinearGradient(
                                colors: [
                                  _OnboardingColors.neonPink,
                                  Color(0xFF8D51FF),
                                ],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              onPressed: isReady
                                  ? () => context.push(JoinPage.routePath)
                                  : null,
                            ),
                            const SizedBox(height: 18),
                            _LandingButton(
                              label: 'ゲームを作成',
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF0CDCB5),
                                  Color(0xFF0CB3A4),
                                ],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              onPressed: isReady
                                  ? () => context.push(CreateGamePage.routePath)
                                  : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        Column(
                          children: [
                            Text('位置情報の使用に同意してください', style: mutedStyle),
                            const SizedBox(height: 4),
                            Text('山手線内でのみプレイ可能です', style: mutedStyle),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: -10,
                    left: 32,
                    right: 32,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: const LinearGradient(
                          colors: [
                            _OnboardingColors.neonGreen,
                            _OnboardingColors.neonGlow,
                            _OnboardingColors.neonPink,
                          ],
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0xAA5FFBF1),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isLoading)
            const Positioned.fill(
              child: _LoadingOverlay(message: '初期化中...'),
            ),
          if (initError != null)
            Positioned.fill(
              child: _InitErrorOverlay(
                error: initError,
                onRetry: () {
                  ref.invalidate(firebaseAppProvider);
                  ref.invalidate(ensureAnonymousSignInProvider);
                },
              ),
            ),
        ],
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
  String? _inlineError;
  Uint8List? _avatarBytes;
  final ImagePicker _picker = ImagePicker();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nicknameController.dispose();
    _gameIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileStore = ref.watch(localProfileStoreProvider);

    profileStore.whenData((store) {
      if (_prefilled) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _prefilled) return;
        _nicknameController.clear();
        _gameIdController.clear();
        _prefilled = true;
      });
    });

    return Scaffold(
      backgroundColor: _OnboardingColors.background,
      body: _NeonBackground(
        enableScroll: true,
        glows: const [
          _GlowSpec(
            alignment: Alignment.topLeft,
            size: 260,
            offset: Offset(-90, -60),
          ),
          _GlowSpec(
            alignment: Alignment.bottomRight,
            size: 300,
            offset: Offset(100, 80),
          ),
        ],
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _NeonCard(
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BackHeader(
                      onBack: () => context.pop(),
                      label: 'JOIN NETWORK',
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Column(
                        children: const [
                          Text(
                            'ゲームに参加',
                            style: TextStyle(
                              color: _OnboardingColors.titleText,
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 6,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Yamago Multiplayer Portal',
                            style: TextStyle(
                              color: _OnboardingColors.mutedText,
                              letterSpacing: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _InputLabel('プロフィール画像（任意）'),
                          const SizedBox(height: 10),
                          _AvatarPicker(
                            imageBytes: _avatarBytes,
                            onPickGallery: () =>
                                _pickAvatar(ImageSource.gallery),
                            onPickCamera: () => _pickAvatar(ImageSource.camera),
                            onRemove: () {
                              setState(() {
                                _avatarBytes = null;
                              });
                            },
                          ),
                          const SizedBox(height: 28),
                          const _InputLabel('ニックネーム'),
                          TextFormField(
                            controller: _nicknameController,
                            decoration: _inputDecoration('あなたのニックネーム'),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty)
                                    ? 'ニックネームを入力してください'
                                    : null,
                          ),
                          const SizedBox(height: 20),
                          const _InputLabel('ゲームID'),
                          TextFormField(
                            controller: _gameIdController,
                            decoration: _inputDecoration('ゲームIDを入力'),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty)
                                    ? 'ゲームIDを入力してください'
                                    : null,
                          ),
                          if (_inlineError != null) ...[
                            const SizedBox(height: 20),
                            _ErrorBanner(message: _inlineError!),
                          ],
                          const SizedBox(height: 24),
                          FilledButton(
                            style:
                                _primaryButtonStyle(_OnboardingColors.neonPink),
                            onPressed: _isSubmitting ? null : _handleJoin,
                            child: Text(
                              _isSubmitting ? '参加中...' : 'ゲームに参加',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    const _FooterNotices(
                      alignCenter: false,
                      lines: [
                        '位置情報の使用に同意してください',
                        '山手線内でのみプレイ可能です',
                      ],
                    ),
                  ],
                ),
                if (_isSubmitting)
                  const Positioned.fill(
                    child: _LoadingOverlay(message: '処理中...'),
                  ),
              ],
            ),
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
    setState(() {
      _inlineError = null;
      _isSubmitting = true;
    });
    try {
      final user = await ref.read(ensureAnonymousSignInProvider.future);
      await controller.joinGame(
        gameId: gameId,
        nickname: nickname,
        uid: user.uid,
        avatarBytes: _avatarBytes,
      );
      if (!mounted) return;
      _goToMap(gameId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _inlineError = '参加に失敗しました: $error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_inlineError!)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _avatarBytes = bytes;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('画像の読み込みに失敗しました: $error')),
      );
    }
  }

  void _goToMap(String gameId) {
    if (!mounted) return;
    context.goNamed(
      GameShellPage.routeName,
      pathParameters: {'gameId': gameId},
    );
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
  String? _errorMessage;
  bool _copied = false;
  Timer? _copyTimer;
  bool _isCreating = false;
  Uint8List? _avatarBytes;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _nicknameController.dispose();
    _copyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileStore = ref.watch(localProfileStoreProvider);

    profileStore.whenData((store) {
      if (_prefilled) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _prefilled) return;
        _nicknameController.clear();
        _prefilled = true;
      });
    });

    if (_createdGameId != null) {
      return Scaffold(
        backgroundColor: _OnboardingColors.background,
        body: _NeonBackground(
          glows: const [
            _GlowSpec(
              alignment: Alignment.topRight,
              size: 320,
              offset: Offset(90, -80),
            ),
            _GlowSpec(
              alignment: Alignment.bottomLeft,
              size: 320,
              offset: Offset(-80, 90),
            ),
          ],
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _NeonCard(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _BackHeader(
                      onBack: () => context.pop(),
                      label: 'SESSION DEPLOYED',
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _OnboardingColors.neonGreen.withOpacity(0.4),
                        ),
                        color: _OnboardingColors.surfaceAccent,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x3322B59B),
                            blurRadius: 24,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: _OnboardingColors.neonGreen,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'ゲームを作成しました',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _OnboardingColors.titleText,
                        fontSize: 26,
                        letterSpacing: 6,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Share The Access Code',
                      style: TextStyle(
                        color: _OnboardingColors.mutedText,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _InputLabel('ゲームID'),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 20,
                          ),
                          decoration: BoxDecoration(
                            color: _OnboardingColors.surfaceAccent,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color:
                                  _OnboardingColors.neonGreen.withOpacity(0.4),
                            ),
                          ),
                          child: SelectableText(
                            _createdGameId!,
                            style: const TextStyle(
                              color: _OnboardingColors.neonGlow,
                              fontFamily: 'monospace',
                              letterSpacing: 3,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                _OnboardingColors.neonGlow.withOpacity(0.9),
                            foregroundColor: Colors.black,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 3,
                            ),
                          ),
                          onPressed: _handleCopyGameId,
                          child: Text(_copied ? 'コピー済み' : 'コピー'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _OnboardingColors.surfaceAccent,
                        border: Border.all(
                          color: _OnboardingColors.neonGreen.withOpacity(0.35),
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const _FooterNotices(
                        alignCenter: false,
                        lines: [
                          'ゲームが正常に保存されました',
                          'あなたは鬼として参加しています',
                          '他のプレイヤーにゲームIDを共有してください',
                          'ゲーム開始するには「ゲーム開始」を押してください',
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      style: _accentButtonStyle(),
                      onPressed: () {
                        final gameId = _createdGameId;
                        if (gameId == null) return;
                        unawaited(_navigateToGame(gameId));
                      },
                      child: const Text('ゲームを開始'),
                    ),
                    const SizedBox(height: 24),
                    const _FooterNotices(
                      alignCenter: false,
                      lines: [
                        '位置情報の使用に同意してください',
                        '山手線内でのみプレイ可能です',
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _OnboardingColors.background,
      body: _NeonBackground(
        enableScroll: true,
        glows: const [
          _GlowSpec(
            alignment: Alignment.topLeft,
            size: 260,
            offset: Offset(-100, -60),
          ),
          _GlowSpec(
            alignment: Alignment.bottomRight,
            size: 320,
            offset: Offset(120, 100),
          ),
        ],
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _NeonCard(
            child: Stack(
              children: [
                SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _BackHeader(
                        onBack: () => context.pop(),
                        label: 'CREATE SESSION',
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Column(
                          children: const [
                            Text(
                              'ゲームを作成',
                              style: TextStyle(
                                color: _OnboardingColors.titleText,
                                fontSize: 26,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 6,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Launch The Yamago Arena',
                              style: TextStyle(
                                color: _OnboardingColors.mutedText,
                                letterSpacing: 4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _InputLabel('プロフィール画像（任意）'),
                            const SizedBox(height: 10),
                            _AvatarPicker(
                              imageBytes: _avatarBytes,
                              onPickGallery: () =>
                                  _pickAvatar(ImageSource.gallery),
                              onPickCamera: () =>
                                  _pickAvatar(ImageSource.camera),
                              onRemove: () {
                                setState(() {
                                  _avatarBytes = null;
                                });
                              },
                            ),
                            const SizedBox(height: 28),
                            const _InputLabel('ニックネーム'),
                            TextFormField(
                              controller: _nicknameController,
                              decoration: _inputDecoration('あなたのニックネーム'),
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                      ? 'ニックネームを入力してください'
                                      : null,
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 20),
                              _ErrorBanner(message: _errorMessage!),
                            ],
                            const SizedBox(height: 24),
                            FilledButton(
                              style: _primaryButtonStyle(
                                  _OnboardingColors.neonGreen),
                              onPressed: _isCreating ? null : _handleCreate,
                              child: Text(
                                _isCreating ? '作成中...' : 'ゲームを作成',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      const _FooterNotices(
                        alignCenter: false,
                        lines: [
                          'ゲーム作成者は鬼になります',
                          '位置情報の使用に同意してください',
                          '山手線内でのみプレイ可能です',
                        ],
                      ),
                    ],
                  ),
                ),
                if (_isCreating)
                  const Positioned.fill(
                    child: _LoadingOverlay(message: '作成中...'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleCreate() async {
    if (!_formKey.currentState!.validate()) return;
    final nickname = _nicknameController.text.trim();
    final controller = ref.read(onboardingControllerProvider.notifier);
    setState(() {
      _errorMessage = null;
      _isCreating = true;
    });
    try {
      final user = await ref.read(ensureAnonymousSignInProvider.future);
      final gameId = await controller.createGame(
        nickname: nickname,
        ownerUid: user.uid,
        avatarBytes: _avatarBytes,
      );
      if (!mounted) return;
      setState(() {
        _createdGameId = gameId;
        _copied = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ゲームを作成しました: $gameId')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'ゲーム作成に失敗しました: $error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ゲーム作成に失敗しました: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _avatarBytes = bytes;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('画像の読み込みに失敗しました: $error')),
      );
    }
  }

  Future<void> _handleCopyGameId() async {
    final gameId = _createdGameId;
    if (gameId == null) return;
    await Clipboard.setData(ClipboardData(text: gameId));
    _copyTimer?.cancel();
    setState(() {
      _copied = true;
    });
    _copyTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _copied = false;
        });
      }
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('ゲームIDをコピーしました: $gameId')),
    );
  }

  Future<void> _navigateToGame(String gameId) async {
    await ref.read(ensureAnonymousSignInProvider.future);
    if (!mounted) return;
    context.goNamed(
      GameShellPage.routeName,
      pathParameters: {'gameId': gameId},
    );
  }
}

class _InputLabel extends StatelessWidget {
  const _InputLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: _OnboardingColors.mutedText,
        fontSize: 12,
        letterSpacing: 4,
      ),
    );
  }
}

class _FooterNotices extends StatelessWidget {
  const _FooterNotices({
    required this.lines,
    this.alignCenter = true,
  });

  final List<String> lines;
  final bool alignCenter;

  @override
  Widget build(BuildContext context) {
    final textAlign = alignCenter ? TextAlign.center : TextAlign.left;
    return Column(
      crossAxisAlignment:
          alignCenter ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: lines
          .map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                line.toUpperCase(),
                textAlign: textAlign,
                style: const TextStyle(
                  color: _OnboardingColors.mutedText,
                  fontSize: 11,
                  letterSpacing: 3,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF2A0B1D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _OnboardingColors.neonPink.withOpacity(0.5),
        ),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _OnboardingColors.neonPink,
          letterSpacing: 2.5,
        ),
      ),
    );
  }
}

class _BackHeader extends StatelessWidget {
  const _BackHeader({
    required this.onBack,
    required this.label,
  });

  final VoidCallback onBack;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton.icon(
          onPressed: onBack,
          style: TextButton.styleFrom(
            foregroundColor: _OnboardingColors.mutedText,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: _OnboardingColors.neonGreen.withOpacity(0.3),
              ),
            ),
            textStyle: const TextStyle(
              letterSpacing: 3,
              fontWeight: FontWeight.w600,
            ),
          ),
          icon: const Icon(Icons.arrow_back_ios_new, size: 16),
          label: const Text('戻る'),
        ),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: _OnboardingColors.mutedText,
            letterSpacing: 4,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: _OnboardingColors.neonGlow,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            message.toUpperCase(),
            style: const TextStyle(
              color: _OnboardingColors.neonGlow,
              letterSpacing: 4,
            ),
          ),
        ],
      ),
    );
  }
}

class _InitErrorOverlay extends StatelessWidget {
  const _InitErrorOverlay({
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: Colors.black.withOpacity(0.75),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Card(
          color: theme.colorScheme.surface.withOpacity(0.95),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 48, color: _OnboardingColors.neonPink),
                const SizedBox(height: 16),
                const Text(
                  '初期化に失敗しました',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('再試行'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NeonBackground extends StatelessWidget {
  const _NeonBackground({
    required this.child,
    this.glows = const [],
    this.enableScroll = false,
    this.centerContent = true,
  });

  final Widget child;
  final List<_GlowSpec> glows;
  final bool enableScroll;
  final bool centerContent;

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(
      padding: const EdgeInsets.all(24),
      child: child,
    );

    if (enableScroll) {
      content = SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Align(
          alignment: centerContent ? Alignment.center : Alignment.topCenter,
          child: content,
        ),
      );
    } else {
      content = Align(
        alignment: centerContent ? Alignment.center : Alignment.topCenter,
        child: content,
      );
    }

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: _OnboardingColors.background,
      ),
      child: Stack(
        children: [
          ...glows.map((spec) => _GlowBlob(spec: spec)),
          SafeArea(child: content),
        ],
      ),
    );
  }
}

class _GlowSpec {
  const _GlowSpec({
    required this.alignment,
    required this.size,
    this.opacity = 0.35,
    this.offset = Offset.zero,
    this.colors = const [
      _OnboardingColors.neonGreen,
      _OnboardingColors.neonGlow,
      _OnboardingColors.neonPink,
    ],
  });

  final Alignment alignment;
  final double size;
  final double opacity;
  final Offset offset;
  final List<Color> colors;
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.spec});

  final _GlowSpec spec;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: spec.alignment,
      child: Transform.translate(
        offset: spec.offset,
        child: IgnorePointer(
          child: Container(
            width: spec.size,
            height: spec.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: spec.colors
                    .map((c) => c.withOpacity(spec.opacity))
                    .toList(),
              ),
              boxShadow: [
                BoxShadow(
                  color: spec.colors.last.withOpacity(spec.opacity * 0.6),
                  blurRadius: spec.size * 0.4,
                  spreadRadius: spec.size * 0.1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NeonCard extends StatelessWidget {
  const _NeonCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF04161C),
                Color(0xFF010A0E),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: _OnboardingColors.neonGreen.withOpacity(0.3),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3322B59B),
                blurRadius: 40,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
        Positioned(
          left: 48,
          right: 48,
          top: -3,
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  _OnboardingColors.neonGreen,
                  _OnboardingColors.neonGlow,
                  _OnboardingColors.neonPink,
                ],
              ),
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x665FFBF1),
                  blurRadius: 18,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OnboardingColors {
  static const background = Color(0xFF010A0E);
  static const neonGreen = Color(0xFF22B59B);
  static const neonGlow = Color(0xFF5FFBF1);
  static const neonPink = Color(0xFFFF61A6);
  static const mutedText = Color(0xFFA9C6C2);
  static const titleText = Color(0xFFE6F7F4);
  static const surfaceAccent = Color(0xF0052028);
}

InputDecoration _inputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
      color: Color(0x805FFBF1),
      letterSpacing: 2,
    ),
    filled: true,
    fillColor: const Color(0xB903161C),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(
        color: _OnboardingColors.neonGreen.withOpacity(0.4),
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(
        color: _OnboardingColors.neonGreen.withOpacity(0.3),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(
        color: _OnboardingColors.neonGlow.withOpacity(0.8),
        width: 1.6,
      ),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
  );
}

ButtonStyle _primaryButtonStyle(Color color) {
  return FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(52),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
    ),
    backgroundColor: color,
    foregroundColor: Colors.white,
    textStyle: const TextStyle(
      fontWeight: FontWeight.w700,
      letterSpacing: 3,
    ),
  );
}

ButtonStyle _accentButtonStyle() {
  return FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(52),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
    ),
    backgroundColor: _OnboardingColors.neonGlow.withOpacity(0.9),
    foregroundColor: Colors.black,
    textStyle: const TextStyle(
      fontWeight: FontWeight.w700,
      letterSpacing: 3,
    ),
  );
}

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({
    required this.imageBytes,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onRemove,
  });

  final Uint8List? imageBytes;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showImageSourceSheet(context),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _OnboardingColors.surfaceAccent,
                      border: Border.all(
                        color: _OnboardingColors.neonGreen.withOpacity(0.4),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x3322B59B),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: imageBytes != null
                          ? Image.memory(
                              imageBytes!,
                              fit: BoxFit.cover,
                            )
                          : Icon(
                              Icons.person,
                              size: 40,
                              color:
                                  _OnboardingColors.mutedText.withOpacity(0.6),
                            ),
                    ),
                  ),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _OnboardingColors.neonGlow.withOpacity(0.6),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x5522B59B),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.camera_alt_outlined,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (imageBytes != null) ...[
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: onRemove,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _OnboardingColors.neonPink,
                  side: BorderSide(
                    color: _OnboardingColors.neonPink.withOpacity(0.4),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('リセット'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'タップして画像を設定',
          style: TextStyle(
            color: _OnboardingColors.mutedText.withOpacity(0.8),
            letterSpacing: 2,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  void _showImageSourceSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF04161E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                _ImageSourceTile(
                  icon: Icons.photo_library_outlined,
                  label: 'ライブラリから選択',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onPickGallery();
                  },
                ),
                const SizedBox(height: 12),
                _ImageSourceTile(
                  icon: Icons.photo_camera_outlined,
                  label: 'カメラで撮影',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onPickCamera();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ImageSourceTile extends StatelessWidget {
  const _ImageSourceTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: _OnboardingColors.neonGreen.withOpacity(0.15),
        ),
      ),
      tileColor: const Color(0x3305161C),
      leading: Icon(
        icon,
        color: _OnboardingColors.neonGlow,
      ),
      title: Text(
        label,
        style: const TextStyle(
          color: _OnboardingColors.titleText,
          letterSpacing: 2,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: _OnboardingColors.mutedText,
      ),
    );
  }
}

class _LandingButton extends StatelessWidget {
  const _LandingButton({
    required this.label,
    required this.gradient,
    required this.onPressed,
  });

  final String label;
  final Gradient gradient;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(32),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4C5FFBF1),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: isEnabled
                ? () {
                    _LandingButtonSound.play();
                    onPressed?.call();
                  }
                : null,
            splashColor: isEnabled ? null : Colors.transparent,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LandingButtonSound {
  static const _assetPath = 'sounds/button_sound2.mp3';
  static AudioPlayer? _player;
  static bool _isInitialized = false;

  static void play() {
    final player = _player ?? AudioPlayer(playerId: 'landing_button');
    _player = player;
    unawaited(_playInternal(player));
  }

  static Future<void> _playInternal(AudioPlayer player) async {
    try {
      if (!_isInitialized) {
        await player.setReleaseMode(ReleaseMode.release);
        _isInitialized = true;
      }
      await player.stop();
      await player.play(AssetSource(_assetPath));
    } catch (error) {
      debugPrint('Failed to play landing button sound: $error');
    }
  }
}

ButtonStyle _landingButtonStyle(Gradient gradient) {
  return FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(60),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(32),
    ),
    padding: EdgeInsets.zero,
  ).merge(
    ButtonStyle(
      backgroundColor: MaterialStateProperty.all(Colors.transparent),
      foregroundColor: MaterialStateProperty.all(Colors.white),
      textStyle: MaterialStateProperty.all(
        const TextStyle(
          fontWeight: FontWeight.bold,
          letterSpacing: 3,
          fontSize: 16,
        ),
      ),
      overlayColor: MaterialStateProperty.resolveWith(
        (states) => states.contains(MaterialState.pressed)
            ? Colors.white.withOpacity(0.12)
            : null,
      ),
      elevation: MaterialStateProperty.all(8),
      shape: MaterialStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
        ),
      ),
      shadowColor: MaterialStateProperty.all(
        const Color(0x805FFBF1),
      ),
    ),
  );
}
