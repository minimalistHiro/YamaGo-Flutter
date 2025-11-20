import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:yamago_flutter/core/location/location_service.dart';
import 'package:yamago_flutter/core/location/yamanote_constants.dart';
import 'package:yamago_flutter/core/services/firebase_providers.dart';
import 'package:yamago_flutter/core/storage/local_profile_store.dart';
import 'package:yamago_flutter/features/game/application/game_exit_controller.dart';
import 'package:yamago_flutter/features/chat/application/chat_providers.dart';
import 'package:yamago_flutter/features/chat/data/chat_repository.dart';
import 'package:yamago_flutter/features/chat/domain/chat_message.dart';
import 'package:yamago_flutter/features/game/application/player_location_updater.dart';
import 'package:yamago_flutter/features/game/application/player_providers.dart';
import 'package:yamago_flutter/features/game/data/game_repository.dart';
import 'package:yamago_flutter/features/game/domain/player.dart';
import 'package:yamago_flutter/features/game/presentation/game_settings_page.dart';
import 'package:yamago_flutter/features/game/presentation/widgets/game_status_banner.dart';
import 'package:yamago_flutter/features/game/presentation/widgets/player_hud.dart';
import 'package:yamago_flutter/features/game/presentation/widgets/player_list_card.dart';
import 'package:yamago_flutter/features/game/presentation/widgets/player_profile_card.dart';
import 'package:yamago_flutter/features/onboarding/presentation/onboarding_pages.dart';
import 'package:yamago_flutter/features/pins/presentation/pin_editor_page.dart';

class GameShellPage extends StatefulWidget {
  const GameShellPage({
    super.key,
    required this.gameId,
  });

  static const routeName = 'game-shell';
  static const routePath = '/game/:gameId';
  static String location(String gameId) => '/game/$gameId';

  final String gameId;

  @override
  State<GameShellPage> createState() => _GameShellPageState();
}

class _GameShellPageState extends State<GameShellPage> {
  int _currentIndex = 0;

  void _handleTabSelected(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sections = [
      GameMapSection(gameId: widget.gameId),
      GameChatSection(gameId: widget.gameId),
      GameSettingsSection(gameId: widget.gameId),
    ];

    final titles = ['マップ', 'チャット', '設定'];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_currentIndex]),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: sections,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _handleTabSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'マップ',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'チャット',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
    );
  }
}

class GameMapSection extends ConsumerStatefulWidget {
  const GameMapSection({super.key, required this.gameId});

  final String gameId;

  @override
  ConsumerState<GameMapSection> createState() => _GameMapSectionState();
}

class _GameMapSectionState extends ConsumerState<GameMapSection> {
  GoogleMapController? _mapController;
  LatLng _cameraTarget = yamanoteCenter;

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final permissionState = ref.watch(locationPermissionStatusProvider);
    final locationState = ref.watch(locationStreamProvider);
    final playersState = ref.watch(playersStreamProvider(widget.gameId));
    final gameState = ref.watch(gameStreamProvider(widget.gameId));
    ref.watch(playerLocationUpdaterProvider(widget.gameId));

    ref.listen(locationStreamProvider, (previous, next) {
      next.whenData((position) {
        final latLng = LatLng(position.latitude, position.longitude);
        _cameraTarget = latLng;
        unawaited(
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(latLng),
          ),
        );
      });
    });

    final markers = _buildMarkers(locationState, playersState);

    final overlay = _buildPermissionOverlay(
      context,
      permissionState,
      locationState,
    );

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _cameraTarget,
            zoom: 12.5,
          ),
          onMapCreated: (controller) {
            _mapController ??= controller;
          },
          myLocationEnabled: locationState.hasValue,
          myLocationButtonEnabled: false,
          compassEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          markers: markers,
          padding: const EdgeInsets.only(bottom: 96),
        ),
        if (overlay != null) overlay,
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GameStatusBanner(gameState: gameState, gameId: widget.gameId),
              const SizedBox(height: 8),
              PlayerHud(playersState: playersState),
            ],
          ),
        ),
      ],
    );
  }

  Set<Marker> _buildMarkers(
    AsyncValue<Position> locationState,
    AsyncValue<List<Player>> playersState,
  ) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('center'),
        position: yamanoteCenter,
        infoWindow: const InfoWindow(title: '山手線中心'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
    };

    locationState.whenData((position) {
      markers.add(
        Marker(
          markerId: const MarkerId('you'),
          position: LatLng(position.latitude, position.longitude),
          infoWindow: const InfoWindow(title: 'あなた'),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    });

    playersState.whenData((players) {
      for (final player in players) {
        final position = player.position;
        if (position == null) continue;
        markers.add(
          Marker(
            markerId: MarkerId('player-${player.uid}'),
            position: position,
            infoWindow: InfoWindow(title: player.nickname),
            icon: _markerForPlayer(player),
          ),
        );
      }
    });

    return markers;
  }

  BitmapDescriptor _markerForPlayer(Player player) {
    const oniHue = BitmapDescriptor.hueRed;
    const runnerHue = BitmapDescriptor.hueGreen;
    const downedHue = BitmapDescriptor.hueOrange;

    if (player.role == PlayerRole.oni) {
      return BitmapDescriptor.defaultMarkerWithHue(oniHue);
    }
    if (player.status == PlayerStatus.downed) {
      return BitmapDescriptor.defaultMarkerWithHue(downedHue);
    }
    return BitmapDescriptor.defaultMarkerWithHue(runnerHue);
  }

  Widget? _buildPermissionOverlay(
    BuildContext context,
    AsyncValue<LocationPermissionStatus> permissionState,
    AsyncValue<Position> locationState,
  ) {
    return permissionState.when(
      data: (status) {
        if (status == LocationPermissionStatus.granted) {
          if (locationState.isLoading) {
            return const _InfoBanner(
              message: '現在地を取得しています...',
              actionLabel: null,
              onActionTap: null,
            );
          }
          return null;
        }

        final (message, actionLabel, action) = switch (status) {
          LocationPermissionStatus.denied => (
              '位置情報の権限が必要です。設定を確認してください。',
              '権限を許可',
              () async {
                await Geolocator.requestPermission();
                ref.invalidate(locationPermissionStatusProvider);
              }
            ),
          LocationPermissionStatus.deniedForever => (
              '位置情報の権限が永久に拒否されています。アプリの設定から許可してください。',
              '設定を開く',
              Geolocator.openAppSettings,
            ),
          LocationPermissionStatus.serviceDisabled => (
              '位置情報サービスが無効です。端末の設定で有効にしてください。',
              '設定を開く',
              Geolocator.openLocationSettings,
            ),
          LocationPermissionStatus.granted => (
              '',
              null,
              null,
            ),
        };

        return _InfoBanner(
          message: message,
          actionLabel: actionLabel,
          onActionTap: action == null
              ? null
              : () async {
                  await action();
                  ref.invalidate(locationPermissionStatusProvider);
                },
        );
      },
      loading: () => const _InfoBanner(
        message: '位置情報の権限を確認しています...',
        actionLabel: null,
        onActionTap: null,
      ),
      error: (error, stackTrace) => _InfoBanner(
        message: '権限の確認でエラーが発生しました: $error',
        actionLabel: '再試行',
        onActionTap: () {
          ref.invalidate(locationPermissionStatusProvider);
        },
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.message,
    required this.actionLabel,
    required this.onActionTap,
  });

  final String message;
  final String? actionLabel;
  final FutureOr<void> Function()? onActionTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: 16,
      right: 16,
      bottom: 24,
      child: Card(
        color: theme.colorScheme.surface.withOpacity(0.9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: theme.textTheme.bodyMedium,
              ),
              if (actionLabel != null && onActionTap != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onActionTap,
                    child: Text(actionLabel!),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class GameChatSection extends ConsumerStatefulWidget {
  const GameChatSection({super.key, required this.gameId});

  final String gameId;

  @override
  ConsumerState<GameChatSection> createState() => _GameChatSectionState();
}

class _GameChatSectionState extends ConsumerState<GameChatSection> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(firebaseAuthProvider);
    final user = auth.currentUser;
    if (user == null) {
      return const Center(child: Text('サインインが必要です'));
    }

    final playerState = ref.watch(
      playerStreamProvider((gameId: widget.gameId, uid: user.uid)),
    );

    return playerState.when(
      data: (player) {
        if (player == null) {
          return const Center(child: Text('プレイヤー情報が見つかりません'));
        }
        final chatState = ref.watch(
          chatMessagesProvider(
            (gameId: widget.gameId, role: player.role),
          ),
        );
        return Column(
          children: [
            Expanded(
              child: chatState.when(
                data: (messages) {
                  if (messages.isEmpty) {
                    return const Center(child: Text('まだメッセージがありません'));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return ListTile(
                        title: Text(message.nickname),
                        subtitle: Text(message.message),
                        trailing: Text(
                          TimeOfDay.fromDateTime(message.timestamp)
                              .format(context),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) =>
                    Center(child: Text('チャット取得に失敗しました: $error')),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: 'メッセージを入力',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed:
                          _sending ? null : () => _sendMessage(context, player),
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text('プレイヤー情報の取得に失敗しました: $error'),
      ),
    );
  }

  Future<void> _sendMessage(BuildContext context, Player player) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _sending = true;
    });
    try {
      final repo = ref.read(chatRepositoryProvider);
      final auth = ref.read(firebaseAuthProvider);
      final user = auth.currentUser;
      if (user == null) return;
      await repo.sendMessage(
        gameId: widget.gameId,
        role: player.role == PlayerRole.oni ? ChatRole.oni : ChatRole.runner,
        uid: user.uid,
        nickname: player.nickname,
        message: text,
      );
      _controller.clear();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('送信に失敗しました: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }
}

class GameSettingsSection extends ConsumerWidget {
  const GameSettingsSection({super.key, required this.gameId});

  final String gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(firebaseAuthProvider);
    final user = auth.currentUser;
    if (user == null) {
      return const Center(child: Text('サインイン情報を取得できません'));
    }

    final gameState = ref.watch(gameStreamProvider(gameId));
    final playerState = ref.watch(
      playerStreamProvider((gameId: gameId, uid: user.uid)),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: playerState.when(
          data: (player) {
            if (player == null) {
              return const Center(child: Text('プレイヤー情報が見つかりません'));
            }
            final canManage = gameState.maybeWhen(
              data: (game) => game?.ownerUid == player.uid,
              orElse: () => false,
            );
            return ListView(
              children: [
                PlayerProfileCard(player: player, gameId: gameId),
                const SizedBox(height: 16),
                PlayerListCard(
                  gameId: gameId,
                  canManage: canManage,
                  ownerUid: gameState.value?.ownerUid ?? '',
                  currentUid: user.uid,
                ),
                if (canManage) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.tune),
                      title: const Text('ゲーム設定'),
                      subtitle: const Text('発電所数や視認距離、カウントダウンなどを調整'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        context.push(GameSettingsPage.path(gameId));
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.edit_location_alt_outlined),
                      title: const Text('発電所ピンを直接編集'),
                      subtitle: const Text('ドラッグ&ドロップで集合地点を微調整できます'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        context.push(PinEditorPage.path(gameId));
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _ActionButtons(
                  gameId: gameId,
                  ownerUid: gameState.value?.ownerUid ?? '',
                  currentUid: user.uid,
                ),
                const SizedBox(height: 16),
                const PrivacyReminderCard(),
              ],
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(),
          ),
          error: (error, _) => Center(
            child: Text('プレイヤー情報の取得に失敗しました: $error'),
          ),
        ),
      ),
    );
  }
}

class _ActionButtons extends ConsumerStatefulWidget {
  const _ActionButtons({
    required this.gameId,
    required this.ownerUid,
    required this.currentUid,
  });

  final String gameId;
  final String ownerUid;
  final String currentUid;

  @override
  ConsumerState<_ActionButtons> createState() => _ActionButtonsState();
}

class _ActionButtonsState extends ConsumerState<_ActionButtons> {
  bool _isLeaving = false;
  bool _isClaimingOwner = false;

  bool get _isOwner => widget.ownerUid == widget.currentUid;

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: widget.gameId));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('ゲームIDをコピーしました')),
            );
          },
          icon: const Icon(Icons.copy),
          label: const Text('ゲームIDをコピー'),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () async {
            final store = await ref.read(localProfileStoreProvider.future);
            await store.clearProfile();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ローカルニックネーム情報を削除しました')),
              );
            }
          },
          icon: const Icon(Icons.refresh),
          label: const Text('端末に保存されたニックネームをリセット'),
        ),
        const SizedBox(height: 8),
        if (!_isOwner) ...[
          ElevatedButton.icon(
            onPressed: _isClaimingOwner
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('オーナー権限を取得'),
                        content: const Text('自分をゲームのオーナーに変更します。よろしいですか？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('キャンセル'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('取得する'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    setState(() {
                      _isClaimingOwner = true;
                    });
                    try {
                      final repo = ref.read(gameRepositoryProvider);
                      await repo.updateOwner(
                        gameId: widget.gameId,
                        newOwnerUid: widget.currentUid,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('オーナー権限を取得しました')),
                        );
                      }
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('権限の取得に失敗しました: $error')),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() {
                          _isClaimingOwner = false;
                        });
                      }
                    }
                  },
            icon: _isClaimingOwner
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.verified_user),
            label: const Text('自分をオーナーにする'),
          ),
          const SizedBox(height: 8),
        ],
        ElevatedButton.icon(
          onPressed: _isLeaving
              ? null
              : () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('ゲームから退出'),
                      content: const Text('現在のゲームから退出し、ログアウトします。よろしいですか？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('キャンセル'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('退出'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  final router = GoRouter.of(context);
                  setState(() {
                    _isLeaving = true;
                  });
                  try {
                    final controller = ref.read(gameExitControllerProvider);
                    await controller.leaveGame(gameId: widget.gameId);
                    router.goNamed(WelcomePage.routeName);
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('退出に失敗しました: $error')),
                      );
                    }
                  } finally {
                    if (mounted) {
                      setState(() {
                        _isLeaving = false;
                      });
                    }
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
          ),
          icon: _isLeaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.logout),
          label: const Text('ログアウト'),
        ),
      ],
    );
  }
}

class PrivacyReminderCard extends StatelessWidget {
  const PrivacyReminderCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '位置情報とプライバシー',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'YamaGo ではゲーム成立のためにあなたの現在地を共有します。'
              'App Store 向け説明文例: 「リアルタイムで鬼ごっこを成立させるため、'
              'プレイヤーの現在地を取得・共有します。他のプレイヤーにはゲームルールで'
              '許可された範囲のみ表示されます。」',
            ),
          ],
        ),
      ),
    );
  }
}
