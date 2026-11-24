import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';

import '../app_state.dart';
import '../theme.dart';

/// Pick a custom location: drag the map under a fixed pin, search a place,
/// type coordinates, or reuse a recent place. Name/address are editable.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, required this.state});

  final AppState state;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _map = MapController();
  final _search = TextEditingController();
  final _title = TextEditingController();
  final _address = TextEditingController();
  late final ValueNotifier<LatLng> _center;
  late final double _initialZoom;
  Timer? _debounce;
  int _req = 0;
  bool _resolving = false, _searching = false;
  String _country = '';

  @override
  void initState() {
    super.initState();
    final s = widget.state;
    final start = s.custom ?? s.live;
    _center = ValueNotifier(start == null
        ? const LatLng(20.5937, 78.9629) // India
        : LatLng(start.lat, start.lng));
    _initialZoom = start == null ? 4.5 : 16;
    if (start != null) {
      _title.text = start.title;
      _address.text = start.address;
      _country = start.country;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _map.dispose();
    _search.dispose();
    _title.dispose();
    _address.dispose();
    _center.dispose();
    super.dispose();
  }

  void _onMove(MapCamera camera, bool hasGesture) {
    _center.value = camera.center;
    if (hasGesture) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), _resolve);
    }
  }

  /// Reverse-geocode the pin; stale responses are dropped via [_req].
  Future<void> _resolve() async {
    final id = ++_req;
    final c = _center.value;
    setState(() => _resolving = true);
    try {
      final info = await AppState.describe(c.latitude, c.longitude);
      if (!mounted || id != _req) return;
      _title.text = info.title;
      _address.text = info.address;
      _country = info.country;
    } catch (_) {
      if (!mounted || id != _req) return;
      _address.clear(); // offline: user can type it
    } finally {
      if (mounted && id == _req) setState(() => _resolving = false);
    }
  }

  void _goTo(LatLng p, {double zoom = 16}) {
    _map.move(p, zoom);
    _center.value = p;
    _resolve();
  }

  Future<void> _doSearch(String q) async {
    q = q.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    try {
      final r = await locationFromAddress(q);
      if (!mounted) return;
      if (r.isEmpty) throw StateError('empty');
      _goTo(LatLng(r.first.latitude, r.first.longitude));
    } catch (_) {
      _toast('No place found for “$q”');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _useCurrent() {
    final l = widget.state.live;
    if (l == null) {
      _toast('Current location not available yet');
      return;
    }
    _apply(l, zoom: 17);
    if (l.title.isEmpty) _resolve();
  }

  void _apply(Place p, {double zoom = 16}) {
    ++_req; // cancel pending lookups
    final c = LatLng(p.lat, p.lng);
    _map.move(c, zoom);
    _center.value = c;
    _title.text = p.title;
    _address.text = p.address;
    _country = p.country;
    setState(() => _resolving = false);
  }

  Future<void> _enterCoordinates() async {
    final c = _center.value;
    final lat = TextEditingController(text: c.latitude.toStringAsFixed(6));
    final lng = TextEditingController(text: c.longitude.toStringAsFixed(6));
    const kb = TextInputType.numberWithOptions(decimal: true, signed: true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Enter coordinates',
            style: TextStyle(
                color: AppColors.navy,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: lat,
              keyboardType: kb,
              decoration:
                  const InputDecoration(labelText: 'Latitude (-90 to 90)')),
          const SizedBox(height: 12),
          TextField(
              controller: lng,
              keyboardType: kb,
              decoration:
                  const InputDecoration(labelText: 'Longitude (-180 to 180)')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Go')),
        ],
      ),
    );
    if (ok != true) return;
    final la = double.tryParse(lat.text.trim());
    final lo = double.tryParse(lng.text.trim());
    if (la == null || lo == null || la.abs() > 90 || lo.abs() > 180) {
      _toast('Enter a valid latitude and longitude');
      return;
    }
    _goTo(LatLng(la, lo));
  }

  void _confirm() {
    final c = _center.value;
    final title = _title.text.trim();
    widget.state.setCustom(Place(
      lat: c.latitude,
      lng: c.longitude,
      title: title.isEmpty ? 'Custom location' : title,
      address: _address.text.trim(),
      country: _country,
    ));
    Navigator.pop(context);
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Set custom location'),
          actions: [
            IconButton(
                tooltip: 'Enter coordinates',
                onPressed: _enterCoordinates,
                icon: const Icon(Icons.numbers)),
          ],
        ),
        body: Column(children: [
          Expanded(child: _mapArea()),
          _panel(),
        ]),
      );

  Widget _mapArea() {
    const none = OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide.none);
    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: _center.value,
          initialZoom: _initialZoom,
          minZoom: 3,
          maxZoom: 19,
          onPositionChanged: _onMove,
          interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.sphurthy.gps_camera',
            maxZoom: 19,
          ),
          const SimpleAttributionWidget(
              source: Text('OpenStreetMap contributors')),
        ],
      ),
      // Fixed centre pin: its tip marks the selected point.
      IgnorePointer(
        child: Center(
          child: Transform.translate(
            offset: const Offset(0, -20),
            child: const Icon(Icons.location_on,
                size: 44, color: AppColors.navy),
          ),
        ),
      ),
      Positioned(
        top: 12,
        left: 12,
        right: 12,
        child: Material(
          elevation: 3,
          color: Colors.white,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(8),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: _doSearch,
            decoration: InputDecoration(
              hintText: 'Search area, street, landmark…',
              prefixIcon: const Icon(Icons.search, color: AppColors.primary),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(
                      icon: const Icon(Icons.arrow_forward,
                          color: AppColors.primary),
                      onPressed: () => _doSearch(_search.text)),
              border: none,
              enabledBorder: none,
              focusedBorder: none,
            ),
          ),
        ),
      ),
      Positioned(
        right: 12,
        bottom: 28,
        child: FloatingActionButton.small(
          heroTag: 'my-location',
          tooltip: 'Use current location',
          backgroundColor: Colors.white,
          foregroundColor: AppColors.primary,
          onPressed: _useCurrent,
          child: const Icon(Icons.my_location),
        ),
      ),
    ]);
  }

  Widget _panel() {
    final recents = widget.state.recents;
    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
      child: Material(
        color: Colors.white,
        elevation: 12,
        shadowColor: Colors.black26,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(children: [
                  const Icon(Icons.place, color: AppColors.primary, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ValueListenableBuilder<LatLng>(
                      valueListenable: _center,
                      builder: (context, c, child) => Text(
                        '${c.latitude.toStringAsFixed(6)}, ${c.longitude.toStringAsFixed(6)}',
                        style: const TextStyle(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w700,
                            fontSize: 13),
                      ),
                    ),
                  ),
                  if (_resolving)
                    const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                ]),
                const SizedBox(height: 4),
                const Text(
                    'Move the map to place the pin. You can edit the name and address.',
                    style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                const SizedBox(height: 12),
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Place name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _address,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Full address'),
                ),
                if (recents.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Recent',
                      style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: recents.length,
                      separatorBuilder: (context, i) =>
                          const SizedBox(width: 8),
                      itemBuilder: (context, i) => ActionChip(
                        avatar: const Icon(Icons.history,
                            size: 16, color: AppColors.navy),
                        label: Text(recents[i].title,
                            style: const TextStyle(
                                color: AppColors.text, fontSize: 12.5)),
                        backgroundColor: AppColors.bg,
                        side: const BorderSide(color: AppColors.border),
                        onPressed: () => _apply(recents[i]),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton(
                    onPressed: _confirm,
                    child: const Text('Use this location')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
