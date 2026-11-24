import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/map_tiles.dart';

/// Square map thumbnail centred on a point (3x3 cached tiles, red pin).
class MiniMap extends StatefulWidget {
  const MiniMap({
    super.key,
    required this.lat,
    required this.lng,
    required this.size,
    this.style = MapStyle.satellite,
  });

  final double lat, lng, size;
  final MapStyle style;

  @override
  State<MiniMap> createState() => _MiniMapState();
}

class _MiniMapState extends State<MiniMap> {
  static const _n = TileWindow.span;
  static const _windowPx = 360.0; // tile pixels shown across the square

  late TileWindow _w;
  List<Uint8List?> _tiles = List.filled(_n * _n, null);

  TileWindow _window() => MapTiles.window(widget.lat, widget.lng,
      z: MapTiles.zoomFor(widget.style));

  @override
  void initState() {
    super.initState();
    _w = _window();
    _load(_w, widget.style);
  }

  @override
  void didUpdateWidget(MiniMap old) {
    super.didUpdateWidget(old);
    if (old.lat == widget.lat &&
        old.lng == widget.lng &&
        old.style == widget.style) {
      return;
    }
    final w = _window();
    final changed = !w.sameTiles(_w) || old.style != widget.style;
    _w = w;
    if (changed) {
      _tiles = List.filled(_n * _n, null);
      _load(w, widget.style);
    }
  }

  Future<void> _load(TileWindow w, MapStyle style) async {
    final tiles = await Future.wait([
      for (var j = 0; j < _n; j++)
        for (var i = 0; i < _n; i++)
          MapTiles.tile(style, w.z, w.x0 + i, w.y0 + j),
    ]);
    if (mounted && w.sameTiles(_w) && style == widget.style) {
      setState(() => _tiles = tiles);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final k = size / _windowPx;
    final pin = size * 0.30;
    return SizedBox(
      width: size,
      height: size,
      child: ColoredBox(
        color: widget.style == MapStyle.satellite
            ? const Color(0xFF5A6152)
            : const Color(0xFFE6E2D8),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (var j = 0; j < _n; j++)
              for (var i = 0; i < _n; i++)
                if (_tiles[j * _n + i] case final bytes?)
                  Positioned(
                    left: size / 2 + (i * 256 - _w.px) * k,
                    top: size / 2 + (j * 256 - _w.py) * k,
                    // +0.5 hides hairline seams between tiles
                    width: 256 * k + 0.5,
                    height: 256 * k + 0.5,
                    child: Image.memory(bytes,
                        gaplessPlayback: true,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.medium),
                  ),
            Positioned(
              left: (size - pin) / 2,
              top: size / 2 - pin * 0.92,
              child: Icon(Icons.location_on,
                  size: pin,
                  color: const Color(0xFFE53935),
                  shadows: const [
                    Shadow(color: Color(0x99000000), blurRadius: 3)
                  ]),
            ),
          ],
        ),
      ),
    );
  }
}
