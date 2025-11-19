import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:yamago_flutter/core/location/yamanote_constants.dart';
import 'package:yamago_flutter/features/game/application/player_providers.dart';
import 'package:yamago_flutter/features/pins/application/pin_providers.dart';
import 'package:yamago_flutter/features/pins/data/pin_repository.dart';
import 'package:yamago_flutter/features/pins/domain/pin_point.dart';

class PinEditorPage extends ConsumerStatefulWidget {
  const PinEditorPage({
    super.key,
    required this.gameId,
  });

  static const routeName = 'pin-editor';
  static const routePath = '/game/:gameId/pins/edit';

  static String path(String gameId) => '/game/$gameId/pins/edit';

  final String gameId;

  @override
  ConsumerState<PinEditorPage> createState() => _PinEditorPageState();
}

class _PinEditorPageState extends ConsumerState<PinEditorPage> {
  GoogleMapController? _mapController;
  LatLng _cameraTarget = yamanoteCenter;
  bool _hasCenteredOnce = false;
  bool _isSaving = false;
  String? _activePinId;
  String? _errorMessage;

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pinsState = ref.watch(pinsStreamProvider(widget.gameId));
    final gameState = ref.watch(gameStreamProvider(widget.gameId));

    final rawPinCountLimit = gameState.maybeWhen(
      data: (game) => game?.pinCount,
      orElse: () => null,
    );

    final pinCountLimit = rawPinCountLimit == null
        ? null
        : rawPinCountLimit.clamp(0, 9999).toInt();

    final pins = pinsState.value ?? const <PinPoint>[];
    pinsState.whenData(_maybeCenterOnPins);
    final displayPins = _resolvedPins(pins, pinCountLimit);

    final hiddenPinCount = pinCountLimit == null
        ? 0
        : (pins.length > pinCountLimit ? pins.length - pinCountLimit : 0);
    final missingPinCount = pinCountLimit == null
        ? 0
        : (pinCountLimit > pins.length ? pinCountLimit - pins.length : 0);
    final pinLimitResolved = pinCountLimit != null;
    final configuredPinCount = pinCountLimit ?? pins.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('発電所のピンを編集'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _cameraTarget,
                    zoom: 12.5,
                  ),
                  markers: _buildMarkers(displayPins),
                  onMapCreated: (controller) {
                    _mapController ??= controller;
                  },
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  myLocationButtonEnabled: false,
                  onCameraMove: (position) {
                    _cameraTarget = position.target;
                  },
                  minMaxZoomPreference: const MinMaxZoomPreference(10, 18),
                ),
                if (pinsState.isLoading)
                  const Center(child: CircularProgressIndicator()),
                if (pinsState.hasError)
                  _MessageOverlay(
                    message:
                        'ピン情報の取得に失敗しました。\n${pinsState.error}',
                    actionLabel: '再読み込み',
                    onAction: () {
                      ref.invalidate(pinsStreamProvider(widget.gameId));
                    },
                  ),
                if (pinLimitResolved && configuredPinCount == 0)
                  const _MessageOverlay(
                    message: 'ゲーム設定で発電所数が 0 に設定されています。\nまずは発電所数を 1 以上にしてください。',
                  ),
                if (pinLimitResolved &&
                    configuredPinCount > 0 &&
                    displayPins.isEmpty &&
                    !pinsState.isLoading)
                  const _MessageOverlay(
                    message: '発電所のピンがまだ生成されていません。\nゲーム設定で再配置を実行してください。',
                  ),
              ],
            ),
          ),
          _PinEditorInfoPanel(
            displayCount: displayPins.length,
            configuredCount: pinLimitResolved ? configuredPinCount : null,
            hiddenPinCount: hiddenPinCount,
            missingPinCount: missingPinCount,
            activePinId: _activePinId,
            isSaving: _isSaving,
            errorMessage: _errorMessage,
          ),
        ],
      ),
    );
  }

  void _maybeCenterOnPins(List<PinPoint> pins) {
    if (_hasCenteredOnce || pins.isEmpty) return;
    _hasCenteredOnce = true;
    final firstPin = pins.first;
    final target = LatLng(firstPin.lat, firstPin.lng);
    unawaited(
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(target, 14),
      ),
    );
  }

  List<PinPoint> _resolvedPins(List<PinPoint> pins, int? limit) {
    if (limit == null) return pins;
    final sanitizedLimit = math.max(0, limit);
    if (pins.length <= sanitizedLimit) return pins;
    return pins.take(sanitizedLimit).toList(growable: false);
  }

  Set<Marker> _buildMarkers(List<PinPoint> pins) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('center'),
        position: yamanoteCenter,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: '山手線中心'),
      ),
    };

    for (final pin in pins) {
      final position = LatLng(pin.lat, pin.lng);
      final hue = switch (pin.status) {
        PinStatus.pending => BitmapDescriptor.hueYellow,
        PinStatus.clearing => BitmapDescriptor.hueOrange,
        PinStatus.cleared => BitmapDescriptor.hueGreen,
      };
      markers.add(
        Marker(
          markerId: MarkerId(pin.id),
          position: position,
          draggable: true,
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          infoWindow: InfoWindow(title: '発電所ピン', snippet: pin.id),
          onDragStart: (_) => _handleDragStart(pin.id),
          onDragEnd: (nextPosition) =>
              _handleDragEnd(pin.id, nextPosition.latitude, nextPosition.longitude),
        ),
      );
    }
    return markers;
  }

  void _handleDragStart(String pinId) {
    setState(() {
      _activePinId = pinId;
      _errorMessage = null;
    });
  }

  Future<void> _handleDragEnd(
    String pinId,
    double lat,
    double lng,
  ) async {
    setState(() {
      _activePinId = pinId;
      _isSaving = true;
    });
    final repo = ref.read(pinRepositoryProvider);
    try {
      await repo.updatePinPosition(
        gameId: widget.gameId,
        pinId: pinId,
        lat: lat,
        lng: lng,
      );
      if (mounted) {
        setState(() {
          _errorMessage = null;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '位置を保存できませんでした。もう一度お試しください。';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ピンの保存に失敗しました: $error')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _activePinId = null;
      });
    }
  }
}

class _MessageOverlay extends StatelessWidget {
  const _MessageOverlay({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Card(
        color: theme.colorScheme.surface.withOpacity(0.92),
        margin: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PinEditorInfoPanel extends StatelessWidget {
  const _PinEditorInfoPanel({
    required this.displayCount,
    required this.configuredCount,
    required this.hiddenPinCount,
    required this.missingPinCount,
    required this.activePinId,
    required this.isSaving,
    required this.errorMessage,
  });

  final int displayCount;
  final int? configuredCount;
  final int hiddenPinCount;
  final int missingPinCount;
  final String? activePinId;
  final bool isSaving;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(0.95),
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '表示中のピン',
                  style: theme.textTheme.labelLarge,
                ),
                Text(
                  configuredCount == null
                      ? '$displayCount 箇所'
                      : '$displayCount / $configuredCount 箇所',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'ピンはドラッグ＆ドロップで移動できます。変更は自動保存されます。',
              style: theme.textTheme.bodySmall,
            ),
            if (hiddenPinCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '設定数を超える $hiddenPinCount 件は非表示にしています。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            if (missingPinCount > 0 && hiddenPinCount == 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '設定数より $missingPinCount 件不足しています。ゲーム設定で再配置してください。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ),
            if (activePinId != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: isSaving
                          ? const CircularProgressIndicator(strokeWidth: 2)
                          : const Icon(Icons.touch_app, size: 16),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isSaving
                            ? '位置を保存しています...'
                            : 'ピンを移動中です...',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  errorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
