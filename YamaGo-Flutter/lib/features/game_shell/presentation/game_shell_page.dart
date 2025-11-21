import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:yamago_flutter/core/location/location_service.dart';
import 'package:yamago_flutter/core/location/yamanote_constants.dart';
import 'package:yamago_flutter/core/services/firebase_providers.dart';
import 'package:yamago_flutter/features/auth/application/auth_providers.dart';
import 'package:yamago_flutter/features/game/application/game_control_controller.dart';
import 'package:yamago_flutter/features/game/application/game_exit_controller.dart';
import 'package:intl/intl.dart';

import 'package:yamago_flutter/features/chat/application/chat_providers.dart';
import 'package:yamago_flutter/features/chat/data/chat_repository.dart';
import 'package:yamago_flutter/features/chat/domain/chat_message.dart';
import 'package:yamago_flutter/features/game/application/player_location_updater.dart';
import 'package:yamago_flutter/features/game/application/player_providers.dart';
import 'package:yamago_flutter/features/game/data/capture_repository.dart';
import 'package:yamago_flutter/features/game/data/game_repository.dart';
import 'package:yamago_flutter/features/game/domain/game.dart';
import 'package:yamago_flutter/features/game/domain/player.dart';
import 'package:yamago_flutter/features/game/presentation/game_settings_page.dart';
import 'package:yamago_flutter/features/game/presentation/player_profile_edit_page.dart';
import 'package:yamago_flutter/features/game/presentation/role_assignment_page.dart';
import 'package:yamago_flutter/features/game/presentation/widgets/game_status_banner.dart';
import 'package:yamago_flutter/features/game/presentation/widgets/player_hud.dart';
import 'package:yamago_flutter/features/game/presentation/widgets/player_list_card.dart';
import 'package:yamago_flutter/features/game/presentation/widgets/player_profile_card.dart';
import 'package:yamago_flutter/features/onboarding/presentation/onboarding_pages.dart';
import 'package:yamago_flutter/features/pins/application/pin_providers.dart';
import 'package:yamago_flutter/features/pins/domain/pin_point.dart';
import 'package:yamago_flutter/features/pins/presentation/pin_editor_page.dart';

class GameShellPage extends ConsumerStatefulWidget {
  const GameShellPage({
    super.key,
    required this.gameId,
  });

  static const routeName = 'game-shell';
  static const routePath = '/game/:gameId';
  static String location(String gameId) => '/game/$gameId';

  final String gameId;

  @override
  ConsumerState<GameShellPage> createState() => _GameShellPageState();
}

class _GameShellPageState extends ConsumerState<GameShellPage> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_ensureSignedIn());
  }

  void _handleTabSelected(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  Future<void> _ensureSignedIn() async {
    try {
      await ref.read(ensureAnonymousSignInProvider.future);
    } catch (error, stackTrace) {
      debugPrint('Failed to ensure FirebaseAuth sign-in: $error');
      debugPrint('$stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = [
      GameMapSection(gameId: widget.gameId),
      GameChatSection(gameId: widget.gameId),
      GameSettingsSection(gameId: widget.gameId),
    ];

    final titles = ['マップ', 'チャット', '設定'];

    AppBar? appBar;
    if (_currentIndex != 1) {
      appBar = AppBar(
        title: Text(titles[_currentIndex]),
      );
    }

    return Scaffold(
      appBar: appBar,
      extendBodyBehindAppBar: _currentIndex == 1,
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
  LatLng? _latestUserLocation;
  Timer? _statusTicker;
  bool _isStatusTickerActive = false;
  bool _countdownAutoStartTriggered = false;
  bool _isLocatingUser = false;
  bool _isCapturing = false;
  BitmapDescriptor? _downedMarkerDescriptor;
  BitmapDescriptor? _oniMarkerDescriptor;
  BitmapDescriptor? _runnerMarkerDescriptor;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCustomMarkers());
  }

  @override
  void dispose() {
    _statusTicker?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final permissionState = ref.watch(locationPermissionStatusProvider);
    final locationState = ref.watch(locationStreamProvider);
    final playersState = ref.watch(playersStreamProvider(widget.gameId));
    final pinsState = ref.watch(pinsStreamProvider(widget.gameId));
    final gameState = ref.watch(gameStreamProvider(widget.gameId));
    final auth = ref.watch(firebaseAuthProvider);
    ref.watch(playerLocationUpdaterProvider(widget.gameId));
    final players = playersState.valueOrNull;
    final currentUid = auth.currentUser?.uid;
    AsyncValue<Player?>? currentPlayerState;
    if (currentUid != null) {
      currentPlayerState = ref.watch(
        playerStreamProvider((gameId: widget.gameId, uid: currentUid)),
      );
    }

    ref.listen(locationStreamProvider, (previous, next) {
      next.whenData((position) {
        final latLng = LatLng(position.latitude, position.longitude);
        _cameraTarget = latLng;
        _latestUserLocation = latLng;
        unawaited(
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(latLng),
          ),
        );
      });
    });

    final game = gameState.valueOrNull;
    final captureRadius = game?.captureRadiusM?.toDouble();
    var currentPlayer = currentPlayerState?.valueOrNull;
    currentPlayer ??= _currentPlayer(playersState, currentUid);
    final circleColor = _captureCircleColor(currentPlayer);
    final circles =
        _buildCaptureCircles(locationState, captureRadius, circleColor);
    final latestPosition = locationState.valueOrNull;
    final selfLatLng = _latestUserLocation ??
        (latestPosition != null
            ? LatLng(latestPosition.latitude, latestPosition.longitude)
            : currentPlayer?.position);
    final captureTargetInfo = _findCaptureTarget(
      gameStatus: game?.status,
      currentPlayer: currentPlayer,
      captureRadiusMeters: captureRadius,
      selfPosition: selfLatLng,
      players: players,
    );
    final captureTarget = captureTargetInfo?.runner;
    final captureTargetDistance = captureTargetInfo?.distanceMeters;
    final playerMarkers = _buildPlayerMarkers(playersState, currentUid);
    final pinMarkers = _buildPinMarkers(
      pinsState: pinsState,
      game: game,
      currentRole: currentPlayer?.role,
      selfPosition: selfLatLng,
    );
    final markers = <Marker>{...playerMarkers, ...pinMarkers};

    final permissionOverlay = _buildPermissionOverlay(
      context,
      permissionState,
      locationState,
    );
    final countdownRemainingSeconds = game?.countdownRemainingSeconds;
    final runningRemainingSeconds = game?.runningRemainingSeconds;
    final isCountdownActive = game?.status == GameStatus.countdown &&
        countdownRemainingSeconds != null &&
        countdownRemainingSeconds > 0;
    final hasRunningCountdown =
        game?.status == GameStatus.running && (runningRemainingSeconds ?? 0) > 0;
    _updateStatusTicker(isCountdownActive || hasRunningCountdown);
    final countdownOverlay = _buildCountdownOverlay(
      context: context,
      isActive: isCountdownActive,
      remainingSeconds: countdownRemainingSeconds,
      role: currentPlayer?.role,
    );
    _maybeTriggerAutoStart(
      game: game,
      currentUid: currentUid,
      context: context,
      isCountdownActive: isCountdownActive,
      remainingSeconds: countdownRemainingSeconds,
    );

    final showStartButton = gameState.maybeWhen(
      data: (game) =>
          game != null &&
          currentUid == game.ownerUid &&
          (game.status == GameStatus.pending ||
              game.status == GameStatus.ended),
      orElse: () => false,
    );
    final countdownSeconds = gameState.maybeWhen(
      data: (game) => game?.countdownDurationSec ?? 900,
      orElse: () => 900,
    );
    final isLocationPermissionGranted = permissionState.maybeWhen(
      data: (status) => status == LocationPermissionStatus.granted,
      orElse: () => false,
    );
    final bool isMyLocationButtonEnabled =
        isLocationPermissionGranted && _mapController != null;
    final bool showCaptureButton = captureTarget != null;
    final double myLocationButtonBottom =
        (showStartButton || showCaptureButton) ? 120.0 : 24.0;
    final bool hasPrimaryAction = showStartButton || showCaptureButton;
    final double mapBottomPadding = hasPrimaryAction ? 64.0 : 16.0;

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _cameraTarget,
            zoom: 12.5,
          ),
          cameraTargetBounds: CameraTargetBounds(yamanoteBounds),
          onMapCreated: (controller) {
            _mapController ??= controller;
          },
          myLocationEnabled: locationState.hasValue,
          myLocationButtonEnabled: false,
          compassEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          markers: markers,
          circles: circles,
          padding: EdgeInsets.only(bottom: mapBottomPadding),
        ),
        if (permissionOverlay != null) permissionOverlay,
        if (countdownOverlay != null) countdownOverlay,
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GameStatusBanner(
                  gameState: gameState,
                  gameId: widget.gameId,
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: PlayerHud(playersState: playersState),
              ),
            ],
          ),
        ),
        if (showStartButton)
          Positioned(
            left: 24,
            right: 24,
            bottom: 24,
            child: _MapStartGameButton(
              gameId: widget.gameId,
              countdownSeconds: countdownSeconds,
            ),
          ),
        if (showCaptureButton && captureTarget != null)
          Positioned(
            left: 24,
            right: 24,
            bottom: 24,
            child: _CaptureActionButton(
              targetName: captureTarget.nickname,
              distanceMeters: captureTargetDistance,
              isLoading: _isCapturing,
              onPressed: _isCapturing
                  ? null
                  : () => _handleCapturePressed(captureTarget),
            ),
          ),
        Positioned(
          right: 16,
          bottom: myLocationButtonBottom,
          child: SafeArea(
            left: false,
            top: false,
            right: false,
            minimum: const EdgeInsets.only(bottom: 16),
            child: _MapMyLocationButton(
              isLoading: _isLocatingUser,
              onPressed: (!isMyLocationButtonEnabled || _isLocatingUser)
                  ? null
                  : _handleMyLocationButtonPressed,
            ),
          ),
        ),
      ],
    );
  }

  void _updateStatusTicker(bool shouldRun) {
    if (shouldRun && !_isStatusTickerActive) {
      _isStatusTickerActive = true;
      _statusTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
      });
      return;
    }
    if (!shouldRun && _isStatusTickerActive) {
      _statusTicker?.cancel();
      _statusTicker = null;
      _isStatusTickerActive = false;
    }
  }

  void _maybeTriggerAutoStart({
    required Game? game,
    required String? currentUid,
    required BuildContext context,
    required bool isCountdownActive,
    required int? remainingSeconds,
  }) {
    if (game == null ||
        currentUid == null ||
        game.status != GameStatus.countdown ||
        game.ownerUid != currentUid) {
      _countdownAutoStartTriggered = false;
      return;
    }
    if (isCountdownActive) {
      _countdownAutoStartTriggered = false;
      return;
    }
    if (remainingSeconds == null) {
      _countdownAutoStartTriggered = false;
      return;
    }
    if (remainingSeconds <= 0 && !_countdownAutoStartTriggered) {
      _countdownAutoStartTriggered = true;
      unawaited(
        _startGameAfterCountdown(
          context,
          pinCount: game.pinCount,
        ),
      );
    }
  }

  Future<void> _startGameAfterCountdown(
    BuildContext context, {
    int? pinCount,
  }) async {
    try {
      final controller = ref.read(gameControlControllerProvider);
      await controller.startGame(
        gameId: widget.gameId,
        pinCount: pinCount,
      );
    } catch (error) {
      _countdownAutoStartTriggered = false;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ゲーム開始に失敗しました: $error')),
        );
      }
    }
  }

  Future<void> _handleMyLocationButtonPressed() async {
    if (_mapController == null || _isLocatingUser) {
      return;
    }
    setState(() {
      _isLocatingUser = true;
    });
    try {
      final status = await ref.read(locationPermissionStatusProvider.future);
      if (status != LocationPermissionStatus.granted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('現在地を取得するには位置情報の権限を許可してください。'),
          ),
        );
        return;
      }
      LatLng? target = _latestUserLocation;
      if (target == null) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        target = LatLng(position.latitude, position.longitude);
      }
      if (target == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('現在地情報がまだ取得できていません。')),
        );
        return;
      }
      _latestUserLocation = target;
      _cameraTarget = target;
      await _mapController?.animateCamera(
        CameraUpdate.newLatLng(target),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('現在地の取得に失敗しました: $error')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isLocatingUser = false;
      });
    }
  }

  Future<void> _handleCapturePressed(Player target) async {
    if (_isCapturing) {
      return;
    }
    final auth = ref.read(firebaseAuthProvider);
    final attackerUid = auth.currentUser?.uid;
    if (attackerUid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('サインイン情報を確認できませんでした')),
      );
      return;
    }
    setState(() {
      _isCapturing = true;
    });
    try {
      final repo = ref.read(captureRepositoryProvider);
      await repo.captureRunner(
        gameId: widget.gameId,
        attackerUid: attackerUid,
        victimUid: target.uid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${target.nickname} を捕獲しました')),
        );
      }
    } catch (error) {
      if (mounted) {
        final message = error is StateError ? error.message : error.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('捕獲に失敗しました: $message')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  Future<void> _loadCustomMarkers() async {
    try {
      final results = await Future.wait([
        _createMarkerDescriptor(
          color: Colors.redAccent,
          icon: Icons.whatshot,
        ),
        _createMarkerDescriptor(
          color: Colors.green,
          icon: Icons.run_circle,
        ),
        _createMarkerDescriptor(
          color: Colors.grey.shade600,
          icon: Icons.run_circle,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _oniMarkerDescriptor = results[0];
        _runnerMarkerDescriptor = results[1];
        _downedMarkerDescriptor = results[2];
      });
    } catch (error) {
      debugPrint('Failed to load custom markers: $error');
    }
  }

  Future<BitmapDescriptor> _createMarkerDescriptor({
    required Color color,
    required IconData icon,
  }) async {
    const double width = 96;
    const double height = 132;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final fillPaint = ui.Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final strokePaint = ui.Paint()
      ..color = color.darken()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final center = ui.Offset(width / 2, width / 2);
    canvas.drawCircle(center, width / 2, fillPaint);
    canvas.drawCircle(center, width / 2 - 2, strokePaint);
    final tailPath = ui.Path()
      ..moveTo(width / 2, height)
      ..lineTo(width * 0.2, width * 0.75)
      ..lineTo(width * 0.8, width * 0.75)
      ..close();
    canvas.drawPath(tailPath, fillPaint);
    canvas.drawPath(tailPath, strokePaint);

    final textPainter = TextPainter(
      textDirection: ui.TextDirection.ltr,
    );
    final textSpan = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: width * 0.65,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: Colors.white,
      ),
    );
    textPainter.text = textSpan;
    textPainter.layout();
    final iconOffset = ui.Offset(
      center.dx - (textPainter.width / 2),
      center.dy - (textPainter.height / 2),
    );
    textPainter.paint(canvas, iconOffset);

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final bytes =
        await image.toByteData(format: ui.ImageByteFormat.png);
    final buffer = bytes?.buffer.asUint8List();
    if (buffer == null) {
      throw StateError('Failed to encode marker image');
    }
    return BitmapDescriptor.fromBytes(buffer);
  }

  _CaptureTargetInfo? _findCaptureTarget({
    required GameStatus? gameStatus,
    required Player? currentPlayer,
    required double? captureRadiusMeters,
    required LatLng? selfPosition,
    required List<Player>? players,
  }) {
    if (gameStatus != GameStatus.running) return null;
    if (currentPlayer == null || currentPlayer.role != PlayerRole.oni) {
      return null;
    }
    if (captureRadiusMeters == null || captureRadiusMeters <= 0) {
      return null;
    }
    if (selfPosition == null) return null;
    if (players == null) return null;

    Player? closestRunner;
    double? closestDistance;

    for (final player in players) {
      if (player.uid == currentPlayer.uid) continue;
      if (player.role != PlayerRole.runner) continue;
      if (!player.isActive) continue;
      if (player.status != PlayerStatus.active) continue;
      final runnerPosition = player.position;
      if (runnerPosition == null) continue;
      final distance = Geolocator.distanceBetween(
        selfPosition.latitude,
        selfPosition.longitude,
        runnerPosition.latitude,
        runnerPosition.longitude,
      );
      if (distance > captureRadiusMeters) continue;
      if (closestDistance == null || distance < closestDistance) {
        closestDistance = distance;
        closestRunner = player;
      }
    }

    if (closestRunner == null || closestDistance == null) {
      return null;
    }
    return _CaptureTargetInfo(
      runner: closestRunner,
      distanceMeters: closestDistance,
    );
  }

  Set<Marker> _buildPlayerMarkers(
    AsyncValue<List<Player>> playersState,
    String? currentUid,
  ) {
    final markers = <Marker>{};

    playersState.whenData((players) {
      for (final player in players) {
        if (player.uid == currentUid) continue;
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

  Set<Marker> _buildPinMarkers({
    required AsyncValue<List<PinPoint>> pinsState,
    required Game? game,
    required PlayerRole? currentRole,
    required LatLng? selfPosition,
  }) {
    if (game?.status != GameStatus.running) {
      return const <Marker>{};
    }
    final pins = pinsState.valueOrNull;
    if (pins == null || pins.isEmpty) {
      return const <Marker>{};
    }
    final markers = <Marker>{};
    final runnerRadius = game?.runnerSeeGeneratorRadiusM?.toDouble();
    final killerRadius = game?.killerSeeGeneratorRadiusM?.toDouble();
    for (final pin in pins) {
      final position = LatLng(pin.lat, pin.lng);
      final isVisible = _shouldDisplayPin(
        pin: pin,
        role: currentRole,
        selfPosition: selfPosition,
        runnerRadius: runnerRadius,
        killerRadius: killerRadius,
      );
      if (!isVisible) continue;
      final hue = switch (pin.status) {
        PinStatus.pending => BitmapDescriptor.hueYellow,
        PinStatus.clearing => BitmapDescriptor.hueOrange,
        PinStatus.cleared => BitmapDescriptor.hueGreen,
      };
      markers.add(
        Marker(
          markerId: MarkerId('pin-${pin.id}'),
          position: position,
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          infoWindow: InfoWindow(
            title: '発電所',
            snippet: _pinStatusLabel(pin.status),
          ),
        ),
      );
    }
    return markers;
  }

  bool _shouldDisplayPin({
    required PinPoint pin,
    required PlayerRole? role,
    required LatLng? selfPosition,
    required double? runnerRadius,
    required double? killerRadius,
  }) {
    final status = pin.status;
    if (status == PinStatus.clearing || status == PinStatus.cleared) {
      return true;
    }
    if (selfPosition == null || role == null) {
      return true;
    }
    final viewerRadius =
        role == PlayerRole.runner ? runnerRadius : killerRadius;
    if (viewerRadius == null || viewerRadius <= 0) {
      return true;
    }
    final distance = Geolocator.distanceBetween(
      selfPosition.latitude,
      selfPosition.longitude,
      pin.lat,
      pin.lng,
    );
    return distance <= viewerRadius;
  }

  String _pinStatusLabel(PinStatus status) {
    return switch (status) {
      PinStatus.pending => '稼働中',
      PinStatus.clearing => '解除中',
      PinStatus.cleared => '解除済み',
    };
  }

  Set<Circle> _buildCaptureCircles(
    AsyncValue<Position> locationState,
    double? radiusMeters,
    Color? color,
  ) {
    if (radiusMeters == null || radiusMeters <= 0) {
      return const <Circle>{};
    }
    final position = locationState.valueOrNull;
    if (position == null) {
      return const <Circle>{};
    }
    return {
      Circle(
        circleId: const CircleId('capture-radius'),
        center: LatLng(position.latitude, position.longitude),
        radius: radiusMeters,
        fillColor: (color ?? Colors.redAccent).withOpacity(0.15),
        strokeColor: (color ?? Colors.redAccent).withOpacity(0.5),
        strokeWidth: 2,
      ),
    };
  }

  Color? _captureCircleColor(Player? currentPlayer) {
    if (currentPlayer == null) return null;
    if (!currentPlayer.isActive ||
        currentPlayer.status == PlayerStatus.downed) {
      return Colors.grey.shade500;
    }
    return currentPlayer.role == PlayerRole.oni
        ? Colors.redAccent
        : Colors.green;
  }

  Player? _currentPlayer(
    AsyncValue<List<Player>> playersState,
    String? currentUid,
  ) {
    if (currentUid == null) return null;
    final players = playersState.valueOrNull;
    if (players == null) return null;
    for (final player in players) {
      if (player.uid == currentUid) {
        return player;
      }
    }
    return null;
  }

  BitmapDescriptor _markerForPlayer(Player player) {
    if (player.role == PlayerRole.oni) {
      return _oniMarkerDescriptor ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    }
    if (player.status == PlayerStatus.downed) {
      return _downedMarkerDescriptor ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }
    return _runnerMarkerDescriptor ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
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

  Widget? _buildCountdownOverlay({
    required BuildContext context,
    required bool isActive,
    required int? remainingSeconds,
    required PlayerRole? role,
  }) {
    if (!isActive || remainingSeconds == null || role == null) {
      return null;
    }
    final formatted = _formatCountdown(remainingSeconds);
    return switch (role) {
      PlayerRole.oni => _buildOniCountdownOverlay(context, formatted),
      PlayerRole.runner => _buildRunnerCountdownOverlay(context, formatted),
    };
  }

  Widget _buildOniCountdownOverlay(
    BuildContext context,
    String formattedTime,
  ) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withOpacity(0.75),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formattedTime,
                style: theme.textTheme.displayMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ) ??
                    const TextStyle(
                      fontSize: 64,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
              ),
              const SizedBox(height: 12),
              const Text(
                '鬼のスタートまで',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRunnerCountdownOverlay(
    BuildContext context,
    String formattedTime,
  ) {
    final theme = Theme.of(context);
    return Positioned(
      right: 16,
      bottom: 140,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(0.9),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.4),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '鬼が出発するまで',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formattedTime,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatCountdown(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
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
  final _scrollController = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
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

    final playersState = ref.watch(playersStreamProvider(widget.gameId));
    final playersByUid = {
      for (final player in playersState.valueOrNull ?? const <Player>[])
        player.uid: player,
    };

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF00090E),
            Color(0xFF03161B),
            Color(0xFF041F25),
          ],
        ),
      ),
      child: playerState.when(
        data: (player) {
          if (player == null) {
            return const Center(child: Text('プレイヤー情報が見つかりません'));
          }
          final palette = _ChatPalette.fromRole(player.role);
          final chatState = ref.watch(
            chatMessagesProvider(
              (gameId: widget.gameId, role: player.role),
            ),
          );

          return Column(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _dismissKeyboard,
                  child: Column(
                    children: [
                      SafeArea(
                        bottom: false,
                        child: _ChatHeader(
                          title: player.role == PlayerRole.oni
                              ? '鬼チャット'
                              : '逃走者チャット',
                          palette: palette,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: chatState.when(
                            data: (messages) {
                              _scheduleScrollToBottom();
                              if (messages.isEmpty) {
                                return _EmptyChatMessage(palette: palette);
                              }
                              return _MessagesListView(
                                messages: messages,
                                palette: palette,
                                playersByUid: playersByUid,
                                currentUid: user.uid,
                                scrollController: _scrollController,
                              );
                            },
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (error, _) => Center(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  'チャットを読み込めませんでした。\n$error',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _ChatComposer(
                controller: _controller,
                sending: _sending,
                palette: palette,
                role: player.role,
                onSendRequested: () => _sendMessage(context, player),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('プレイヤー情報の取得に失敗しました: $error'),
        ),
      ),
    );
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      _scrollController.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
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
      if (context.mounted) {
        _dismissKeyboard();
      }
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

class _MessagesListView extends StatelessWidget {
  const _MessagesListView({
    required this.messages,
    required this.palette,
    required this.playersByUid,
    required this.currentUid,
    required this.scrollController,
  });

  final List<ChatMessage> messages;
  final _ChatPalette palette;
  final Map<String, Player> playersByUid;
  final String currentUid;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return _EmptyChatMessage(palette: palette);
    }
    final width = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = width * 0.8;
    return ListView.builder(
      key: ValueKey(messages.length),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      physics: const BouncingScrollPhysics(),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isMine = message.uid == currentUid;
        final playerProfile = playersByUid[message.uid];
        final displayName = message.nickname.isNotEmpty
            ? message.nickname
            : playerProfile?.nickname ?? '';
        final avatarUrl = playerProfile?.avatarUrl;
        final formattedTime = DateFormat('HH:mm').format(message.timestamp);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment:
                    isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  if (!isMine) ...[
                    _ChatAvatar(avatarUrl: avatarUrl, palette: palette),
                    const SizedBox(width: 8),
                  ],
                  if (!isMine && displayName.isNotEmpty)
                    Text(
                      displayName,
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 2.5,
                        color: palette.mutedText.withOpacity(0.9),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment:
                    isMine ? Alignment.centerRight : Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: isMine ? palette.mineBubbleGradient : null,
                      color: isMine ? null : palette.otherBubbleColor,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: Radius.circular(isMine ? 20 : 6),
                        bottomRight: Radius.circular(isMine ? 6 : 20),
                      ),
                      border: isMine
                          ? null
                          : Border.all(
                              color: palette.accentColor.withOpacity(0.25),
                            ),
                      boxShadow: [
                        BoxShadow(
                          color: palette.shadowColor,
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Text(
                        message.message,
                        style: TextStyle(
                          color: isMine ? Colors.white : palette.bodyText,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                formattedTime,
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2,
                  color: palette.mutedText,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.title,
    required this.palette,
  });

  final String title;
  final _ChatPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: palette.headerGradient),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        border: Border(
          bottom: BorderSide(
            color: palette.accentColor.withOpacity(0.4),
            width: 1.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: palette.accentColor.withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TEAM CHANNEL',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              letterSpacing: 4,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({
    required this.avatarUrl,
    required this.palette,
  });

  final String? avatarUrl;
  final _ChatPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: palette.accentColor.withOpacity(0.35)),
        color: Colors.black.withOpacity(0.4),
        boxShadow: [
          BoxShadow(
            color: palette.accentColor.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: avatarUrl != null && avatarUrl!.isNotEmpty
          ? Image.network(
              avatarUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, _, __) => Icon(
                Icons.person,
                size: 18,
                color: palette.accentColor.withOpacity(0.7),
              ),
            )
          : Icon(
              Icons.person,
              size: 18,
              color: palette.accentColor.withOpacity(0.7),
            ),
    );
  }
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.sending,
    required this.palette,
    required this.role,
    required this.onSendRequested,
  });

  final TextEditingController controller;
  final bool sending;
  final _ChatPalette palette;
  final PlayerRole role;
  final VoidCallback onSendRequested;

  @override
  Widget build(BuildContext context) {
    const hint = 'チャットを入力…';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final canSend = value.text.trim().isNotEmpty;
            final counterText =
                value.text.isEmpty ? null : '${value.text.length}/200';
            return Row(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      TextField(
                        controller: controller,
                        maxLines: 4,
                        minLines: 1,
                        maxLength: 200,
                        buildCounter: (_,
                                {int? currentLength,
                                int? maxLength,
                                bool? isFocused}) =>
                            null,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: hint,
                          hintStyle: TextStyle(color: palette.mutedText),
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.35),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(
                              color: palette.accentColor.withOpacity(0.4),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(
                              color: palette.accentColor.withOpacity(0.4),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(color: palette.accentColor),
                          ),
                          contentPadding:
                              const EdgeInsets.fromLTRB(16, 14, 48, 14),
                        ),
                        cursorColor: palette.accentColor,
                      ),
                      if (counterText != null)
                        Positioned(
                          right: 12,
                          top: 12,
                          child: Text(
                            counterText,
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 2,
                              color: palette.mutedText,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 56,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _GradientButton(
                      palette: palette,
                      sending: sending,
                      enabled: canSend,
                      onPressed: canSend && !sending ? onSendRequested : null,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.palette,
    required this.sending,
    required this.enabled,
    required this.onPressed,
  });

  final _ChatPalette palette;
  final bool sending;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final canTap = enabled && !sending && onPressed != null;
    final Color iconColor =
        canTap ? palette.accentColor : palette.mutedText.withOpacity(0.8);

    return SizedBox(
      height: 52,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: canTap ? onPressed : null,
          child: Center(
            child: sending
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                    ),
                  )
                : Icon(
                    Icons.send_rounded,
                    size: 24,
                    color: iconColor,
                  ),
          ),
        ),
      ),
    );
  }
}

class _EmptyChatMessage extends StatelessWidget {
  const _EmptyChatMessage({required this.palette});

  final _ChatPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            color: palette.mutedText,
            size: 36,
          ),
          const SizedBox(height: 12),
          Text(
            'まだメッセージがありません',
            style: TextStyle(
              color: palette.bodyText,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '仲間に最初の一言を送信してみよう！',
            style: TextStyle(color: palette.mutedText, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ChatPalette {
  const _ChatPalette({
    required this.headerGradient,
    required this.mineBubbleGradient,
    required this.buttonGradient,
    required this.accentColor,
    required this.bodyText,
    required this.mutedText,
    required this.otherBubbleColor,
    required this.shadowColor,
  });

  final List<Color> headerGradient;
  final LinearGradient mineBubbleGradient;
  final List<Color> buttonGradient;
  final Color accentColor;
  final Color bodyText;
  final Color mutedText;
  final Color otherBubbleColor;
  final Color shadowColor;

  static _ChatPalette fromRole(PlayerRole role) {
    if (role == PlayerRole.oni) {
      return const _ChatPalette(
        headerGradient: [
          Color(0xFFFF47C2),
          Color(0xFF8A1FBD),
          Color(0xFFFF47C2),
        ],
        mineBubbleGradient: LinearGradient(
          colors: [
            Color(0xFFFF47C2),
            Color(0xFF8A1FBD),
          ],
        ),
        buttonGradient: [
          Color(0xFFFF47C2),
          Color(0xFF8A1FBD),
        ],
        accentColor: Color(0xFFFF47C2),
        bodyText: Color(0xFFE6F4F1),
        mutedText: Color(0xFF6B9DA2),
        otherBubbleColor: Color(0xFF03161B),
        shadowColor: Color(0xAA8A1FBD),
      );
    }

    return const _ChatPalette(
      headerGradient: [
        Color(0xFF22B59B),
        Color(0xFF5FFBF1),
        Color(0xFF22B59B),
      ],
      mineBubbleGradient: LinearGradient(
        colors: [
          Color(0xFF22B59B),
          Color(0xFF5FFBF1),
        ],
      ),
      buttonGradient: [
        Color(0xFF22B59B),
        Color(0xFF5FFBF1),
      ],
      accentColor: Color(0xFF22B59B),
      bodyText: Color(0xFFE6F4F1),
      mutedText: Color(0xFF6B9DA2),
      otherBubbleColor: Color(0xFF03161B),
      shadowColor: Color(0x6622B59B),
    );
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
                PlayerProfileCard(
                  player: player,
                  gameId: gameId,
                  onEditProfile: () {
                    context.push(PlayerProfileEditPage.path(gameId));
                  },
                ),
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
                        context.pushNamed(
                          GameSettingsPage.routeName,
                          pathParameters: {'gameId': gameId},
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.swap_horiz),
                      title: const Text('役職振り分け'),
                      subtitle: const Text('鬼/逃走者の人数と役割を整理・ランダム振り分け'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        context.pushNamed(
                          RoleAssignmentPage.routeName,
                          pathParameters: {'gameId': gameId},
                        );
                      },
                    ),
                  ),
                ],
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
                  const SizedBox(height: 16),
                _ActionButtons(
                  gameId: gameId,
                  ownerUid: gameState.value?.ownerUid ?? '',
                  currentUid: user.uid,
                  gameStatus: gameState.value?.status,
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

class _MapStartGameButton extends ConsumerStatefulWidget {
  const _MapStartGameButton({
    required this.gameId,
    required this.countdownSeconds,
  });

  final String gameId;
  final int countdownSeconds;

  @override
  ConsumerState<_MapStartGameButton> createState() =>
      _MapStartGameButtonState();
}

class _MapMyLocationButton extends StatelessWidget {
  const _MapMyLocationButton({
    required this.onPressed,
    required this.isLoading,
  });

  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: 'game-map-my-location',
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : const Icon(Icons.my_location),
    );
  }
}

class _CaptureActionButton extends StatelessWidget {
  const _CaptureActionButton({
    required this.targetName,
    required this.distanceMeters,
    required this.isLoading,
    required this.onPressed,
  });

  final String targetName;
  final double? distanceMeters;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distanceLabel = distanceMeters == null
        ? null
        : (distanceMeters! >= 100
            ? distanceMeters!.toStringAsFixed(0)
            : distanceMeters!.toStringAsFixed(1));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.redAccent,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          foregroundColor: Colors.white,
          textStyle: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        onPressed: isLoading ? null : onPressed,
        icon: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.gpp_maybe),
        label: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('捕獲する'),
            Text(
              distanceLabel == null
                  ? targetName
                  : '$targetName（約${distanceLabel}m）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptureTargetInfo {
  const _CaptureTargetInfo({
    required this.runner,
    required this.distanceMeters,
  });

  final Player runner;
  final double distanceMeters;
}

extension on Color {
  Color darken([double amount = 0.2]) {
    final hsl = HSLColor.fromColor(this);
    final lightness = (hsl.lightness - amount).clamp(0.0, 1.0);
    return hsl.withLightness(lightness).toColor();
  }
}

class _MapStartGameButtonState extends ConsumerState<_MapStartGameButton> {
  bool _isStarting = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.redAccent,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
        ),
        onPressed: _isStarting ? null : _handlePressed,
        child: _isStarting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text('ゲームスタート'),
      ),
    );
  }

  Future<void> _handlePressed() async {
    setState(() {
      _isStarting = true;
    });
    try {
      final controller = ref.read(gameControlControllerProvider);
      await controller.startCountdown(
        gameId: widget.gameId,
        durationSeconds: widget.countdownSeconds,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ゲーム開始に失敗しました: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }
}

class _ActionButtons extends ConsumerStatefulWidget {
  const _ActionButtons({
    required this.gameId,
    required this.ownerUid,
    required this.currentUid,
    required this.gameStatus,
  });

  final String gameId;
  final String ownerUid;
  final String currentUid;
  final GameStatus? gameStatus;

  @override
  ConsumerState<_ActionButtons> createState() => _ActionButtonsState();
}

class _ActionButtonsState extends ConsumerState<_ActionButtons> {
  bool _isLeaving = false;
  bool _isClaimingOwner = false;
  bool _isDeletingGame = false;
  bool _isEndingGame = false;

  bool get _isOwner => widget.ownerUid == widget.currentUid;
  bool get _showEndGameButton {
    final status = widget.gameStatus;
    if (!_isOwner || status == null) return false;
    return status == GameStatus.countdown || status == GameStatus.running;
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        if (_showEndGameButton) ...[
          ElevatedButton.icon(
            onPressed: _isEndingGame
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('ゲームを終了'),
                        content: const Text(
                          '現在のゲームを終了して結果画面に移行します。よろしいですか？',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('キャンセル'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('終了する'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    setState(() {
                      _isEndingGame = true;
                    });
                    try {
                      final controller =
                          ref.read(gameControlControllerProvider);
                      await controller.endGame(gameId: widget.gameId);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('ゲームを終了しました')),
                        );
                      }
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('ゲームの終了に失敗しました: $error')),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() {
                          _isEndingGame = false;
                        });
                      }
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
            ),
            icon: _isEndingGame
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.stop_circle_outlined),
            label: const Text('ゲームを終了'),
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
        if (_isOwner) ...[
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _isDeletingGame
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('ゲームを削除'),
                        content: const Text(
                          'このゲームに関するプレイヤーやチャット履歴などのデータがすべて削除されます。'
                          'この操作は取り消せません。実行してもよろしいですか？',
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
                      _isDeletingGame = true;
                    });
                    final router = GoRouter.of(context);
                    try {
                      final repo = ref.read(gameRepositoryProvider);
                      await repo.deleteGame(gameId: widget.gameId);
                      final exitController =
                          ref.read(gameExitControllerProvider);
                      await exitController.leaveGame(gameId: widget.gameId);
                      if (!mounted) return;
                      router.goNamed(WelcomePage.routeName);
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('ゲームの削除に失敗しました: $error')),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() {
                          _isDeletingGame = false;
                        });
                      }
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black87,
            ),
            icon: _isDeletingGame
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.delete_forever),
            label: const Text('ゲームを削除'),
          ),
        ],
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
