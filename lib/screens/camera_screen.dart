import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';

import '../app_state.dart';
import '../services/photo_stamper.dart';
import '../theme.dart';
import '../widgets/info_card.dart';
import 'location_picker_screen.dart';
import 'preview_screen.dart';
import 'settings_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, required this.state});

  final AppState state;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  static const _glass = Color(0x24FFFFFF);

  final _previewKey = GlobalKey();
  final _cardKey = GlobalKey();

  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  FlashMode _flash = FlashMode.off;
  bool _starting = false, _busy = false, _away = false;
  bool _flashOverlay = false, _pressed = false;
  double _flipTurns = 0;
  String? _cameraError, _lastPhoto;

  double _minZoom = 1, _maxZoom = 1, _zoom = 1, _baseZoom = 1;
  Offset? _focusPoint;
  Timer? _focusTimer;

  AppState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCamera();
    _state.startLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusTimer?.cancel();
    _controller?.dispose();
    _state.stopLocation();
    super.dispose();
  }

  // Release camera + GPS in background to save battery.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) {
      _releaseCamera();
      _state.stopLocation();
    } else if (s == AppLifecycleState.resumed) {
      if (!_away) _startCamera();
      _state.startLocation();
    }
  }

  // ------------------------------------------------------------ camera

  static Future<void> _quiet(Future<void> f) async {
    try {
      await f;
    } catch (_) {}
  }

  Future<void> _startCamera() async {
    if (_starting || _controller != null) return;
    _starting = true;
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
        final back = _cameras
            .indexWhere((c) => c.lensDirection == CameraLensDirection.back);
        _cameraIndex = back < 0 ? 0 : back;
      }
      if (_cameras.isEmpty) {
        _setError('No camera found on this device');
        return;
      }
      final c = CameraController(
        _cameras[_cameraIndex],
        // Standard = 1080p (fast). High = full sensor 4:3.
        _state.highQuality ? ResolutionPreset.max : ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await c.initialize();
      await _quiet(c.setFlashMode(_flash));
      try {
        _minZoom = await c.getMinZoomLevel();
        _maxZoom = math.min(await c.getMaxZoomLevel(), 10);
      } catch (_) {
        _minZoom = _maxZoom = 1;
      }
      _zoom = _minZoom;
      final backgrounded =
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused;
      if (!mounted || _away || backgrounded) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _cameraError = null;
      });
    } on CameraException catch (e) {
      _setError(e.code.contains('AccessDenied')
          ? 'Camera permission is required.\nAllow it in Settings › Apps › GPS Camera.'
          : 'Camera unavailable (${e.code})');
    } finally {
      _starting = false;
    }
  }

  Future<void> _releaseCamera() async {
    final c = _controller;
    if (c == null) return;
    if (mounted) setState(() => _controller = null);
    await c.dispose();
  }

  void _setError(String m) {
    if (mounted) setState(() => _cameraError = m);
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _busy || _starting) return;
    setState(() => _flipTurns += 0.5);
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _releaseCamera();
    await _startCamera();
  }

  Future<void> _cycleFlash() async {
    const order = [FlashMode.off, FlashMode.auto, FlashMode.always];
    final next = order[(order.indexOf(_flash) + 1) % order.length];
    setState(() => _flash = next);
    final c = _controller;
    if (c != null) await _quiet(c.setFlashMode(next));
  }

  IconData get _flashIcon => switch (_flash) {
        FlashMode.auto => Icons.flash_auto_rounded,
        FlashMode.always => Icons.flash_on_rounded,
        _ => Icons.flash_off_rounded,
      };

  void _setZoom(double z) {
    final c = _controller;
    z = z.clamp(_minZoom, _maxZoom);
    if (c == null || (z - _zoom).abs() < 0.01) return;
    setState(() => _zoom = z);
    _quiet(c.setZoomLevel(z));
  }

  void _toggleZoom() => _setZoom(_zoom < 1.95 ? math.min(2, _maxZoom) : _minZoom);

  void _focusAt(Offset p) {
    final c = _controller;
    final box = _previewKey.currentContext?.findRenderObject() as RenderBox?;
    if (c == null || box == null) return;
    final pt = Offset((p.dx / box.size.width).clamp(0.0, 1.0),
        (p.dy / box.size.height).clamp(0.0, 1.0));
    _quiet(c.setFocusPoint(pt));
    _quiet(c.setExposurePoint(pt));
    setState(() => _focusPoint = p);
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _focusPoint = null);
    });
  }

  Future<void> _capture() async {
    final c = _controller;
    final place = _state.place;
    if (c == null || !c.value.isInitialized || _busy) return;
    if (place == null) {
      _toast('Waiting for location…');
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = true;
      _flashOverlay = true;
    });
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _flashOverlay = false);
    });
    try {
      final shot = await c.takePicture();
      final card =
          _cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final path = await PhotoStamper.stamp(
        photoPath: shot.path,
        card: card,
        place: place,
        time: DateTime.now(),
      );
      if (!await Gal.hasAccess(toAlbum: true)) {
        await Gal.requestAccess(toAlbum: true);
      }
      await Gal.putImage(path, album: 'GPS Camera');

      final old = _lastPhoto;
      if (old != null) File(old).delete().ignore(); // keep cache small
      if (!mounted) return;
      setState(() => _lastPhoto = path);
      _toast('Saved to Gallery › GPS Camera');
    } catch (e) {
      _toast('Could not save photo. Please try again.');
      debugPrint('capture failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------- navigation

  /// Pushes a page with the camera released (no hidden preview draining battery).
  Future<void> _open(Widget page) async {
    _away = true;
    await _releaseCamera();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    _away = false;
    if (mounted) _startCamera();
  }

  void _openPicker() => _open(LocationPickerScreen(state: _state));

  void _selectMode(LocationMode m) {
    if (m == LocationMode.custom &&
        (_state.custom == null || _state.isCustom)) {
      _openPicker();
      return;
    }
    HapticFeedback.selectionClick();
    _state.setMode(m);
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(m),
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 150),
      ));
  }

  // --------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.black,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Colors.black,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(child: LayoutBuilder(builder: _layout)),
        ),
      );

  static const _topH = 56.0, _bottomH = 172.0;

  /// Adapts to every screen: the preview always spans the full width at the
  /// camera's true aspect ratio. On tall phones it sits between the bars;
  /// on short/wide screens the bars float over it and the stamp is lifted
  /// above the controls so it is never hidden.
  Widget _layout(BuildContext context, BoxConstraints box) {
    final w = box.maxWidth, h = box.maxHeight;
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    // value.aspectRatio is landscape (w/h > 1); in portrait height = w * ar.
    final ar = ready ? c.value.aspectRatio : (_state.highQuality ? 4 / 3 : 16 / 9);
    final previewH = w * ar;
    final free = h - _topH - _bottomH - previewH;
    final fits = free >= 0;
    final previewTop =
        fits ? _topH + free / 2 : math.max(0.0, math.min(_topH, h - previewH));
    final visibleBottom = math.min(previewTop + previewH, h - _bottomH);
    final side = w * StampLayout.side;

    return Stack(children: [
      Positioned(
        left: 0,
        top: previewTop,
        width: w,
        height: previewH,
        child: _preview(c, ready),
      ),
      if (ready)
        Positioned(
          left: side,
          right: side,
          bottom: h - visibleBottom + w * StampLayout.bottom,
          child: GestureDetector(
            onTap: _openPicker,
            child:
                RepaintBoundary(key: _cardKey, child: InfoCard(state: _state)),
          ),
        ),
      if (ready && _maxZoom > 1.05)
        Positioned(
          top: math.max(previewTop, _topH) + 10,
          left: 0,
          right: 0,
          child: Center(child: _zoomPill()),
        ),
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        height: _topH,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: previewTop < _topH
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xAA000000), Color(0x00000000)])
                : null,
          ),
          child: _topBar(),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: _bottomH,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: fits
                ? null
                : const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC000000)]),
          ),
          child: _bottomBar(),
        ),
      ),
    ]);
  }

  Widget _topBar() => SizedBox(
        height: _topH,
        child: Row(children: [
          const SizedBox(width: 6),
          _circleIcon(_flashIcon, _cycleFlash, 'Flash', size: 44),
          Expanded(
            child: Center(
              child: ListenableBuilder(
                  listenable: _state,
                  builder: (context, child) => _statusChip()),
            ),
          ),
          _circleIcon(Icons.tune_rounded,
              () => _open(SettingsScreen(state: _state)), 'Stamp settings',
              size: 44),
          const SizedBox(width: 6),
        ]),
      );

  Widget _statusChip() {
    final s = _state;
    final Widget lead;
    final String text;
    if (s.isCustom) {
      lead = const Icon(Icons.push_pin_rounded,
          size: 14, color: AppColors.primary);
      text = s.custom?.title ?? 'Custom location';
    } else if (s.live == null) {
      lead = const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
              strokeWidth: 1.6, color: AppColors.primary));
      text = s.locationError ?? 'Searching GPS…';
    } else {
      lead = Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
              color: Color(0xFF34D399), shape: BoxShape.circle));
      final acc = s.accuracy;
      text = acc == null ? 'GPS active' : 'GPS  ±${acc.round()} m';
    }
    return GestureDetector(
      onTap: _openPicker,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
            color: _glass, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          lead,
          const SizedBox(width: 7),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  Widget _preview(CameraController? c, bool ready) {
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography_outlined,
                color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            Text(_cameraError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.4)),
          ]),
        ),
      );
    }
    if (!ready) {
      return const Center(
        child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: AppColors.primary)),
      );
    }
    final focus = _focusPoint;
    return Stack(key: _previewKey, fit: StackFit.expand, children: [
      GestureDetector(
        onScaleStart: (_) => _baseZoom = _zoom,
        onScaleUpdate: (d) {
          if (d.pointerCount >= 2) _setZoom(_baseZoom * d.scale);
        },
        onTapUp: (d) => _focusAt(d.localPosition),
        child: CameraPreview(c!),
      ),
      if (focus != null)
        Positioned(
          left: focus.dx - 34,
          top: focus.dy - 34,
          child: IgnorePointer(
            child: TweenAnimationBuilder<double>(
              key: ValueKey(focus),
              tween: Tween(begin: 1.35, end: 1),
              duration: const Duration(milliseconds: 220),
              builder: (context, v, child) =>
                  Transform.scale(scale: v, child: child),
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.6),
                ),
              ),
            ),
          ),
        ),
      IgnorePointer(
        child: AnimatedOpacity(
          opacity: _flashOverlay ? 0.75 : 0,
          duration: const Duration(milliseconds: 90),
          child: const ColoredBox(color: Colors.white),
        ),
      ),
    ]);
  }

  Widget _zoomPill() => GestureDetector(
        onTap: _toggleZoom,
        child: Container(
          width: 44,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: const Color(0x66000000),
              borderRadius: BorderRadius.circular(15)),
          child: Text(
            '${_zoom.toStringAsFixed(_zoom < 10 ? 1 : 0)}×',
            style: TextStyle(
                color: _zoom > _minZoom + 0.05
                    ? const Color(0xFFFFD54F)
                    : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700),
          ),
        ),
      );

  Widget _bottomBar() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
          ListenableBuilder(
              listenable: _state, builder: (context, child) => _modeSwitch()),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _thumbnail(),
              _shutter(),
              AnimatedRotation(
                turns: _flipTurns,
                duration: const Duration(milliseconds: 300),
                child: _circleIcon(Icons.flip_camera_android_rounded,
                    _switchCamera, 'Switch camera'),
              ),
            ],
          ),
        ]),
      );

  Widget _modeSwitch() {
    Widget seg(String label, IconData icon, LocationMode m) {
      final on = _state.mode == m;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectMode(m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: on ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: on ? Colors.white : Colors.white60),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: on ? Colors.white : Colors.white60,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: _glass, borderRadius: BorderRadius.circular(21)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('Live GPS', Icons.my_location_rounded, LocationMode.live),
        seg('Custom', Icons.edit_location_alt_rounded, LocationMode.custom),
      ]),
    );
  }

  Widget _thumbnail() {
    final p = _lastPhoto;
    return GestureDetector(
      onTap: p == null ? null : () => _open(PreviewScreen(path: p)),
      child: Container(
        width: 52,
        height: 52,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _glass,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white70, width: 1.5),
        ),
        child: p == null
            ? const Icon(Icons.photo_library_outlined, color: Colors.white70)
            : Image.file(File(p), fit: BoxFit.cover, cacheWidth: 160),
      ),
    );
  }

  Widget _shutter() => Semantics(
        button: true,
        label: 'Take photo',
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) {
            setState(() => _pressed = false);
            _capture();
          },
          child: AnimatedScale(
            scale: _pressed ? 0.9 : 1,
            duration: const Duration(milliseconds: 90),
            child: Container(
              width: 76,
              height: 76,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Colors.white),
                child: _busy
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(
                            color: AppColors.primary, strokeWidth: 2.5))
                    : null,
              ),
            ),
          ),
        ),
      );

  Widget _circleIcon(IconData icon, VoidCallback onTap, String tip,
          {double size = 52}) =>
      Tooltip(
        message: tip,
        child: Material(
          color: _glass,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
                width: size,
                height: size,
                child: Icon(icon, color: Colors.white, size: size * 0.46)),
          ),
        ),
      );
}
