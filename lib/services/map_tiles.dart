import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

enum MapStyle { satellite, street }

/// A 3x3 block of map tiles around a point. The point always lies in the
/// centre tile, so any window up to 512px wide around it is fully covered.
/// [px]/[py] are the point's pixel position inside the 768x768 block.
class TileWindow {
  const TileWindow(this.z, this.x0, this.y0, this.px, this.py);
  final int z, x0, y0;
  final double px, py;

  static const span = 3;

  bool sameTiles(TileWindow o) => z == o.z && x0 == o.x0 && y0 == o.y0;
}

/// Small tile fetcher for the stamp's mini map: LRU memory cache and
/// de-duplicated in-flight requests.
class MapTiles {
  MapTiles._();

  static const userAgent = 'GPSCameraApp/1.0 (com.sphurthy.gps_camera)';
  static const _maxCached = 64;
  static final _client = http.Client();
  static final _cache = <String, Uint8List>{};
  static final _pending = <String, Future<Uint8List?>>{};

  static int zoomFor(MapStyle s) => s == MapStyle.satellite ? 18 : 17;

  static String attribution(MapStyle s) =>
      s == MapStyle.satellite ? '© Esri' : '© OpenStreetMap';

  static TileWindow window(double lat, double lng, {required int z}) {
    final n = 1 << z;
    final la = lat.clamp(-85.0511, 85.0511).toDouble() * pi / 180;
    final fx = (lng + 180) / 360 * n;
    final fy = (1 - log(tan(la) + 1 / cos(la)) / pi) / 2 * n;
    final x0 = fx.floor() - 1, y0 = fy.floor() - 1;
    return TileWindow(z, x0, y0, (fx - x0) * 256, (fy - y0) * 256);
  }

  static Uri _url(MapStyle s, int z, int x, int y) => s == MapStyle.satellite
      ? Uri.parse('https://server.arcgisonline.com/ArcGIS/rest/services/'
          'World_Imagery/MapServer/tile/$z/$y/$x')
      : Uri.parse('https://tile.openstreetmap.org/$z/$x/$y.png');

  static Future<Uint8List?> tile(MapStyle s, int z, int x, int y) {
    final n = 1 << z;
    if (y < 0 || y >= n) return Future.value(null);
    x = ((x % n) + n) % n;
    final key = '${s.name}/$z/$x/$y';
    final hit = _cache.remove(key);
    if (hit != null) return Future.value(_cache[key] = hit); // bump LRU
    return _pending[key] ??= _fetch(key, _url(s, z, x, y))
        .whenComplete(() => _pending.remove(key));
  }

  static Future<Uint8List?> _fetch(String key, Uri url) async {
    try {
      final r = await _client.get(url, headers: const {
        'User-Agent': userAgent
      }).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      if (_cache.length >= _maxCached) _cache.remove(_cache.keys.first);
      return _cache[key] = r.bodyBytes;
    } catch (_) {
      return null; // offline -> map placeholder
    }
  }
}
