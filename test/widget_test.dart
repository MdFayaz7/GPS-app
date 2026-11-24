import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera/app_state.dart';
import 'package:gps_camera/services/map_tiles.dart';

void main() {
  test('tile window surrounds the point', () {
    final w = MapTiles.window(0, 0, z: 2); // n=4 -> point at tile (2,2) corner
    expect(w.x0, 1);
    expect(w.y0, 1);
    expect(w.px, closeTo(256, 1e-9));
    expect(w.py, closeTo(256, 1e-9));

    // Point always in the centre tile of the 3x3 block.
    final b = MapTiles.window(16.500732, 80.656216, z: 18); // Vijayawada
    expect(b.px, inInclusiveRange(256, 512));
    expect(b.py, inInclusiveRange(256, 512));
  });

  test('place json round-trip', () {
    const p = Place(lat: 12.5, lng: 77.25, title: 'MG Road', address: 'BLR');
    final q = Place.fromJson(p.toJson());
    expect(q.sameSpot(p), isTrue);
    expect(q.title, 'MG Road');
    expect(q.address, 'BLR');
  });
}
