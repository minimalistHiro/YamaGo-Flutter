import 'dart:async';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:yamago_flutter/core/location/location_service.dart';
import 'package:yamago_flutter/core/location/yamanote_constants.dart';
import 'package:yamago_flutter/core/maps/marker_icon_factory.dart';
import 'package:yamago_flutter/core/notifications/local_notification_service.dart';
import 'package:yamago_flutter/core/notifications/push_notification_service.dart';
import 'package:yamago_flutter/core/services/firebase_providers.dart';
import 'package:yamago_flutter/core/time/server_time_service.dart';
import 'package:yamago_flutter/features/auth/application/auth_providers.dart';
import 'package:yamago_flutter/features/game/application/game_control_controller.dart';
import 'package:yamago_flutter/features/game/application/game_event_providers.dart';
import 'package:yamago_flutter/features/game/application/game_exit_controller.dart';
import 'package:intl/intl.dart';

import 'package:yamago_flutter/features/chat/application/chat_providers.dart';
import 'package:yamago_flutter/features/chat/data/chat_repository.dart';
import 'package:yamago_flutter/features/chat/domain/chat_message.dart';
import 'package:yamago_flutter/features/game/application/player_location_updater.dart';
import 'package:yamago_flutter/features/game/application/player_providers.dart';
import 'package:yamago_flutter/features/game/data/capture_repository.dart';
import 'package:yamago_flutter/features/game/data/game_event_repository.dart';
import 'package:yamago_flutter/features/game/data/rescue_repository.dart';
import 'package:yamago_flutter/features/game/data/game_repository.dart';
import 'package:yamago_flutter/features/game/data/player_repository.dart';
import 'package:yamago_flutter/features/game/domain/game.dart';
import 'package:yamago_flutter/features/game/domain/game_event.dart';
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
import 'package:yamago_flutter/features/pins/data/pin_repository.dart';

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

final gameShellTabIndexProvider = StateProvider<int>((ref) => 0);

class _GameShellPageState extends ConsumerState<GameShellPage> {
  int _currentIndex = 0;
  StreamSubscription<String>? _tokenRefreshSubscription;
  String? _lastSyncedFcmToken;
  bool _hasAttemptedInitialTokenSync = false;
  bool _hasCheckedTutorial = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(gameShellTabIndexProvider.notifier).state = _currentIndex;
    });
    unawaited(_ensureSignedIn());
    final pushService = ref.read(pushNotificationServiceProvider);
    unawaited(pushService.initialize());
    _tokenRefreshSubscription =
        pushService.onTokenRefresh.listen((token) async {
      final auth = ref.read(firebaseAuthProvider);
      final uid = auth.currentUser?.uid;
      if (uid == null) return;
      await _syncPlayerNotificationToken(uid, tokenOverride: token);
    });
    unawaited(_maybeShowTutorial());
    unawaited(_syncServerTimeOffset());
  }

  void _handleTabSelected(int index) {
    final isLeavingChatTab = _currentIndex == 1 && index != 1;
    if (isLeavingChatTab) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    setState(() {
      _currentIndex = index;
    });
    ref.read(gameShellTabIndexProvider.notifier).state = index;
  }

  Future<void> _ensureSignedIn() async {
    try {
      await ref.read(ensureAnonymousSignInProvider.future);
      final auth = ref.read(firebaseAuthProvider);
      _maybeSyncTokenForUser(auth.currentUser);
    } catch (error, stackTrace) {
      debugPrint('Failed to ensure FirebaseAuth sign-in: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _syncPlayerNotificationToken(
    String uid, {
    String? tokenOverride,
  }) async {
    final pushService = ref.read(pushNotificationServiceProvider);
    final token = tokenOverride ?? await pushService.getToken();
    if (token == null) return;
    if (_lastSyncedFcmToken == token) return;
    final repo = ref.read(playerRepositoryProvider);
    try {
      await repo.addPlayerFcmToken(
        gameId: widget.gameId,
        uid: uid,
        token: token,
      );
      _lastSyncedFcmToken = token;
    } catch (error, stackTrace) {
      debugPrint('Failed to sync FCM token: $error');
      debugPrint('$stackTrace');
    }
  }

  void _maybeSyncTokenForUser(User? user) {
    if (user == null || _hasAttemptedInitialTokenSync) {
      return;
    }
    _hasAttemptedInitialTokenSync = true;
    unawaited(_syncPlayerNotificationToken(user.uid));
  }

  Future<void> _maybeShowTutorial() async {
    if (_hasCheckedTutorial) {
      return;
    }
    _hasCheckedTutorial = true;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const GameTutorialDialog(),
    );
  }

  Future<void> _syncServerTimeOffset() async {
    try {
      await ref.read(serverTimeServiceProvider).ensureSynchronized();
    } catch (error, stackTrace) {
      debugPrint('Failed to sync server time offset: $error');
      debugPrint('$stackTrace');
    }
  }

  @override
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(firebaseAuthProvider);
    final user = auth.currentUser;
    _maybeSyncTokenForUser(user);
    final sections = [
      GameMapSection(gameId: widget.gameId),
      GameChatSection(gameId: widget.gameId),
      GameSettingsSection(gameId: widget.gameId),
    ];

    final titles = ['マップ', 'チャット', '設定'];

    AppBar? appBar;
    if (_currentIndex == 2) {
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

class _GameMapSectionState extends ConsumerState<GameMapSection>
    with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  LatLng _cameraTarget = yamanoteCenter;
  static const double _initialMapZoom = 13.5;
  LatLng? _latestUserLocation;
  Timer? _statusTicker;
  bool _isStatusTickerActive = false;
  bool _countdownAutoStartTriggered = false;
  bool _isLocatingUser = false;
  bool _isCapturing = false;
  bool _isRescuing = false;
  bool _isClearingPin = false;
  bool _showGeneratorClearedAlert = false;
  bool _showRescueAlert = false;
  bool _showCaptureAlert = false;
  String? _rescueAlertMessage;
  String? _captureAlertMessage;
  bool _hasSeededGameEvents = false;
  bool _hasSeededClearedPins = false;
  static const int _defaultPinClearDurationSeconds = 180;
  static const int _minPinClearDurationSeconds = 10;
  static const int _maxPinClearDurationSeconds = 600;
  static const int _oniClearingAlertDurationSeconds = 5;
  int _pinClearDurationSeconds = _defaultPinClearDurationSeconds;
  Timer? _pinClearTimer;
  int? _pinClearRemainingSeconds;
  String? _activeClearingPinId;
  Timer? _oniClearingAlertTimer;
  bool _isOniClearingAlertVisible = false;
  String? _oniClearingPinId;
  BitmapDescriptor? _downedMarkerDescriptor;
  BitmapDescriptor? _oniMarkerDescriptor;
  BitmapDescriptor? _runnerMarkerDescriptor;
  BitmapDescriptor? _generatorPinMarkerDescriptor;
  BitmapDescriptor? _clearingPinMarkerDescriptor;
  BitmapDescriptor? _clearedPinMarkerDescriptor;
  final Set<String> _knownClearedPinIds = <String>{};
  final Set<String> _knownClearingPinIds = <String>{};
  final Set<String> _handledGameEventIds = <String>{};
  List<PinPoint> _latestPins = const [];
  double? _latestCaptureRadiusMeters;
  PlayerRole? _latestPlayerRole;
  GameStatus? _latestGameStatus;
  bool _hasInitializedGameStatus = false;
  bool _showGameEndPopup = false;
  bool _showGameSummaryPopup = false;
  bool _hasShownGameEndPopup = false;
  DateTime? _gameEndedAt;
  bool _hasTriggeredAutoGameEnd = false;
  ProviderSubscription<AsyncValue<List<PinPoint>>>? _pinsSubscription;
  ProviderSubscription<AsyncValue<List<GameEvent>>>? _gameEventsSubscription;
  ProviderSubscription<AsyncValue<Position>>? _locationSubscription;
  bool _hasCenteredOnUserInitially = false;
  bool _backgroundPermissionDialogDismissed = false;
  static const _kodouSoundAssetPath = 'sounds/kodou_sound.mp3';
  AudioPlayer? _kodouPlayer;
  bool _shouldPlayKodouSound = false;
  bool _isKodouPlaying = false;
  bool _isAppInForeground = true;
  bool? _lastReportedPlayerActiveStatus;
  String? _lastReportedPlayerActiveUid;
  bool _showTimedEventPopup = false;
  _TimedEventPopupData? _activeTimedEvent;
  final Set<int> _triggeredTimedEventQuarters = <int>{};
  DateTime? _currentGameStartAt;
  int? _pendingTimedEventQuarter;
  final math.Random _timedEventRandom = math.Random();
  static const int _defaultGameDurationSeconds = 7200;
  static const int _timedEventDefaultRequiredRunners = 3;

  @override
  void initState() {
    super.initState();
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    final lifecycleState = binding.lifecycleState;
    if (lifecycleState != null) {
      _isAppInForeground = lifecycleState == AppLifecycleState.resumed;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeUpdatePlayerActiveStatus();
    });
    _pinsSubscription = ref.listenManual<AsyncValue<List<PinPoint>>>(
      pinsStreamProvider(widget.gameId),
      (previous, next) {
        next.whenData((pins) {
          if (!mounted) return;
          _latestPins = pins;
          _handlePinClearingNotifications(pins);
          _handlePinClearedNotifications(pins);
          _handleActiveClearingPinSnapshot(pins);
          _maybeCancelClearingWhenOutOfRange();
        });
      },
    );
    _gameEventsSubscription = ref.listenManual<AsyncValue<List<GameEvent>>>(
      gameEventsStreamProvider(widget.gameId),
      (previous, next) {
        next.whenData(_handleGameEvents);
      },
    );
    _locationSubscription = ref.listenManual<AsyncValue<Position>>(
        locationStreamProvider, (previous, next) {
      next.whenData((position) {
        _latestUserLocation = LatLng(position.latitude, position.longitude);
        _maybeCenterCameraOnUserInitially();
        _maybeCancelClearingWhenOutOfRange();
      });
    });
    unawaited(_initializeKodouPlayer());
    unawaited(_loadCustomMarkers());
    unawaited(_attemptInitialUserLocationFocus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _maybeUpdatePlayerActiveStatus(isActiveOverride: false);
    _statusTicker?.cancel();
    _pinClearTimer?.cancel();
    _oniClearingAlertTimer?.cancel();
    _mapController?.dispose();
    _pinsSubscription?.close();
    _gameEventsSubscription?.close();
    _locationSubscription?.close();
    final kodouPlayer = _kodouPlayer;
    if (kodouPlayer != null) {
      unawaited(kodouPlayer.stop());
      kodouPlayer.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppInForeground = state == AppLifecycleState.resumed;
    _maybeUpdatePlayerActiveStatus(isActiveOverride: _isAppInForeground);
  }

  void _maybeNotifyMapPopup({
    required String notificationId,
    required String title,
    required String body,
  }) {
    if (_isAppInForeground) return;
    final service = ref.read(localNotificationServiceProvider);
    unawaited(
      service.showMapEventNotification(
        notificationId: notificationId,
        title: title,
        body: body,
      ),
    );
  }

  void _maybeUpdatePlayerActiveStatus({
    String? uid,
    bool? isActiveOverride,
  }) {
    final resolvedUid = uid ?? ref.read(firebaseAuthProvider).currentUser?.uid;
    if (resolvedUid == null) {
      _lastReportedPlayerActiveUid = null;
      _lastReportedPlayerActiveStatus = null;
      return;
    }
    final shouldBeActive = isActiveOverride ?? _isAppInForeground;
    if (_lastReportedPlayerActiveUid == resolvedUid &&
        _lastReportedPlayerActiveStatus == shouldBeActive) {
      return;
    }
    _lastReportedPlayerActiveUid = resolvedUid;
    _lastReportedPlayerActiveStatus = shouldBeActive;
    final repo = ref.read(playerRepositoryProvider);
    unawaited(
      repo
          .setPlayerActive(
        gameId: widget.gameId,
        uid: resolvedUid,
        isActive: shouldBeActive,
      )
          .catchError((error, stackTrace) {
        debugPrint('Failed to update player activity: $error');
        debugPrint('$stackTrace');
      }),
    );
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
    _maybeUpdatePlayerActiveStatus(uid: currentUid);
    AsyncValue<Player?>? currentPlayerState;
    if (currentUid != null) {
      currentPlayerState = ref.watch(
        playerStreamProvider((gameId: widget.gameId, uid: currentUid)),
      );
    }

    final previousGameStatus = _latestGameStatus;
    final game = gameState.valueOrNull;
    _updatePinClearDuration(game);
    final captureRadius = game?.captureRadiusM?.toDouble();
    _latestCaptureRadiusMeters = captureRadius;
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
    final isRunnerDetectedByOni = _isRunnerDetectedByOni(
      game: game,
      currentPlayer: currentPlayer,
      selfPosition: selfLatLng,
      players: players,
    );
    _updateKodouSound(shouldPlay: isRunnerDetectedByOni);
    final captureTargetInfo = _findCaptureTarget(
      gameStatus: game?.status,
      currentPlayer: currentPlayer,
      captureRadiusMeters: captureRadius,
      selfPosition: selfLatLng,
      players: players,
    );
    final captureTarget = captureTargetInfo?.runner;
    final captureTargetDistance = captureTargetInfo?.distanceMeters;
    final rescueTargetInfo = _findRescueTarget(
      gameStatus: game?.status,
      currentPlayer: currentPlayer,
      captureRadiusMeters: captureRadius,
      selfPosition: selfLatLng,
      players: players,
    );
    final rescueTarget = rescueTargetInfo?.runner;
    final rescueTargetDistance = rescueTargetInfo?.distanceMeters;
    final pins = pinsState.valueOrNull;
    final int? totalGenerators = pins?.length;
    final int? clearedGenerators = pins == null
        ? null
        : pins
            .where((pin) => pin.status == PinStatus.cleared || pin.cleared)
            .length;
    if (pins != null) {
      _latestPins = pins;
    }
    _latestPlayerRole = currentPlayer?.role;
    _latestGameStatus = game?.status;
    _handleGameEndStatusChange(
      previousStatus: previousGameStatus,
      currentStatus: _latestGameStatus,
    );
    _maybeCancelClearingWhenPlayerUnavailable(currentPlayer);
    _maybeCancelClearingWhenGameInactive(game);
    final nearbyPinInfo = _findNearbyPin(
      gameStatus: game?.status,
      currentPlayer: currentPlayer,
      captureRadiusMeters: captureRadius,
      selfPosition: selfLatLng,
      pins: pins,
    );
    final nearbyPin = nearbyPinInfo?.pin;
    final nearbyPinDistance = nearbyPinInfo?.distanceMeters;
    final bool isCurrentlyClearing =
        _isClearingPin && _activeClearingPinId != null;
    final PinPoint? activeClearingPin =
        isCurrentlyClearing ? _findPinById(_activeClearingPinId!, pins) : null;
    final double? activeClearingDistance = isCurrentlyClearing
        ? _distanceToPin(activeClearingPin, selfLatLng)
        : null;
    final bool isGameRunning = game?.status == GameStatus.running;
    final playerRole = currentPlayer?.role;
    final playerMarkers = isGameRunning
        ? _buildPlayerMarkers(
            playersState: playersState,
            currentUid: currentUid,
            currentPlayer: currentPlayer,
            selfPosition: selfLatLng,
            game: game,
          )
        : const <Marker>{};
    final pinMarkers = isGameRunning
        ? _buildPinMarkers(
            pinsState: pinsState,
            game: game,
            currentRole: currentPlayer?.role,
            selfPosition: selfLatLng,
          )
        : const <Marker>{};
    final markers = <Marker>{...playerMarkers, ...pinMarkers};

    final permissionOverlay = _buildPermissionOverlay(
      context,
      permissionState,
      locationState,
    );
    final countdownRemainingSeconds = _calculateCountdownRemainingSeconds(game);
    final runningRemainingSeconds = game?.runningRemainingSeconds;
    final isCountdownActive = game?.status == GameStatus.countdown &&
        countdownRemainingSeconds != null &&
        countdownRemainingSeconds > 0;
    final hasRunningCountdown = game?.status == GameStatus.running &&
        (runningRemainingSeconds ?? 0) > 0;
    _updateStatusTicker(isCountdownActive || hasRunningCountdown);
    final countdownOverlay = _buildCountdownOverlay(
      context: context,
      isActive: isCountdownActive,
      remainingSeconds: countdownRemainingSeconds,
      role: currentPlayer?.role,
    );
    _maybeTriggerAutoStart(
      game: game,
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
      data: (status) =>
          status == LocationPermissionStatus.granted ||
          status == LocationPermissionStatus.limited,
      orElse: () => false,
    );
    final bool isMyLocationButtonEnabled =
        isLocationPermissionGranted && _mapController != null;
    final int pinCountdownSeconds = _pinClearRemainingSeconds ?? 0;
    final double? clearButtonDistance =
        isCurrentlyClearing ? activeClearingDistance : nearbyPinDistance;
    final bool showRunnerClearingOverlay = isGameRunning &&
        pinCountdownSeconds > 0 &&
        currentPlayer?.role == PlayerRole.runner &&
        isCurrentlyClearing;
    final bool showOniClearingOverlay = isGameRunning &&
        _isOniClearingAlertVisible &&
        currentPlayer?.role == PlayerRole.oni &&
        _oniClearingPinId != null;
    final bool showGeneratorClearedOverlay =
        isGameRunning && _showGeneratorClearedAlert && playerRole != null;
    final bool showRescueAlert =
        isGameRunning && _showRescueAlert && _rescueAlertMessage != null;
    final bool showCaptureAlert =
        isGameRunning && _showCaptureAlert && _captureAlertMessage != null;
    final bool isPermissionDialogVisible =
        permissionOverlay is _BackgroundPermissionDialog;
    final bool isPopupVisible = isPermissionDialogVisible ||
        countdownOverlay != null ||
        showGeneratorClearedOverlay ||
        showRunnerClearingOverlay ||
        showOniClearingOverlay ||
        showRescueAlert ||
        showCaptureAlert ||
        _showGameEndPopup ||
        _showGameSummaryPopup ||
        _showTimedEventPopup;

    final actionButtons = <Widget>[];
    if (showStartButton) {
      actionButtons.add(
        _MapStartGameButton(
          gameId: widget.gameId,
          countdownSeconds: countdownSeconds,
          isLocked: isPopupVisible,
        ),
      );
    }
    if (captureTarget != null) {
      actionButtons.add(
        _CaptureActionButton(
          targetName: captureTarget.nickname,
          distanceMeters: captureTargetDistance,
          isLoading: _isCapturing,
          onPressed: (_isCapturing || isPopupVisible)
              ? null
              : () => _handleCapturePressed(captureTarget),
        ),
      );
    }
    if (rescueTarget != null) {
      actionButtons.add(
        _RescueActionButton(
          targetName: rescueTarget.nickname,
          distanceMeters: rescueTargetDistance,
          isLoading: _isRescuing,
          onPressed: (_isRescuing || isPopupVisible)
              ? null
              : () => _handleRescuePressed(rescueTarget),
        ),
      );
    }
    if (nearbyPin != null && !_isClearingPin) {
      actionButtons.add(
        _ClearPinButton(
          distanceMeters: clearButtonDistance,
          isLoading: _isClearingPin,
          countdownSeconds: _pinClearRemainingSeconds,
          onPressed:
              isPopupVisible ? null : () => _handleClearPinPressed(nearbyPin),
        ),
      );
    }
    final int actionCount = actionButtons.length;
    final double myLocationButtonBottom = switch (actionCount) {
      0 => 12.0,
      1 => 96.0,
      2 => 156.0,
      _ => 196.0,
    };
    final double mapBottomPadding = switch (actionCount) {
      0 => 16.0,
      1 => 64.0,
      2 => 96.0,
      _ => 120.0,
    };

    final bool allPinsCleared = _areAllPinsCleared(pins);
    final bool allRunnersDown = _areAllRunnersDown(players);
    final int capturedPlayersCount = _capturedRunnersCount(players);
    final int summaryClearedGenerators = clearedGenerators ?? 0;
    final String formattedGameDuration =
        _formatElapsedDuration(_calculateGameDurationSeconds(game));
    final gameEndResult = _resolveGameEndResult(
      game: game,
      allPinsCleared: allPinsCleared,
      allRunnersDown: allRunnersDown,
    );
    _maybeTriggerAutoGameEnd(
      game: game,
      allPinsCleared: allPinsCleared,
      allRunnersDown: allRunnersDown,
      runningRemainingSeconds: runningRemainingSeconds,
      pinCount: game?.pinCount ?? totalGenerators,
    );
    _maybeHandleTimedEvents(
      game: game,
      players: players,
    );

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _cameraTarget,
            zoom: _initialMapZoom,
          ),
          cameraTargetBounds: CameraTargetBounds(yamanoteBounds),
          minMaxZoomPreference: const MinMaxZoomPreference(
            yamanoteMinZoom,
            yamanoteMaxZoom,
          ),
          onMapCreated: (controller) {
            _mapController ??= controller;
            _maybeCenterCameraOnUserInitially();
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
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                    child: PlayerHud(
                      playersState: playersState,
                      totalGenerators: totalGenerators,
                      clearedGenerators: clearedGenerators,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (permissionOverlay != null) permissionOverlay,
        if (countdownOverlay != null) countdownOverlay,
        if (showGeneratorClearedOverlay)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _GeneratorClearedAlert(
                    playerRole: playerRole,
                    onDismissed: _dismissGeneratorClearedAlert,
                  ),
                ),
              ),
            ),
          ),
        if (showRunnerClearingOverlay)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _GeneratorClearingCountdownAlert(
                    remainingSeconds: pinCountdownSeconds,
                  ),
                ),
              ),
            ),
          ),
        if (showOniClearingOverlay)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: const _OniClearingAlert(),
                ),
              ),
            ),
          ),
        if (showRescueAlert)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _RescueAlert(
                    message: _rescueAlertMessage!,
                    onDismissed: _dismissRescueAlert,
                  ),
                ),
              ),
            ),
          ),
        if (showCaptureAlert)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _CaptureAlert(
                    message: _captureAlertMessage!,
                    onDismissed: _dismissCaptureAlert,
                  ),
                ),
              ),
            ),
          ),
        if (_showTimedEventPopup && _activeTimedEvent != null)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _TimedEventPopup(
                    data: _activeTimedEvent!,
                    onClose: _handleTimedEventPopupDismissed,
                  ),
                ),
              ),
            ),
          ),
        if (_showGameEndPopup)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _GameEndResultPopup(
                    result: gameEndResult,
                    onNext: _handleGameEndPopupNext,
                  ),
                ),
              ),
            ),
          ),
        if (_showGameSummaryPopup)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _GameSummaryPopup(
                    capturedPlayersCount: capturedPlayersCount,
                    generatorsClearedCount: summaryClearedGenerators,
                    gameDurationLabel: formattedGameDuration,
                    onClose: _handleGameSummaryClose,
                  ),
                ),
              ),
            ),
          ),
        if (actionButtons.isNotEmpty)
          Positioned(
            left: 24,
            right: 24,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < actionButtons.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  actionButtons[i],
                ],
              ],
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
              onPressed: (!isMyLocationButtonEnabled ||
                      _isLocatingUser ||
                      isPopupVisible)
                  ? null
                  : _handleMyLocationButtonPressed,
            ),
          ),
        ),
        if (currentPlayer != null)
          Positioned(
            left: 16,
            bottom: myLocationButtonBottom,
            child: SafeArea(
              left: false,
              top: false,
              bottom: false,
              minimum: const EdgeInsets.only(bottom: 16),
              child: _RoleBadge(
                role: currentPlayer.role,
                status: currentPlayer.status,
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

  void _handleGameEndStatusChange({
    required GameStatus? previousStatus,
    required GameStatus? currentStatus,
  }) {
    if (currentStatus == null) return;
    if (currentStatus != GameStatus.running && _hasTriggeredAutoGameEnd) {
      _hasTriggeredAutoGameEnd = false;
    }
    if (!_hasInitializedGameStatus) {
      _hasInitializedGameStatus = true;
      if (currentStatus == GameStatus.ended) {
        _hasShownGameEndPopup = true;
      }
      return;
    }
    if (previousStatus != GameStatus.running &&
        currentStatus == GameStatus.running) {
      _notifyGameStarted();
    }
    if (currentStatus == GameStatus.ended &&
        previousStatus != GameStatus.ended &&
        !_hasShownGameEndPopup) {
      final endedAt = DateTime.now();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _showGameEndPopup = true;
          _showGameSummaryPopup = false;
          _hasShownGameEndPopup = true;
          _gameEndedAt = endedAt;
        });
        _maybeNotifyMapPopup(
          notificationId:
              'game-end-${widget.gameId}-${endedAt.millisecondsSinceEpoch}',
          title: 'ゲームが終了しました',
          body: 'マップ画面を開いて結果を確認しましょう。',
        );
      });
      return;
    }
    if (currentStatus != GameStatus.ended && _hasShownGameEndPopup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _clearGameEndPopupState();
        });
      });
    }
  }

  void _clearGameEndPopupState() {
    _showGameEndPopup = false;
    _showGameSummaryPopup = false;
    _hasShownGameEndPopup = false;
    _gameEndedAt = null;
  }

  void _clearTimedEventPopupState() {
    _showTimedEventPopup = false;
    _activeTimedEvent = null;
  }

  void _notifyGameStarted() {
    final role = _latestPlayerRole;
    final body = switch (role) {
      PlayerRole.oni => '逃走者が動き出しました。マップで位置を確認して捕獲を開始しましょう。',
      PlayerRole.runner => 'ゲームが始まりました。仲間と協力して発電所を解除しましょう。',
      _ => 'ゲームが始まりました。マップ画面で状況を確認しましょう。',
    };
    _maybeNotifyMapPopup(
      notificationId:
          'game-start-${widget.gameId}-${DateTime.now().millisecondsSinceEpoch}',
      title: 'ゲームが開始しました',
      body: body,
    );
  }

  void _handleGameEndPopupNext() {
    if (!_showGameEndPopup) return;
    setState(() {
      _showGameEndPopup = false;
      _showGameSummaryPopup = true;
    });
  }

  void _handleGameSummaryClose() {
    if (!_showGameSummaryPopup) return;
    setState(() {
      _showGameSummaryPopup = false;
    });
  }

  void _maybeHandleTimedEvents({
    required Game? game,
    required List<Player>? players,
  }) {
    final status = game?.status;
    final startAt = game?.startAt;
    if (status != GameStatus.running || startAt == null) {
      final shouldHidePopup = _showTimedEventPopup || _activeTimedEvent != null;
      _triggeredTimedEventQuarters.clear();
      _currentGameStartAt = null;
      _pendingTimedEventQuarter = null;
      if (shouldHidePopup) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(_clearTimedEventPopupState);
        });
      }
      return;
    }
    if (_currentGameStartAt != startAt) {
      _currentGameStartAt = startAt;
      _triggeredTimedEventQuarters.clear();
      _pendingTimedEventQuarter = null;
    }
    final totalDurationSeconds =
        game?.gameDurationSec ?? _defaultGameDurationSeconds;
    if (totalDurationSeconds <= 0) {
      return;
    }
    final elapsed = game?.runningElapsedSeconds;
    if (elapsed == null || elapsed <= 0) {
      return;
    }
    final double quarterDuration = totalDurationSeconds / 4;
    for (var quarter = 1; quarter <= 3; quarter++) {
      final thresholdSeconds = (quarterDuration * quarter).ceil();
      final hasTriggered = _triggeredTimedEventQuarters.contains(quarter);
      if (elapsed >= thresholdSeconds &&
          !hasTriggered &&
          _pendingTimedEventQuarter != quarter) {
        _triggeredTimedEventQuarters.add(quarter);
        _pendingTimedEventQuarter = quarter;
        final popupData = _buildTimedEventPopupData(
          quarterIndex: quarter,
          totalDurationSeconds: totalDurationSeconds,
          players: players,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _activeTimedEvent = popupData;
            _showTimedEventPopup = true;
            _pendingTimedEventQuarter = null;
          });
        });
        _recordTimedEventTrigger(popupData);
        _maybeNotifyMapPopup(
          notificationId: 'timed-event-${widget.gameId}-$quarter',
          title: 'イベント発生',
          body: '新しいイベントミッションが届きました。マップで詳細を確認してください。',
        );
        break;
      }
    }
  }

  void _handleTimedEventPopupDismissed() {
    if (!_showTimedEventPopup && _activeTimedEvent == null) {
      return;
    }
    setState(_clearTimedEventPopupState);
  }

  void _recordTimedEventTrigger(_TimedEventPopupData data) {
    final repo = ref.read(gameEventRepositoryProvider);
    unawaited(
      repo
          .recordTimedEventTrigger(
        gameId: widget.gameId,
        quarterIndex: data.quarterIndex,
        requiredRunners: data.requiredRunners,
        eventDurationSeconds: data.eventDurationSeconds,
        percentProgress: data.percentProgress,
        eventTimeLabel: data.eventTimeLabel,
        totalRunnerCount: data.totalRunnerCount,
      )
          .catchError((error, stackTrace) {
        debugPrint('Failed to record timed event trigger: $error');
        debugPrint('$stackTrace');
      }),
    );
  }

  Future<void> _initializeKodouPlayer() async {
    final player = AudioPlayer();
    await player.setReleaseMode(ReleaseMode.loop);
    if (!mounted) {
      await player.dispose();
      return;
    }
    _kodouPlayer = player;
    if (_shouldPlayKodouSound) {
      _ensureKodouPlaying();
    }
  }

  void _updateKodouSound({required bool shouldPlay}) {
    if (_shouldPlayKodouSound == shouldPlay && _kodouPlayer != null) {
      if (shouldPlay == _isKodouPlaying) {
        return;
      }
    }
    _shouldPlayKodouSound = shouldPlay;
    if (shouldPlay) {
      _ensureKodouPlaying();
    } else {
      _ensureKodouStopped();
    }
  }

  void _ensureKodouPlaying() {
    if (!_shouldPlayKodouSound) return;
    final player = _kodouPlayer;
    if (player == null || _isKodouPlaying) {
      return;
    }
    _isKodouPlaying = true;
    unawaited(
      player.play(AssetSource(_kodouSoundAssetPath)).catchError((error, _) {
        debugPrint('Failed to play kodou sound: $error');
        _isKodouPlaying = false;
      }),
    );
  }

  void _ensureKodouStopped() {
    if (!_isKodouPlaying) {
      return;
    }
    _isKodouPlaying = false;
    final player = _kodouPlayer;
    if (player == null) {
      return;
    }
    unawaited(
      player.stop().catchError((error, _) {
        debugPrint('Failed to stop kodou sound: $error');
      }),
    );
  }

  Future<void> _attemptInitialUserLocationFocus() async {
    try {
      final status = await ref.read(locationPermissionStatusProvider.future);
      if (!_hasForegroundLocationPermission(status)) {
        return;
      }
      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (position == null) {
        return;
      }
      final target = LatLng(position.latitude, position.longitude);
      _latestUserLocation = target;
      _cameraTarget = target;
      if (!mounted) return;
      _maybeCenterCameraOnUserInitially();
    } catch (error, stackTrace) {
      debugPrint('Failed to obtain initial map location: $error');
      debugPrint('$stackTrace');
    }
  }

  void _maybeCenterCameraOnUserInitially() {
    if (_hasCenteredOnUserInitially) {
      return;
    }
    final controller = _mapController;
    final target = _latestUserLocation;
    if (controller == null || target == null) {
      return;
    }
    _hasCenteredOnUserInitially = true;
    _cameraTarget = target;
    unawaited(
      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: target,
            zoom: _initialMapZoom,
          ),
        ),
      ),
    );
  }

  void _maybeTriggerAutoStart({
    required Game? game,
    required BuildContext context,
    required bool isCountdownActive,
    required int? remainingSeconds,
  }) {
    if (game == null || game.status != GameStatus.countdown) {
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
      unawaited(_startGameAfterCountdown(context));
    }
  }

  Future<void> _startGameAfterCountdown(
    BuildContext context,
  ) async {
    try {
      final controller = ref.read(gameControlControllerProvider);
      await controller.startGame(gameId: widget.gameId);
    } catch (error) {
      _countdownAutoStartTriggered = false;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ゲーム開始に失敗しました: $error')),
        );
      }
    }
  }

  int? _calculateCountdownRemainingSeconds(Game? game) {
    if (game == null) return null;
    final endAt = game.countdownEndAt;
    if (endAt == null) {
      return game.countdownRemainingSeconds;
    }
    final serverTimeService = ref.read(serverTimeServiceProvider);
    final now = serverTimeService.now();
    final remaining = endAt.difference(now).inSeconds;
    if (remaining < 0) {
      return 0;
    }
    return remaining;
  }

  void _maybeTriggerAutoGameEnd({
    required Game? game,
    required bool allPinsCleared,
    required bool allRunnersDown,
    required int? runningRemainingSeconds,
    required int? pinCount,
  }) {
    if (game?.status != GameStatus.running) {
      return;
    }
    final result = _autoGameEndResult(
      allPinsCleared: allPinsCleared,
      allRunnersDown: allRunnersDown,
      runningRemainingSeconds: runningRemainingSeconds,
    );
    if (result == null) {
      return;
    }
    if (_hasTriggeredAutoGameEnd) {
      return;
    }
    _hasTriggeredAutoGameEnd = true;
    unawaited(_endGameAutomatically(pinCount: pinCount, result: result));
  }

  GameEndResult? _autoGameEndResult({
    required bool allPinsCleared,
    required bool allRunnersDown,
    required int? runningRemainingSeconds,
  }) {
    if (allPinsCleared) {
      return GameEndResult.runnerVictory;
    }
    if (allRunnersDown) {
      return GameEndResult.oniVictory;
    }
    final isTimeExpired =
        runningRemainingSeconds != null && runningRemainingSeconds <= 0;
    if (isTimeExpired) {
      return GameEndResult.draw;
    }
    return null;
  }

  Future<void> _endGameAutomatically({
    required int? pinCount,
    required GameEndResult result,
  }) async {
    try {
      final controller = ref.read(gameControlControllerProvider);
      await controller.endGame(
        gameId: widget.gameId,
        pinCount: pinCount,
        result: result,
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to end game automatically: $error');
      debugPrint('$stackTrace');
      _hasTriggeredAutoGameEnd = false;
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
      if (!_hasForegroundLocationPermission(status)) {
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
      if (mounted) {
        setState(() {
          _isLocatingUser = false;
        });
      }
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

  Future<void> _handleRescuePressed(Player target) async {
    if (_isRescuing) {
      return;
    }
    final auth = ref.read(firebaseAuthProvider);
    final rescuerUid = auth.currentUser?.uid;
    if (rescuerUid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('サインイン情報を確認できませんでした')),
      );
      return;
    }
    setState(() {
      _isRescuing = true;
    });
    try {
      final repo = ref.read(rescueRepositoryProvider);
      await repo.rescueRunner(
        gameId: widget.gameId,
        rescuerUid: rescuerUid,
        victimUid: target.uid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${target.nickname} を救出しました')),
        );
      }
    } catch (error) {
      if (mounted) {
        final message = error is StateError ? error.message : error.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('救出に失敗しました: $message')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRescuing = false;
        });
      }
    }
  }

  Future<void> _handleClearPinPressed(PinPoint pin) async {
    if (_isClearingPin) {
      return;
    }
    if (pin.status != PinStatus.pending) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('この発電所は現在解除できません')),
      );
      return;
    }
    try {
      setState(() {
        _isClearingPin = true;
        _activeClearingPinId = pin.id;
        _pinClearRemainingSeconds = _pinClearDurationSeconds;
      });
      _startPinClearTimer();
      final repo = ref.read(pinRepositoryProvider);
      await repo.updatePinStatus(
        gameId: widget.gameId,
        pinId: pin.id,
        status: PinStatus.clearing,
      );
    } catch (error) {
      final message = error is StateError ? error.message : error.toString();
      await _cancelPinClearing(
        resetStatus: false,
        message: '発電所の解除を開始できませんでした: $message',
      );
    }
  }

  void _startPinClearTimer() {
    _pinClearTimer?.cancel();
    _pinClearTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = _pinClearRemainingSeconds;
      if (remaining == null) {
        return;
      }
      final nextValue = remaining - 1;
      if (!mounted) return;
      if (nextValue <= 0) {
        setState(() {
          _pinClearRemainingSeconds = 0;
        });
        _pinClearTimer?.cancel();
        _pinClearTimer = null;
        unawaited(_finalizePinClearing());
      } else {
        setState(() {
          _pinClearRemainingSeconds = nextValue;
        });
      }
    });
  }

  Future<void> _finalizePinClearing() async {
    final pinId = _activeClearingPinId;
    if (pinId == null) {
      _resetPinClearingState();
      return;
    }
    final repo = ref.read(pinRepositoryProvider);
    try {
      await repo.updatePinStatus(
        gameId: widget.gameId,
        pinId: pinId,
        status: PinStatus.cleared,
      );
      _resetPinClearingState();
      _showSnackBar('発電所を解除しました');
    } catch (error) {
      try {
        await repo.updatePinStatus(
          gameId: widget.gameId,
          pinId: pinId,
          status: PinStatus.pending,
        );
      } catch (resetError) {
        debugPrint('Failed to reset pin after clear failure: $resetError');
      }
      _resetPinClearingState();
      final message = error is StateError ? error.message : error.toString();
      _showSnackBar('発電所の解除に失敗しました: $message');
    }
  }

  Future<void> _cancelPinClearing({
    bool resetStatus = false,
    String? message,
  }) async {
    if (!_isClearingPin && _activeClearingPinId == null) {
      if (message != null) {
        _showSnackBar(message);
      }
      return;
    }
    final pinId = _activeClearingPinId;
    _resetPinClearingState();
    if (resetStatus && pinId != null) {
      final repo = ref.read(pinRepositoryProvider);
      try {
        await repo.updatePinStatus(
          gameId: widget.gameId,
          pinId: pinId,
          status: PinStatus.pending,
        );
      } catch (error) {
        debugPrint('Failed to reset pin status: $error');
      }
    }
    if (message != null) {
      _showSnackBar(message);
    }
  }

  void _resetPinClearingState() {
    _pinClearTimer?.cancel();
    _pinClearTimer = null;
    if (!mounted) return;
    if (!_isClearingPin &&
        _pinClearRemainingSeconds == null &&
        _activeClearingPinId == null) {
      return;
    }
    setState(() {
      _isClearingPin = false;
      _pinClearRemainingSeconds = null;
      _activeClearingPinId = null;
    });
  }

  void _maybeCancelClearingWhenOutOfRange() {
    if (!_isClearingPin || _activeClearingPinId == null) return;
    final radius = _latestCaptureRadiusMeters;
    final selfPosition = _latestUserLocation;
    if (radius == null || radius <= 0) return;
    if (selfPosition == null) return;
    final pin = _findPinById(_activeClearingPinId!);
    final distance = _distanceToPin(pin, selfPosition);
    if (distance != null && distance > radius) {
      unawaited(
        _cancelPinClearing(
          resetStatus: true,
          message: '発電所から離れたため解除が中断されました',
        ),
      );
    }
  }

  void _handleActiveClearingPinSnapshot(List<PinPoint> pins) {
    final activeId = _activeClearingPinId;
    if (activeId == null || !_isClearingPin) return;
    final pin = _findPinById(activeId, pins);
    if (pin == null) {
      _resetPinClearingState();
      return;
    }
    switch (pin.status) {
      case PinStatus.clearing:
        return;
      case PinStatus.cleared:
        _resetPinClearingState();
        _showSnackBar('他の逃走者が先に発電所を解除しました');
        break;
      case PinStatus.pending:
        _resetPinClearingState();
        _showSnackBar('解除が中断されました');
        break;
    }
  }

  void _maybeCancelClearingWhenPlayerUnavailable(Player? player) {
    if (!_isClearingPin || player == null) return;
    final canContinue = player.role == PlayerRole.runner &&
        player.isActive &&
        player.status == PlayerStatus.active;
    if (canContinue) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isClearingPin) return;
      unawaited(
        _cancelPinClearing(
          resetStatus: true,
          message: '解除が中断されました',
        ),
      );
    });
  }

  void _maybeCancelClearingWhenGameInactive(Game? game) {
    if (!_isClearingPin) return;
    if (game == null || game.status == GameStatus.running) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isClearingPin) return;
      unawaited(
        _cancelPinClearing(
          resetStatus: true,
          message: 'ゲームの状態により解除が中断されました',
        ),
      );
    });
  }

  void _updatePinClearDuration(Game? game) {
    final rawSeconds = game?.generatorClearDurationSec;
    final sanitized = (rawSeconds ?? _defaultPinClearDurationSeconds)
        .clamp(_minPinClearDurationSeconds, _maxPinClearDurationSeconds)
        .toInt();
    if (_pinClearDurationSeconds == sanitized) {
      return;
    }
    _pinClearDurationSeconds = sanitized;
    if (_isClearingPin && _pinClearRemainingSeconds != null) {
      _pinClearRemainingSeconds =
          _pinClearRemainingSeconds!.clamp(0, sanitized).toInt();
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _handlePinClearingNotifications(List<PinPoint> pins) {
    if (_latestGameStatus != GameStatus.running ||
        _latestPlayerRole != PlayerRole.oni) {
      if (_knownClearingPinIds.isNotEmpty) {
        _knownClearingPinIds.clear();
      }
      _dismissOniClearingAlert();
      return;
    }
    final clearingPins = pins
        .where((pin) => pin.status == PinStatus.clearing && !pin.cleared)
        .map((pin) => pin.id)
        .toSet();
    final previousActivePinId = _oniClearingPinId;
    final previousKnownPins = Set<String>.from(_knownClearingPinIds);
    String? newPinId;
    for (final id in clearingPins) {
      if (!previousKnownPins.contains(id)) {
        newPinId = id;
        break;
      }
    }
    _knownClearingPinIds
      ..clear()
      ..addAll(clearingPins);
    if (clearingPins.isEmpty) {
      _dismissOniClearingAlert();
      return;
    }
    if (newPinId != null) {
      _showOniClearingAlert(newPinId, isNewClearing: true);
      return;
    }
    final isActiveStillClearing = previousActivePinId != null &&
        clearingPins.contains(previousActivePinId);
    if (!isActiveStillClearing) {
      final fallbackId = clearingPins.first;
      _showOniClearingAlert(fallbackId, isNewClearing: false);
    }
  }

  void _handlePinClearedNotifications(List<PinPoint> pins) {
    final isParticipant = _latestPlayerRole == PlayerRole.oni ||
        _latestPlayerRole == PlayerRole.runner;
    if (_latestGameStatus != GameStatus.running || !isParticipant) {
      if (_knownClearedPinIds.isNotEmpty) {
        _knownClearedPinIds.clear();
      }
      _hasSeededClearedPins = false;
      _dismissGeneratorClearedAlert();
      return;
    }
    final clearedPins = pins
        .where((pin) => pin.status == PinStatus.cleared || pin.cleared)
        .map((pin) => pin.id)
        .toSet();
    if (!_hasSeededClearedPins) {
      _hasSeededClearedPins = true;
      _knownClearedPinIds
        ..clear()
        ..addAll(clearedPins);
      return;
    }
    String? newPinId;
    for (final id in clearedPins) {
      if (!_knownClearedPinIds.contains(id)) {
        newPinId = id;
        break;
      }
    }
    _knownClearedPinIds
      ..clear()
      ..addAll(clearedPins);
    if (newPinId != null) {
      _showGeneratorClearedAlertForPin(newPinId);
    }
    if (clearedPins.isEmpty && _showGeneratorClearedAlert) {
      _dismissGeneratorClearedAlert();
    }
  }

  void _handleGameEvents(List<GameEvent> events) {
    if (!_hasSeededGameEvents) {
      _hasSeededGameEvents = true;
      if (events.isNotEmpty) {
        for (final event in events) {
          _handledGameEventIds.add(event.id);
        }
        _trimHandledGameEvents();
      }
      return;
    }
    if (events.isEmpty) return;
    final currentUid = ref.read(firebaseAuthProvider).currentUser?.uid;
    for (final event in events) {
      if (event.type == GameEventType.unknown) continue;
      if (_handledGameEventIds.contains(event.id)) {
        continue;
      }
      _handledGameEventIds.add(event.id);
      if (event.type == GameEventType.rescue) {
        if (currentUid == null) {
          continue;
        }
        final message = _messageForRescueEvent(event, currentUid);
        if (message == null) {
          continue;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _showCaptureAlert = false;
            _captureAlertMessage = null;
            _showRescueAlert = true;
            _rescueAlertMessage = message;
          });
        });
        _maybeNotifyMapPopup(
          notificationId: 'rescue-${event.id}',
          title: '救出が完了しました',
          body: message,
        );
        break;
      }
      if (event.type == GameEventType.capture) {
        final message = _messageForCaptureEvent(event);
        if (message == null) {
          continue;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _showRescueAlert = false;
            _rescueAlertMessage = null;
            _showCaptureAlert = true;
            _captureAlertMessage = message;
          });
        });
        _maybeNotifyMapPopup(
          notificationId: 'capture-${event.id}',
          title: '捕獲が発生しました',
          body: message,
        );
        break;
      }
    }
    _trimHandledGameEvents();
  }

  String? _messageForRescueEvent(GameEvent event, String currentUid) {
    final rescuerUid = event.actorUid;
    final victimUid = event.targetUid;
    final rescuerName = event.actorName ?? '逃走者';
    final victimName = event.targetName ?? '逃走者';
    if (rescuerUid == null || victimUid == null) {
      return '$victimName が救出されました';
    }
    if (currentUid == rescuerUid) {
      return '$victimName を救出しました';
    }
    if (currentUid == victimUid) {
      return '$rescuerName から救出されました';
    }
    return '$victimName が救出されました';
  }

  String? _messageForCaptureEvent(GameEvent event) {
    final attackerName = event.actorName ?? '鬼';
    final victimName = event.targetName ?? '逃走者';
    if (_latestPlayerRole == PlayerRole.oni) {
      return '$attackerName が $victimName を捕獲しました';
    }
    return '$victimName が捕獲されました';
  }

  void _trimHandledGameEvents() {
    const maxEntries = 100;
    if (_handledGameEventIds.length <= maxEntries) {
      return;
    }
    final removeCount = _handledGameEventIds.length - maxEntries;
    final iterator = _handledGameEventIds.iterator;
    final idsToRemove = <String>{};
    var removed = 0;
    while (removed < removeCount && iterator.moveNext()) {
      idsToRemove.add(iterator.current);
      removed++;
    }
    _handledGameEventIds.removeAll(idsToRemove);
  }

  void _dismissRescueAlert() {
    if (!_showRescueAlert) return;
    setState(() {
      _showRescueAlert = false;
      _rescueAlertMessage = null;
    });
  }

  void _dismissCaptureAlert() {
    if (!_showCaptureAlert) return;
    setState(() {
      _showCaptureAlert = false;
      _captureAlertMessage = null;
    });
  }

  void _showGeneratorClearedAlertForPin(String pinId) {
    setState(() {
      _showGeneratorClearedAlert = true;
    });
    final role = _latestPlayerRole;
    String body;
    if (role == PlayerRole.oni) {
      body = '逃走者が発電所を解除しました。マップで位置を確認してください。';
    } else if (role == PlayerRole.runner) {
      body = '仲間の逃走者が発電所を解除しました。次の発電所へ向かいましょう。';
    } else {
      body = '発電所が解除されました。マップで状況を確認しましょう。';
    }
    _maybeNotifyMapPopup(
      notificationId: 'generator-cleared-$pinId',
      title: '発電所が解除されました',
      body: body,
    );
  }

  void _dismissGeneratorClearedAlert() {
    if (_showGeneratorClearedAlert) {
      setState(() {
        _showGeneratorClearedAlert = false;
      });
    }
  }

  void _showOniClearingAlert(String pinId, {required bool isNewClearing}) {
    _oniClearingAlertTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _oniClearingPinId = pinId;
      _isOniClearingAlertVisible = true;
    });
    if (isNewClearing) {
      _maybeNotifyMapPopup(
        notificationId: 'generator-clearing-$pinId',
        title: '発電所の解除が始まりました',
        body: '逃走者が発電所の解除を開始しました。すぐに確認してください。',
      );
    }
    _oniClearingAlertTimer = Timer(
      const Duration(seconds: _oniClearingAlertDurationSeconds),
      () {
        _oniClearingAlertTimer = null;
        if (!mounted) return;
        setState(() {
          _isOniClearingAlertVisible = false;
        });
      },
    );
  }

  void _dismissOniClearingAlert() {
    _oniClearingAlertTimer?.cancel();
    _oniClearingAlertTimer = null;
    if (!mounted) {
      _oniClearingPinId = null;
      _isOniClearingAlertVisible = false;
      return;
    }
    if (_oniClearingPinId == null && !_isOniClearingAlertVisible) {
      return;
    }
    setState(() {
      _oniClearingPinId = null;
      _isOniClearingAlertVisible = false;
    });
  }

  Future<void> _loadCustomMarkers() async {
    const markerIconFactory = MarkerIconFactory();
    try {
      final results = await Future.wait([
        markerIconFactory.create(
          color: Colors.redAccent,
          icon: Icons.whatshot,
        ),
        markerIconFactory.create(
          color: Colors.green,
          icon: Icons.run_circle,
        ),
        markerIconFactory.create(
          color: Colors.grey.shade600,
          icon: Icons.run_circle,
        ),
        markerIconFactory.create(
          color: Colors.yellow.shade600,
          icon: Icons.electric_bolt,
        ),
        markerIconFactory.create(
          color: Colors.orange.shade600,
          icon: Icons.electric_bolt,
        ),
        markerIconFactory.create(
          color: Colors.grey.shade500,
          icon: Icons.electric_bolt,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _oniMarkerDescriptor = results[0];
        _runnerMarkerDescriptor = results[1];
        _downedMarkerDescriptor = results[2];
        _generatorPinMarkerDescriptor = results[3];
        _clearingPinMarkerDescriptor = results[4];
        _clearedPinMarkerDescriptor = results[5];
      });
    } catch (error) {
      debugPrint('Failed to load custom markers: $error');
    }
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

  _RescueTargetInfo? _findRescueTarget({
    required GameStatus? gameStatus,
    required Player? currentPlayer,
    required double? captureRadiusMeters,
    required LatLng? selfPosition,
    required List<Player>? players,
  }) {
    if (gameStatus != GameStatus.running) return null;
    if (currentPlayer == null || currentPlayer.role != PlayerRole.runner) {
      return null;
    }
    if (!currentPlayer.isActive ||
        currentPlayer.status != PlayerStatus.active) {
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
      if (!player.isActive) continue;
      if (player.role != PlayerRole.runner) continue;
      if (player.status != PlayerStatus.downed) continue;
      final targetPosition = player.position;
      if (targetPosition == null) continue;
      final distance = Geolocator.distanceBetween(
        selfPosition.latitude,
        selfPosition.longitude,
        targetPosition.latitude,
        targetPosition.longitude,
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
    return _RescueTargetInfo(
      runner: closestRunner,
      distanceMeters: closestDistance,
    );
  }

  _NearbyPinInfo? _findNearbyPin({
    required GameStatus? gameStatus,
    required Player? currentPlayer,
    required double? captureRadiusMeters,
    required LatLng? selfPosition,
    required List<PinPoint>? pins,
  }) {
    if (gameStatus != GameStatus.running) return null;
    if (currentPlayer == null || currentPlayer.role != PlayerRole.runner) {
      return null;
    }
    if (!currentPlayer.isActive ||
        currentPlayer.status != PlayerStatus.active) {
      return null;
    }
    if (captureRadiusMeters == null || captureRadiusMeters <= 0) {
      return null;
    }
    if (selfPosition == null) return null;
    if (pins == null || pins.isEmpty) return null;

    PinPoint? closestPin;
    double? closestDistance;

    for (final pin in pins) {
      if (pin.status != PinStatus.pending) continue;
      final distance = Geolocator.distanceBetween(
        selfPosition.latitude,
        selfPosition.longitude,
        pin.lat,
        pin.lng,
      );
      if (distance > captureRadiusMeters) continue;
      if (closestDistance == null || distance < closestDistance) {
        closestDistance = distance;
        closestPin = pin;
      }
    }

    if (closestPin == null || closestDistance == null) {
      return null;
    }
    return _NearbyPinInfo(
      pin: closestPin,
      distanceMeters: closestDistance,
    );
  }

  PinPoint? _findPinById(
    String id, [
    List<PinPoint>? pins,
  ]) {
    final source = pins ?? _latestPins;
    for (final pin in source) {
      if (pin.id == id) {
        return pin;
      }
    }
    return null;
  }

  double? _distanceToPin(PinPoint? pin, LatLng? selfPosition) {
    if (pin == null || selfPosition == null) {
      return null;
    }
    return Geolocator.distanceBetween(
      selfPosition.latitude,
      selfPosition.longitude,
      pin.lat,
      pin.lng,
    );
  }

  bool _isRunnerDetectedByOni({
    required Game? game,
    required Player? currentPlayer,
    required LatLng? selfPosition,
    required List<Player>? players,
  }) {
    if (game?.status != GameStatus.running) return false;
    if (currentPlayer == null || currentPlayer.role != PlayerRole.runner) {
      return false;
    }
    if (!currentPlayer.isActive ||
        currentPlayer.status != PlayerStatus.active ||
        selfPosition == null) {
      return false;
    }
    final detectionRadius = game?.killerDetectRunnerRadiusM?.toDouble();
    if (detectionRadius == null || detectionRadius <= 0) {
      return false;
    }
    if (players == null || players.isEmpty) {
      return false;
    }
    for (final player in players) {
      if (player.role != PlayerRole.oni) continue;
      if (!player.isActive || player.status != PlayerStatus.active) {
        continue;
      }
      final position = player.position;
      if (position == null) continue;
      final distance = Geolocator.distanceBetween(
        selfPosition.latitude,
        selfPosition.longitude,
        position.latitude,
        position.longitude,
      );
      if (distance <= detectionRadius) {
        return true;
      }
    }
    return false;
  }

  Set<Marker> _buildPlayerMarkers({
    required AsyncValue<List<Player>> playersState,
    required String? currentUid,
    required Player? currentPlayer,
    required LatLng? selfPosition,
    required Game? game,
  }) {
    final markers = <Marker>{};
    final viewerPosition = selfPosition ?? currentPlayer?.position;
    playersState.whenData((players) {
      for (final player in players) {
        if (player.uid == currentUid) continue;
        final position = player.position;
        if (position == null) continue;
        if (!_isPlayerVisibleToViewer(
          viewer: currentPlayer,
          target: player,
          viewerPosition: viewerPosition,
          game: game,
        )) {
          continue;
        }
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

  bool _isPlayerVisibleToViewer({
    required Player? viewer,
    required Player target,
    required LatLng? viewerPosition,
    required Game? game,
  }) {
    if (viewer == null) return true;
    final viewerRole = viewer.role;
    final targetRole = target.role;
    final position = target.position;
    if (position == null) return false;
    final radius = switch ((viewerRole, targetRole)) {
      (PlayerRole.runner, PlayerRole.oni) =>
        game?.runnerSeeKillerRadiusM?.toDouble(),
      (PlayerRole.runner, PlayerRole.runner) =>
        game?.runnerSeeRunnerRadiusM?.toDouble(),
      (PlayerRole.oni, PlayerRole.runner) =>
        game?.killerDetectRunnerRadiusM?.toDouble(),
      _ => null,
    };
    if (radius == null || radius <= 0) {
      return true;
    }
    final viewerLatLng = viewerPosition;
    if (viewerLatLng == null) {
      return true;
    }
    final distance = Geolocator.distanceBetween(
      viewerLatLng.latitude,
      viewerLatLng.longitude,
      position.latitude,
      position.longitude,
    );
    return distance <= radius;
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
      final iconDescriptor = _pinIconForStatus(pin.status);
      markers.add(
        Marker(
          markerId: MarkerId('pin-${pin.id}'),
          position: position,
          icon: iconDescriptor,
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
    if (_shouldAlwaysDisplayPin(pin)) {
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

  bool _shouldAlwaysDisplayPin(PinPoint pin) {
    if (pin.cleared) return true;
    return pin.status == PinStatus.cleared || pin.status == PinStatus.clearing;
  }

  String _pinStatusLabel(PinStatus status) {
    return switch (status) {
      PinStatus.pending => '稼働中',
      PinStatus.clearing => '解除中',
      PinStatus.cleared => '解除済み',
    };
  }

  BitmapDescriptor _pinIconForStatus(PinStatus status) {
    switch (status) {
      case PinStatus.pending:
        return _generatorPinMarkerDescriptor ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
      case PinStatus.clearing:
        return _clearingPinMarkerDescriptor ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
      case PinStatus.cleared:
        return _clearedPinMarkerDescriptor ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }
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
        if (status != LocationPermissionStatus.limited &&
            _backgroundPermissionDialogDismissed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _backgroundPermissionDialogDismissed = false;
            });
          });
        }

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

        if (status == LocationPermissionStatus.limited &&
            !_backgroundPermissionDialogDismissed) {
          return _BackgroundPermissionDialog(
            message: 'バックグラウンドでも位置情報を共有するには「常に許可」を設定してください。',
            actionLabel: '設定を開く',
            onActionTap: () async {
              await Geolocator.openAppSettings();
              if (mounted) {
                setState(() {
                  _backgroundPermissionDialogDismissed = false;
                });
              }
              ref.invalidate(locationPermissionStatusProvider);
            },
            onClose: () {
              if (!mounted) return;
              setState(() {
                _backgroundPermissionDialogDismissed = true;
              });
            },
          );
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
          LocationPermissionStatus.limited => (
              '',
              null,
              null,
            ),
        };

        if (message.isEmpty && actionLabel == null && action == null) {
          return null;
        }

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
                style: theme.textTheme.displayLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ) ??
                    const TextStyle(
                      fontSize: 80,
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

  int? _calculateGameDurationSeconds(Game? game) {
    final startAt = game?.startAt;
    final endedAt = _gameEndedAt;
    if (startAt == null || endedAt == null) {
      return null;
    }
    final seconds = endedAt.difference(startAt).inSeconds;
    if (seconds < 0) {
      return 0;
    }
    return seconds;
  }

  String _formatElapsedDuration(int? seconds) {
    if (seconds == null) return '---';
    if (seconds <= 0) return '0秒';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '${hours}時間${minutes}分${secs}秒';
    }
    if (minutes > 0) {
      return '${minutes}分${secs}秒';
    }
    return '${secs}秒';
  }

  _TimedEventPopupData _buildTimedEventPopupData({
    required int quarterIndex,
    required int totalDurationSeconds,
    required List<Player>? players,
  }) {
    final totalRunnerCount = _countTotalRunners(players);
    final requiredRunners =
        _resolveTimedEventRequiredRunners(totalRunnerCount);
    final eventDurationSeconds =
        math.max(1, (totalDurationSeconds / 8).round());
    final eventDurationLabel =
        _formatEventDurationLabel(eventDurationSeconds);
    final percentProgress = quarterIndex * 25;
    final computedSeconds =
        (totalDurationSeconds / 4 * quarterIndex).round();
    final eventSeconds = math.max(
      0,
      math.min(computedSeconds, totalDurationSeconds),
    );
    final eventTimeLabel = _formatTimedEventTimeMark(eventSeconds);
    final quarterLabel = _quarterLabelForIndex(quarterIndex);
    final slides = _buildTimedEventSlides(
      quarterLabel: quarterLabel,
      percentProgress: percentProgress,
      eventTimeLabel: eventTimeLabel,
      requiredRunners: requiredRunners,
      eventDurationLabel: eventDurationLabel,
      totalRunnerCount: totalRunnerCount,
    );
    return _TimedEventPopupData(
      quarterIndex: quarterIndex,
      quarterLabel: quarterLabel,
      percentProgress: percentProgress,
      eventTimeLabel: eventTimeLabel,
      requiredRunners: requiredRunners,
      eventDurationSeconds: eventDurationSeconds,
      eventDurationLabel: eventDurationLabel,
      totalRunnerCount: totalRunnerCount,
      slides: slides,
    );
  }

  List<_TimedEventSlideData> _buildTimedEventSlides({
    required String quarterLabel,
    required int percentProgress,
    required String eventTimeLabel,
    required int requiredRunners,
    required String eventDurationLabel,
    required int totalRunnerCount,
  }) {
    final runnerCountLabel =
        totalRunnerCount > 0 ? '$totalRunnerCount人' : '不明';
    return [
      _TimedEventSlideData(
        title: '$quarterLabelの進行状況',
        description:
            'ゲーム時間の$percentProgress%（開始から$eventTimeLabel）に到達しました。'
            'このタイミングで「イベント発生」フェーズが始まり、マップには今回のターゲットとなる発電所が明示されます。'
            'プレイヤー全員で場所を確認し、次のミッション達成に備えてください。',
      ),
      _TimedEventSlideData(
        title: '逃走者のミッション',
        description:
            '逃走者チームは$eventDurationLabel以内に、少なくとも${requiredRunners}人が同じ発電所を同時に解除する必要があります。'
            '現在の逃走者数は$runnerCountLabelです。解除を担当するメンバーと警戒を担当するメンバーを分け、'
            'マップに示された対象発電所を守りながら安全にカウントダウンを完了させましょう。',
      ),
      _TimedEventSlideData(
        title: '達成できなかった場合',
        description:
            '制限時間内に${requiredRunners}人の解除が達成できないと、鬼の捕獲半径が次のイベントまで2倍に拡大します。'
            '鬼は広い範囲から逃走者を捕捉できるようになるため、解除が難しそうな場合でも粘り強く連携し、'
            'リスクを最小限に抑えてイベントを乗り切ってください。',
      ),
    ];
  }

  String _quarterLabelForIndex(int quarterIndex) {
    switch (quarterIndex) {
      case 1:
        return '第1フェーズ';
      case 2:
        return '第2フェーズ';
      case 3:
        return '最終フェーズ';
      default:
        return 'イベント';
    }
  }

  String _formatTimedEventTimeMark(int seconds) {
    if (seconds <= 0) {
      return '直後';
    }
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      if (minutes == 0) {
        return '${hours}時間';
      }
      return '${hours}時間${minutes}分';
    }
    if (minutes > 0) {
      return '${minutes}分';
    }
    return '${seconds % 60}秒';
  }

  String _formatEventDurationLabel(int seconds) {
    if (seconds <= 0) {
      return '---';
    }
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes > 0 && secs > 0) {
      return '${minutes}分${secs}秒';
    }
    if (minutes > 0) {
      return '${minutes}分';
    }
    return '${secs}秒';
  }

  int _countTotalRunners(List<Player>? players) {
    if (players == null || players.isEmpty) {
      return 0;
    }
    var count = 0;
    for (final player in players) {
      if (player.role == PlayerRole.runner && player.isActive) {
        count++;
      }
    }
    return count;
  }

  int _resolveTimedEventRequiredRunners(int totalRunnerCount) {
    if (totalRunnerCount <= 0) {
      return _timedEventDefaultRequiredRunners;
    }
    return _timedEventRandom.nextInt(totalRunnerCount) + 1;
  }

  GameEndResult? _resolveGameEndResult({
    required Game? game,
    required bool allPinsCleared,
    required bool allRunnersDown,
  }) {
    final explicit = game?.endResult;
    if (explicit != null) {
      return explicit;
    }
    if (game?.status != GameStatus.ended) {
      return null;
    }
    if (allPinsCleared) {
      return GameEndResult.runnerVictory;
    }
    if (allRunnersDown) {
      return GameEndResult.oniVictory;
    }
    return GameEndResult.draw;
  }

  int _capturedRunnersCount(List<Player>? players) {
    if (players == null || players.isEmpty) {
      return 0;
    }
    var count = 0;
    for (final player in players) {
      if (player.role == PlayerRole.runner && player.stats.capturedTimes > 0) {
        count++;
      }
    }
    return count;
  }

  bool _areAllRunnersDown(List<Player>? players) {
    if (players == null || players.isEmpty) {
      return false;
    }
    final activeRunners = players
        .where((player) => player.role == PlayerRole.runner && player.isActive)
        .toList();
    if (activeRunners.isEmpty) {
      return false;
    }
    for (final runner in activeRunners) {
      if (runner.status == PlayerStatus.active) {
        return false;
      }
    }
    return true;
  }

  bool _areAllPinsCleared(List<PinPoint>? pins) {
    if (pins == null || pins.isEmpty) {
      return false;
    }
    for (final pin in pins) {
      if (!(pin.status == PinStatus.cleared || pin.cleared)) {
        return false;
      }
    }
    return true;
  }

  bool _hasForegroundLocationPermission(LocationPermissionStatus status) {
    return status == LocationPermissionStatus.granted ||
        status == LocationPermissionStatus.limited;
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

class _GameEndResultPopup extends StatelessWidget {
  const _GameEndResultPopup({
    required this.result,
    required this.onNext,
  });

  final GameEndResult? result;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedResult = result;
    late final String victoryText;
    late final Color victoryColor;
    switch (resolvedResult) {
      case GameEndResult.runnerVictory:
        victoryText = '逃走者の勝利！';
        victoryColor = const Color(0xFF22B59B);
        break;
      case GameEndResult.oniVictory:
        victoryText = '鬼の勝利！';
        victoryColor = theme.colorScheme.error;
        break;
      case GameEndResult.draw:
        victoryText = '引き分け';
        victoryColor = theme.colorScheme.primary;
        break;
      default:
        victoryText = '結果を確認してください';
        victoryColor = theme.colorScheme.primary;
        break;
    }
    return Card(
      color: theme.colorScheme.surface.withOpacity(0.96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ゲームが終了しました',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              victoryText,
              style: theme.textTheme.headlineSmall?.copyWith(
                    color: victoryColor,
                    fontWeight: FontWeight.w800,
                  ) ??
                  TextStyle(
                    fontSize: 24,
                    color: victoryColor,
                    fontWeight: FontWeight.w800,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onNext,
                child: const Text('結果を見る'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameSummaryPopup extends StatelessWidget {
  const _GameSummaryPopup({
    required this.capturedPlayersCount,
    required this.generatorsClearedCount,
    required this.gameDurationLabel,
    required this.onClose,
  });

  final int capturedPlayersCount;
  final int generatorsClearedCount;
  final String gameDurationLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget buildRow(String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      color: theme.colorScheme.surface.withOpacity(0.96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ゲーム内容',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            buildRow('捕獲者数', '$capturedPlayersCount人'),
            buildRow('発電機解除数', '$generatorsClearedCount箇所'),
            buildRow('ゲーム時間', gameDurationLabel),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onClose,
                child: const Text('閉じる'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimedEventPopup extends StatefulWidget {
  const _TimedEventPopup({
    required this.data,
    required this.onClose,
  });

  final _TimedEventPopupData data;
  final VoidCallback onClose;

  @override
  State<_TimedEventPopup> createState() => _TimedEventPopupState();
}

class _TimedEventPopupState extends State<_TimedEventPopup> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _handleBack() {
    if (_currentPage == 0) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _handleNext() {
    final isLastPage = _currentPage == widget.data.slides.length - 1;
    if (isLastPage) {
      widget.onClose();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slides = widget.data.slides;
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.dialogBackgroundColor,
          borderRadius: BorderRadius.circular(28),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'イベント発生',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.data.quarterLabel} · ゲーム経過${widget.data.percentProgress}% '
                  '（開始から${widget.data.eventTimeLabel}）',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _TimedEventInfoChip(
                        label: '必要人数',
                        value: '${widget.data.requiredRunners}人',
                      ),
                      _TimedEventInfoChip(
                        label: '制限時間',
                        value: widget.data.eventDurationLabel,
                      ),
                      if (widget.data.totalRunnerCount > 0)
                        _TimedEventInfoChip(
                          label: '逃走者',
                          value: '${widget.data.totalRunnerCount}人',
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 360,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: slides.length,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      final slide = slides[index];
                      return _TimedEventSlide(slide: slide);
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(slides.length, (index) {
                    final isActive = index == _currentPage;
                    final color = isActive
                        ? theme.colorScheme.primary
                        : theme.dividerColor;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      height: 8,
                      width: isActive ? 24 : 8,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    TextButton(
                      onPressed: _currentPage == 0 ? null : _handleBack,
                      child: const Text('戻る'),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: _handleNext,
                      child: Text(
                        _currentPage == slides.length - 1 ? '閉じる' : '次へ',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimedEventPopupData {
  const _TimedEventPopupData({
    required this.quarterIndex,
    required this.quarterLabel,
    required this.percentProgress,
    required this.eventTimeLabel,
    required this.requiredRunners,
    required this.eventDurationSeconds,
    required this.eventDurationLabel,
    required this.totalRunnerCount,
    required this.slides,
  });

  final int quarterIndex;
  final String quarterLabel;
  final int percentProgress;
  final String eventTimeLabel;
  final int requiredRunners;
  final int eventDurationSeconds;
  final String eventDurationLabel;
  final int totalRunnerCount;
  final List<_TimedEventSlideData> slides;
}

class _TimedEventSlideData {
  const _TimedEventSlideData({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;
}

class _TimedEventSlide extends StatelessWidget {
  const _TimedEventSlide({required this.slide});

  final _TimedEventSlideData slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.dividerColor.withOpacity(0.7);
    final fillColor = theme.colorScheme.surfaceVariant.withOpacity(
      theme.brightness == Brightness.dark ? 0.35 : 0.65,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          slide.title,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              color: fillColor,
              border: Border.all(color: borderColor),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            child: Text(
              slide.description,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    );
  }
}

class _TimedEventInfoChip extends StatelessWidget {
  const _TimedEventInfoChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.colorScheme.surfaceVariant.withOpacity(
      theme.brightness == Brightness.dark ? 0.45 : 0.85,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Text(
        '$label: $value',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _BackgroundPermissionDialog extends StatelessWidget {
  const _BackgroundPermissionDialog({
    required this.message,
    required this.actionLabel,
    required this.onActionTap,
    required this.onClose,
  });

  final String message;
  final String actionLabel;
  final FutureOr<void> Function()? onActionTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.6),
        alignment: Alignment.center,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 420,
              ),
              child: Material(
                borderRadius: BorderRadius.circular(24),
                color: theme.colorScheme.surface,
                elevation: 6,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            color: theme.colorScheme.primary,
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'バックグラウンド位置情報の許可が必要です',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        message,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          TextButton(
                            onPressed: onClose,
                            child: const Text('閉じる'),
                          ),
                          const Spacer(),
                          if (onActionTap != null)
                            FilledButton(
                              onPressed: onActionTap,
                              child: Text(actionLabel),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
  final FocusNode _composerFocusNode = FocusNode();
  final GlobalKey _composerKey = GlobalKey();
  final GlobalKey _headerKey = GlobalKey();
  bool _sending = false;
  bool _hasAutoScrolledToBottom = false;
  bool _isUserNearBottom = true;
  bool _isChatTutorialVisible = false;
  bool _hasCompletedChatTutorial = false;
  bool _chatTutorialStartPending = false;
  _ChatTutorialStep? _currentTutorialStep;
  Rect? _composerHighlightRect;
  Rect? _headerHighlightRect;
  ProviderSubscription<int>? _tabIndexSubscription;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScrollPositionChanged);
    _tabIndexSubscription = ref.listenManual<int>(
      gameShellTabIndexProvider,
      (previous, next) {
        if (next == 1) {
          unawaited(_handleChatTabActivated());
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(gameShellTabIndexProvider) == 1) {
        unawaited(_handleChatTabActivated());
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScrollPositionChanged);
    _controller.dispose();
    _scrollController.dispose();
    _tabIndexSubscription?.close();
    _composerFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isChatTutorialVisible) {
      _scheduleTutorialTargetCapture();
    }
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
    final gameState = ref.watch(gameStreamProvider(widget.gameId));
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
          final status = gameState.value?.status;
          final isTeamChat = status == null ||
              status == GameStatus.countdown ||
              status == GameStatus.running;
          final chatChannel = isTeamChat
              ? (player.role == PlayerRole.oni
                  ? ChatChannel.oni
                  : ChatChannel.runner)
              : ChatChannel.general;
          final palette = _ChatPalette.fromContext(
            role: player.role,
            channel: chatChannel,
          );
          final headerTitle = isTeamChat
              ? (player.role == PlayerRole.oni ? '鬼チャット' : '逃走者チャット')
              : '総合チャット';
          final headerEyebrow = isTeamChat ? 'TEAM CHANNEL' : 'GLOBAL CHANNEL';
          final chatState = ref.watch(
            chatMessagesByChannelProvider(
              (gameId: widget.gameId, channel: chatChannel),
            ),
          );
          final tutorialRect = _activeTutorialRect;

          return Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _dismissKeyboard,
                      child: Column(
                        children: [
                          SafeArea(
                            bottom: false,
                            child: KeyedSubtree(
                              key: _headerKey,
                              child: _ChatHeader(
                                title: headerTitle,
                                eyebrow: headerEyebrow,
                                palette: palette,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: chatState.when(
                                data: (messages) {
                                  final shouldForceInitialScroll =
                                      messages.isNotEmpty &&
                                          !_hasAutoScrolledToBottom;
                                  if (shouldForceInitialScroll) {
                                    _hasAutoScrolledToBottom = true;
                                  }
                                  if (messages.isNotEmpty) {
                                    _scheduleScrollToBottom(
                                      force: shouldForceInitialScroll,
                                    );
                                  }
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
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24),
                                    child: Text(
                                      'チャットを読み込めませんでした。\n$error',
                                      textAlign: TextAlign.center,
                                      style:
                                          const TextStyle(color: Colors.white70),
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
                  KeyedSubtree(
                    key: _composerKey,
                    child: _ChatComposer(
                      controller: _controller,
                      sending: _sending,
                      palette: palette,
                      focusNode: _composerFocusNode,
                      onSendRequested: () =>
                          _sendMessage(context, player, chatChannel),
                    ),
                  ),
                ],
              ),
              if (_isChatTutorialVisible)
                _ChatTutorialOverlay(
                  highlightRect: tutorialRect,
                  accentColor: palette.accentColor,
                  message: _currentTutorialMessage,
                  preferBelow:
                      _currentTutorialStep == _ChatTutorialStep.header,
                  isLastStep:
                      _currentTutorialStep == _ChatTutorialStep.header,
                  step: _currentTutorialStep == _ChatTutorialStep.header ? 2 : 1,
                  totalSteps: 2,
                  onNext: _advanceChatTutorial,
                  onSkip: _skipChatTutorial,
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

  void _handleScrollPositionChanged() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    const threshold = 120.0;
    final distanceToBottom = position.maxScrollExtent - position.pixels;
    _isUserNearBottom = distanceToBottom <= threshold;
  }

  void _scheduleScrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final shouldScroll = force || _isUserNearBottom;
      if (!shouldScroll) return;
      final position = _scrollController.position;
      _scrollController.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _handleChatTabActivated() async {
    if (!mounted ||
        _isChatTutorialVisible ||
        _hasCompletedChatTutorial ||
        _chatTutorialStartPending) {
      return;
    }
    _chatTutorialStartPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chatTutorialStartPending = false;
      if (!mounted ||
          _isChatTutorialVisible ||
          _hasCompletedChatTutorial) {
        return;
      }
      _startChatTutorial();
    });
  }

  void _startChatTutorial() {
    if (!mounted) return;
    _composerFocusNode.unfocus();
    setState(() {
      _isChatTutorialVisible = true;
      _currentTutorialStep = _ChatTutorialStep.input;
    });
    _scheduleTutorialTargetCapture();
  }

  void _scheduleTutorialTargetCapture() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isChatTutorialVisible) return;
      final root = context.findRenderObject();
      if (root is! RenderBox || !root.hasSize) return;

      Rect? composerRect;
      final composerContext = _composerKey.currentContext;
      if (composerContext != null) {
        final renderBox =
            composerContext.findRenderObject() as RenderBox?;
        if (renderBox != null && renderBox.hasSize) {
          final offset = renderBox.localToGlobal(Offset.zero);
          final localOffset = root.globalToLocal(offset);
          composerRect = localOffset & renderBox.size;
        }
      }

      Rect? headerRect;
      final headerContext = _headerKey.currentContext;
      if (headerContext != null) {
        final renderBox = headerContext.findRenderObject() as RenderBox?;
        if (renderBox != null && renderBox.hasSize) {
          final offset = renderBox.localToGlobal(Offset.zero);
          final localOffset = root.globalToLocal(offset);
          headerRect = localOffset & renderBox.size;
        }
      }

      if (!mounted) return;
      setState(() {
        _composerHighlightRect = composerRect;
        _headerHighlightRect = headerRect;
      });
    });
  }

  void _advanceChatTutorial() {
    if (_currentTutorialStep == _ChatTutorialStep.input) {
      _composerFocusNode.unfocus();
      setState(() {
        _currentTutorialStep = _ChatTutorialStep.header;
      });
      _scheduleTutorialTargetCapture();
      return;
    }
    unawaited(_completeChatTutorial());
  }

  void _skipChatTutorial() {
    unawaited(_completeChatTutorial());
  }

  Future<void> _completeChatTutorial() async {
    if (!mounted) return;
    setState(() {
      _isChatTutorialVisible = false;
      _currentTutorialStep = null;
    });
    _composerFocusNode.unfocus();
    _hasCompletedChatTutorial = true;
  }

  Rect? get _activeTutorialRect {
    switch (_currentTutorialStep) {
      case _ChatTutorialStep.input:
        return _composerHighlightRect;
      case _ChatTutorialStep.header:
        return _headerHighlightRect;
      default:
        return null;
    }
  }

  String get _currentTutorialMessage {
    switch (_currentTutorialStep) {
      case _ChatTutorialStep.input:
        return 'ここでメッセージを送り合い、仲間と相談できます。';
      case _ChatTutorialStep.header:
        return 'ゲームが始まると鬼と逃走者でチャットが分かれます。「総合チャット」の表示から切り替わりを確認しましょう。';
      default:
        return '';
    }
  }

  Future<void> _sendMessage(
    BuildContext context,
    Player player,
    ChatChannel channel,
  ) async {
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
        channel: channel,
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

enum _ChatTutorialStep { input, header }

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
    required this.eyebrow,
    required this.palette,
  });

  final String title;
  final String eyebrow;
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
            eyebrow,
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
    this.focusNode,
    required this.onSendRequested,
  });

  final TextEditingController controller;
  final bool sending;
  final _ChatPalette palette;
  final FocusNode? focusNode;
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
                        focusNode: focusNode,
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

  static const _ChatPalette _oniPalette = _ChatPalette(
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

  static const _ChatPalette _runnerPalette = _ChatPalette(
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

  static const _ChatPalette _generalPalette = _ChatPalette(
    headerGradient: [
      Color(0xFF0D47A1),
      Color(0xFF1976D2),
      Color(0xFF42A5F5),
    ],
    mineBubbleGradient: LinearGradient(
      colors: [
        Color(0xFF1E88E5),
        Color(0xFF64B5F6),
      ],
    ),
    buttonGradient: [
      Color(0xFF0D47A1),
      Color(0xFF42A5F5),
    ],
    accentColor: Color(0xFF42A5F5),
    bodyText: Color(0xFFE3F2FD),
    mutedText: Color(0xFF8EA6C1),
    otherBubbleColor: Color(0xFF03161B),
    shadowColor: Color(0x552264B8),
  );

  static _ChatPalette fromContext({
    required PlayerRole role,
    required ChatChannel channel,
  }) {
    switch (channel) {
      case ChatChannel.oni:
        return _oniPalette;
      case ChatChannel.runner:
        return _runnerPalette;
      case ChatChannel.general:
        return _generalPalette;
    }
  }
}

class _ChatTutorialOverlay extends StatelessWidget {
  const _ChatTutorialOverlay({
    required this.highlightRect,
    required this.accentColor,
    required this.message,
    required this.step,
    required this.totalSteps,
    required this.isLastStep,
    required this.preferBelow,
    required this.onNext,
    required this.onSkip,
  });

  final Rect? highlightRect;
  final Color accentColor;
  final String message;
  final int step;
  final int totalSteps;
  final bool isLastStep;
  final bool preferBelow;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final rectWithPadding = highlightRect?.inflate(12);
    final tooltipWidth = math.min(size.width - 32, 360.0);
    final centerX = rectWithPadding?.center.dx ?? size.width / 2;
    final double left = math.max(
      16,
      math.min(centerX - tooltipWidth / 2, size.width - tooltipWidth - 16),
    ).toDouble();
    final double baseTop = preferBelow
        ? (rectWithPadding?.bottom ?? size.height * 0.55) + 16
        : (rectWithPadding?.top ?? size.height * 0.45) - 160;
    final double top = math.max(24, math.min(baseTop, size.height - 200))
        .toDouble();

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              GestureDetector(
                onTap: () {},
                child: CustomPaint(
                  painter: _TutorialDimPainter(
                    highlightRect: rectWithPadding,
                    color: Colors.black.withOpacity(0.65),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              if (rectWithPadding != null)
                Positioned(
                  left: rectWithPadding.left,
                  top: rectWithPadding.top,
                  width: rectWithPadding.width,
                  height: rectWithPadding.height,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: accentColor, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withOpacity(0.35),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: left,
                top: top,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: tooltipWidth,
                  ),
                  child: _ChatTutorialTooltip(
                    message: message,
                    accentColor: accentColor,
                    step: step,
                    totalSteps: totalSteps,
                    isLastStep: isLastStep,
                    onNext: onNext,
                    onSkip: onSkip,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatTutorialTooltip extends StatelessWidget {
  const _ChatTutorialTooltip({
    required this.message,
    required this.accentColor,
    required this.step,
    required this.totalSteps,
    required this.isLastStep,
    required this.onNext,
    required this.onSkip,
  });

  final String message;
  final Color accentColor;
  final int step;
  final int totalSteps;
  final bool isLastStep;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      borderRadius: BorderRadius.circular(20),
      color: const Color(0xFF0A1418).withOpacity(0.92),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'STEP $step / $totalSteps',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accentColor,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  child: const Text('スキップ'),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.black,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(isLastStep ? '完了' : '次へ'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialDimPainter extends CustomPainter {
  const _TutorialDimPainter({
    required this.highlightRect,
    required this.color,
  });

  final Rect? highlightRect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final overlayPath =
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    if (highlightRect == null) {
      canvas.drawPath(overlayPath, paint);
      return;
    }
    final highlightPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          highlightRect!,
          const Radius.circular(28),
        ),
      );
    final dimPath =
        Path.combine(PathOperation.difference, overlayPath, highlightPath);
    canvas.drawPath(dimPath, paint);
  }

  @override
  bool shouldRepaint(covariant _TutorialDimPainter oldDelegate) {
    return oldDelegate.highlightRect != highlightRect ||
        oldDelegate.color != color;
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
            final gameStatus = gameState.value?.status;
            final roleEditingLocked = gameStatus == GameStatus.countdown ||
                gameStatus == GameStatus.running;
            final pinEditingLocked = roleEditingLocked;
            return ListView(
              children: [
                PlayerProfileCard(
                  player: player,
                  gameId: gameId,
                  onEditProfile: () {
                    FocusScope.of(context).unfocus();
                    context.push(PlayerProfileEditPage.path(gameId));
                  },
                ),
                const SizedBox(height: 16),
                PlayerListCard(
                  gameId: gameId,
                  canManage: canManage,
                  ownerUid: gameState.value?.ownerUid ?? '',
                  currentUid: user.uid,
                  roleEditingLocked: roleEditingLocked,
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
                        FocusScope.of(context).unfocus();
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
                      subtitle: Text(
                        roleEditingLocked
                            ? 'カウントダウン・進行中は役職を変更できません'
                            : '鬼/逃走者の人数と役割を整理・ランダム振り分け',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      enabled: !roleEditingLocked,
                      onTap: roleEditingLocked
                          ? null
                          : () {
                              FocusScope.of(context).unfocus();
                              context.pushNamed(
                                RoleAssignmentPage.routeName,
                                pathParameters: {'gameId': gameId},
                              );
                            },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.edit_location_alt_outlined),
                      title: const Text('発電所ピンを直接編集'),
                      subtitle: Text(
                        pinEditingLocked
                            ? 'カウントダウン・進行中は発電所ピンを編集できません'
                            : 'ドラッグ&ドロップで集合地点を微調整できます',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      enabled: !pinEditingLocked,
                      onTap: pinEditingLocked
                          ? null
                          : () {
                              FocusScope.of(context).unfocus();
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
                  gameStatus: gameState.value?.status,
                  pinCount: gameState.value?.pinCount,
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
    this.isLocked = false,
  });

  final String gameId;
  final int countdownSeconds;
  final bool isLocked;

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

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({
    required this.role,
    required this.status,
  });

  final PlayerRole role;
  final PlayerStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOni = role == PlayerRole.oni;
    final isCapturedRunner = !isOni && status != PlayerStatus.active;
    final label = isOni
        ? '鬼'
        : isCapturedRunner
            ? '逃走者（ダウン中）'
            : '逃走者';
    final baseColor = isOni ? Colors.redAccent : Colors.green;
    final color = isCapturedRunner
        ? Colors.grey.shade600.withOpacity(0.9)
        : baseColor.withOpacity(0.9);
    final icon = isOni ? Icons.whatshot : Icons.directions_run;
    final textColor = isCapturedRunner ? Colors.white70 : Colors.white;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(40),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: textColor),
            const SizedBox(width: 8),
            Text(
              '役職: $label',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
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
      child: SizedBox(
        width: double.infinity,
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
      ),
    );
  }
}

class _RescueActionButton extends StatelessWidget {
  const _RescueActionButton({
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
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.teal,
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
              : const Icon(Icons.volunteer_activism),
          label: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('救出する'),
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
      ),
    );
  }
}

class _ClearPinButton extends StatelessWidget {
  const _ClearPinButton({
    required this.distanceMeters,
    required this.isLoading,
    this.countdownSeconds,
    required this.onPressed,
  });

  final double? distanceMeters;
  final bool isLoading;
  final int? countdownSeconds;
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
            color: Colors.black.withOpacity(0.2),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.amber.shade700,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            foregroundColor: Colors.white,
            textStyle: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          onPressed: countdownSeconds != null || isLoading ? null : onPressed,
          icon: countdownSeconds != null
              ? const Icon(Icons.timer)
              : isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.electric_bolt),
          label: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                distanceLabel == null ? '発電所' : '発電所（約${distanceLabel}m）',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RescueAlert extends StatelessWidget {
  const _RescueAlert({
    required this.message,
    required this.onDismissed,
  });

  final String message;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: ConstrainedBox(
        key: const ValueKey('rescue-alert'),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Material(
          borderRadius: BorderRadius.circular(24),
          elevation: 16,
          color: const Color(0xFF0F1A16).withOpacity(0.95),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF4CAF50),
                        Color(0xFF2E7D32),
                      ],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.volunteer_activism,
                    size: 36,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '救出が完了しました',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.tealAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onDismissed,
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptureAlert extends StatelessWidget {
  const _CaptureAlert({
    required this.message,
    required this.onDismissed,
  });

  final String message;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: ConstrainedBox(
        key: const ValueKey('capture-alert'),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Material(
          borderRadius: BorderRadius.circular(24),
          elevation: 16,
          color: const Color(0xFF190C0C).withOpacity(0.95),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFFF5252),
                        Color(0xFFD50000),
                      ],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.security,
                    size: 36,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '捕獲が発生しました',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.deepOrangeAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onDismissed,
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GeneratorClearedAlert extends StatelessWidget {
  const _GeneratorClearedAlert({
    required this.playerRole,
    required this.onDismissed,
  });

  final PlayerRole playerRole;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOni = playerRole == PlayerRole.oni;
    final description = isOni
        ? '逃走者が発電所を停止させました。地図を確認して即座に対応してください。'
        : '仲間の逃走者が発電所を停止させました。マップで状況を確認して次の発電所へ向かいましょう。';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: ConstrainedBox(
        key: const ValueKey('generator-cleared-alert'),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Material(
          borderRadius: BorderRadius.circular(24),
          elevation: 16,
          color: const Color(0xFF0F1115).withOpacity(0.95),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFFFC857),
                        Color(0xFFFF9500),
                      ],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.electric_bolt,
                    size: 36,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '発電所が解除されました',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onDismissed,
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GeneratorClearingCountdownAlert extends StatelessWidget {
  const _GeneratorClearingCountdownAlert({
    required this.remainingSeconds,
  });

  final int remainingSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clampedSeconds = remainingSeconds.clamp(0, 999).toInt();
    final formattedDuration = _formatRemainingLabel(clampedSeconds);
    return Material(
      borderRadius: BorderRadius.circular(24),
      elevation: 16,
      color: const Color(0xFF0F1115).withOpacity(0.95),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFFFC857),
                    Color(0xFFFF9500),
                  ],
                ),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.electric_bolt,
                size: 36,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '発電所を解除中…',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '解除完了まで残り$formattedDuration',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
                strokeWidth: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatRemainingLabel(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes <= 0) {
      return '${secs}秒';
    }
    final paddedSecs = secs.toString().padLeft(2, '0');
    return '${minutes}分${paddedSecs}秒';
  }
}

class _OniClearingAlert extends StatelessWidget {
  const _OniClearingAlert();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      borderRadius: BorderRadius.circular(24),
      elevation: 16,
      color: const Color(0xFF0F1115).withOpacity(0.95),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFFFC857),
                    Color(0xFFFF9500),
                  ],
                ),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.warning_amber_rounded,
                size: 36,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '逃走者が発電所を解除中です',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'マップを確認して最寄りの発電所へ急行してください。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NearbyPinInfo {
  const _NearbyPinInfo({
    required this.pin,
    required this.distanceMeters,
  });

  final PinPoint pin;
  final double distanceMeters;
}

class _CaptureTargetInfo {
  const _CaptureTargetInfo({
    required this.runner,
    required this.distanceMeters,
  });

  final Player runner;
  final double distanceMeters;
}

class _RescueTargetInfo {
  const _RescueTargetInfo({
    required this.runner,
    required this.distanceMeters,
  });

  final Player runner;
  final double distanceMeters;
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
      child: SizedBox(
        width: double.infinity,
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
          onPressed: (_isStarting || widget.isLocked) ? null : _handlePressed,
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
    this.pinCount,
  });

  final String gameId;
  final String ownerUid;
  final String currentUid;
  final GameStatus? gameStatus;
  final int? pinCount;

  @override
  ConsumerState<_ActionButtons> createState() => _ActionButtonsState();
}

class _ActionButtonsState extends ConsumerState<_ActionButtons> {
  bool _isLeaving = false;
  bool _isClaimingOwner = false;
  bool _isEndingGame = false;

  bool get _isOwner => widget.ownerUid == widget.currentUid;
  bool get _showEndGameButton {
    final status = widget.gameStatus;
    if (!_isOwner || status == null) return false;
    return status == GameStatus.countdown || status == GameStatus.running;
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
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
                    _dismissKeyboard();
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
                    _dismissKeyboard();
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
                      await controller.endGame(
                        gameId: widget.gameId,
                        pinCount: widget.pinCount,
                        result: GameEndResult.draw,
                      );
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
                  _dismissKeyboard();
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

class GameTutorialDialog extends StatefulWidget {
  const GameTutorialDialog({super.key});

  @override
  State<GameTutorialDialog> createState() => _GameTutorialDialogState();
}

class _GameTutorialDialogState extends State<GameTutorialDialog> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _handleBack() {
    if (_currentPage == 0) {
      return;
    }
    _pageController.previousPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _handleNext() {
    final isLastPage = _currentPage == _tutorialSlides.length - 1;
    if (isLastPage) {
      Navigator.of(context).pop(true);
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return WillPopScope(
      onWillPop: () async => false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ゲームチュートリアル',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '初めての方は一度目を通してください',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 360,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _tutorialSlides.length,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      final slide = _tutorialSlides[index];
                      return _TutorialSlide(slide: slide);
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _tutorialSlides.length,
                    (index) {
                      final isActive = index == _currentPage;
                      final color = isActive
                          ? theme.colorScheme.primary
                          : theme.dividerColor;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        height: 8,
                        width: isActive ? 24 : 8,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    TextButton(
                      onPressed: _currentPage == 0 ? null : _handleBack,
                      child: const Text('戻る'),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: _handleNext,
                      child: Text(
                        _currentPage == _tutorialSlides.length - 1
                            ? 'プレイ開始'
                            : '次へ',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TutorialSlide extends StatelessWidget {
  const _TutorialSlide({required this.slide});

  final _GameTutorialSlideData slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.dividerColor.withOpacity(0.7);
    final fillColor = theme.colorScheme.surfaceVariant.withOpacity(
      theme.brightness == Brightness.dark ? 0.35 : 0.65,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          slide.title,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              color: fillColor,
              border: Border.all(color: borderColor),
            ),
            child: slide.showWarningIcon
                ? Center(
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: theme.colorScheme.error,
                      size: 96,
                    ),
                  )
                : Image.asset(
                    slide.assetPath,
                    fit: BoxFit.cover,
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            child: Text(
              slide.description,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    );
  }
}

class _GameTutorialSlideData {
  const _GameTutorialSlideData({
    required this.title,
    required this.description,
    required this.assetPath,
    this.showWarningIcon = false,
  });

  final String title;
  final String description;
  final String assetPath;
  final bool showWarningIcon;
}

const List<_GameTutorialSlideData> _tutorialSlides = [
  _GameTutorialSlideData(
    title: 'YamaGoへようこそ',
    description:
        'YamaGoは山手線エリアを舞台に、鬼と逃走者に分かれて街全体で遊ぶリアル鬼ごっこです。'
        '移動しながら仲間と連携し、現実の地形を活かして勝利をつかみましょう。',
    assetPath: 'assets/tutorial/page1.png',
  ),
  _GameTutorialSlideData(
    title: '鬼のミッション',
    description:
        '鬼役はすべての逃走者を捕獲できれば勝ちです。捕獲範囲内に逃走者がいると捕まえられるので、'
        'マップで位置を確認しつつ連絡を取り合い、退路をふさぎながら少しずつ包囲していきましょう。',
    assetPath: 'assets/tutorial/page2.png',
  ),
  _GameTutorialSlideData(
    title: '逃走者と発電機',
    description:
        '逃走者はマップ上の発電機をすべて解除すると勝利します。捕獲範囲内に発電機があると解除開始が可能で、'
        '解除中は同じ場所に一定時間とどまる必要があり、解除開始と同時に鬼へ通知されるため仲間の警戒が重要です。',
    assetPath: 'assets/tutorial/page3.png',
  ),
  _GameTutorialSlideData(
    title: 'ゲームを始めるには',
    description:
        'オーナーがゲームスタートボタンを押すとゲームが始まります。オーナーがいない場合は、'
        '設定タブの「自分をオーナーにする」ボタンを押して自分をオーナーに任命してください。',
    assetPath: 'assets/tutorial/page4.png',
  ),
  _GameTutorialSlideData(
    title: 'カウントダウンと設定',
    description:
        'スタート後は鬼が動けるようになるまでカウントダウンが走り、その間に逃走者は素早く散開しましょう。'
        '設定画面ではルールやタイマーなどの各種設定を調整できます。',
    assetPath: 'assets/tutorial/page5.png',
  ),
  _GameTutorialSlideData(
    title: 'ゲーム終了後の注意',
    description:
        'ゲームが終わったら必ず設定画面のログアウトボタンからログアウトしてください。'
        'ログアウトしないままだと位置情報の共有が継続してしまうため注意が必要です。',
    assetPath: '',
    showWarningIcon: true,
  ),
];
