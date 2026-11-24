import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/map_tiles.dart';

class Place {
  const Place({
    required this.lat,
    required this.lng,
    required this.title,
    this.address = '',
    this.country = '',
  });

  final double lat, lng;
  final String title, address;

  /// ISO 3166 alpha-2 country code, e.g. "IN".
  final String country;

  /// Emoji flag for [country] ("IN" -> 🇮🇳), or '' when unknown.
  String get flag {
    final c = country.toUpperCase();
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(c)) return '';
    return String.fromCharCodes(c.codeUnits.map((u) => 0x1F1E6 + u - 65));
  }

  Place copyWith({String? title, String? address, String? country}) => Place(
        lat: lat,
        lng: lng,
        title: title ?? this.title,
        address: address ?? this.address,
        country: country ?? this.country,
      );

  bool sameSpot(Place o) =>
      (lat - o.lat).abs() < 1e-5 && (lng - o.lng).abs() < 1e-5;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'title': title,
        'address': address,
        'country': country,
      };

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        title: j['title'] as String? ?? '',
        address: j['address'] as String? ?? '',
        country: j['country'] as String? ?? '',
      );
}

typedef PlaceInfo = ({String title, String address, String country});

enum LocationMode { live, custom }

/// Single source of truth: live GPS, custom location and stamp preferences.
class AppState extends ChangeNotifier {
  AppState._(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppState> load() async {
    final s = AppState._(await SharedPreferences.getInstance());
    s._restore();
    return s;
  }

  LocationMode _mode = LocationMode.live;
  Place? _live, _custom;
  List<Place> _recents = [];
  double? accuracy;
  String? locationError;

  bool showMap = true,
      showAddress = true,
      showCoords = true,
      showDate = true,
      highQuality = true;
  MapStyle mapStyle = MapStyle.satellite;
  String note = '';

  LocationMode get mode => _mode;
  bool get isCustom => _mode == LocationMode.custom;
  Place? get live => _live;
  Place? get custom => _custom;
  List<Place> get recents => List.unmodifiable(_recents);

  /// The location stamped on photos right now.
  Place? get place => isCustom ? _custom : _live;

  void _restore() {
    final c = _prefs.getString('custom');
    if (c != null) {
      _custom = Place.fromJson(jsonDecode(c) as Map<String, dynamic>);
    }
    _recents = (_prefs.getStringList('recents') ?? const [])
        .map((s) => Place.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
    if (_prefs.getBool('isCustom') == true && _custom != null) {
      _mode = LocationMode.custom;
    }
    showMap = _prefs.getBool('showMap') ?? true;
    showAddress = _prefs.getBool('showAddress') ?? true;
    showCoords = _prefs.getBool('showCoords') ?? true;
    showDate = _prefs.getBool('showDate') ?? true;
    highQuality = _prefs.getBool('highQuality') ?? true;
    mapStyle = _prefs.getString('mapStyle') == MapStyle.street.name
        ? MapStyle.street
        : MapStyle.satellite;
    note = _prefs.getString('note') ?? '';
  }

  // ---------------------------------------------------------------- GPS

  StreamSubscription<Position>? _sub;
  bool _starting = false, _geocoding = false;
  Position? _geocodedAt;

  Future<void> startLocation() async {
    if (_sub != null || _starting) return;
    _starting = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _fail('Turn on device location (GPS)');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _fail('Location permission denied');
        return;
      }
      locationError = null;
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && _live == null) _onPosition(last);
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).listen(_onPosition, onError: (_) => _fail('Unable to get location'));
    } catch (_) {
      _fail('Unable to get location');
    } finally {
      _starting = false;
    }
  }

  /// Stops GPS (battery) while the app is in background.
  void stopLocation() {
    _sub?.cancel();
    _sub = null;
  }

  void _fail(String message) {
    locationError = message;
    notifyListeners();
  }

  void _onPosition(Position p) {
    accuracy = p.accuracy;
    locationError = null;
    _live = (_live ??
            Place(lat: p.latitude, lng: p.longitude, title: ''))
        ._moved(p.latitude, p.longitude);
    notifyListeners();

    // Reverse-geocode only when we moved > 25 m: saves network & battery.
    final g = _geocodedAt;
    if (!_geocoding &&
        (g == null ||
            Geolocator.distanceBetween(
                    g.latitude, g.longitude, p.latitude, p.longitude) >
                25)) {
      _reverse(p);
    }
  }

  Future<void> _reverse(Position p) async {
    _geocoding = true;
    try {
      final info = await describe(p.latitude, p.longitude);
      _geocodedAt = p;
      _live = _live?.copyWith(
          title: info.title, address: info.address, country: info.country);
      notifyListeners();
    } catch (_) {
      // Offline: keep coordinates, retry on next position update.
    } finally {
      _geocoding = false;
    }
  }

  static final _plusCode = RegExp(r'^[A-Z0-9]{4,8}\+[A-Z0-9]{2,3}$');

  /// Short title ("Ranipura, Rajasthan, India"), full address and country code.
  static Future<PlaceInfo> describe(double lat, double lng) async {
    final list = await placemarkFromCoordinates(lat, lng);
    if (list.isEmpty) return (title: 'Unknown place', address: '', country: '');
    final p = list.first;
    final title = _join([
      (p.subLocality?.isNotEmpty ?? false) ? p.subLocality : p.locality,
      p.administrativeArea,
      p.country,
    ]);
    final address = _join([
      p.name,
      p.street,
      p.subLocality,
      p.locality,
      p.subAdministrativeArea,
      '${p.administrativeArea ?? ''} ${p.postalCode ?? ''}',
      p.country,
    ]);
    return (
      title: title.isEmpty ? 'Unknown place' : title,
      address: address,
      country: p.isoCountryCode ?? '',
    );
  }

  static String _join(List<String?> parts) {
    final seen = <String>{};
    return parts
        .map((s) => s?.trim() ?? '')
        .where((s) => s.isNotEmpty && !_plusCode.hasMatch(s) && seen.add(s))
        .join(', ');
  }

  // ------------------------------------------------------- mutations

  void setMode(LocationMode m) {
    if (m == LocationMode.custom && _custom == null) return;
    _mode = m;
    _prefs.setBool('isCustom', isCustom);
    notifyListeners();
  }

  void setCustom(Place p) {
    _custom = p;
    _mode = LocationMode.custom;
    _recents = [p, ..._recents.where((r) => !r.sameSpot(p))].take(6).toList();
    _prefs.setString('custom', jsonEncode(p.toJson()));
    _prefs.setStringList(
        'recents', _recents.map((r) => jsonEncode(r.toJson())).toList());
    _prefs.setBool('isCustom', true);
    notifyListeners();
  }

  void updateStamp({
    bool? showMap,
    bool? showAddress,
    bool? showCoords,
    bool? showDate,
    bool? highQuality,
    MapStyle? mapStyle,
    String? note,
  }) {
    if (mapStyle != null) {
      this.mapStyle = mapStyle;
      _prefs.setString('mapStyle', mapStyle.name);
    }
    void setBool(String key, bool? v, void Function(bool) apply) {
      if (v == null) return;
      apply(v);
      _prefs.setBool(key, v);
    }

    setBool('showMap', showMap, (v) => this.showMap = v);
    setBool('showAddress', showAddress, (v) => this.showAddress = v);
    setBool('showCoords', showCoords, (v) => this.showCoords = v);
    setBool('showDate', showDate, (v) => this.showDate = v);
    setBool('highQuality', highQuality, (v) => this.highQuality = v);
    if (note != null) {
      this.note = note;
      _prefs.setString('note', note);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    stopLocation();
    super.dispose();
  }
}

extension on Place {
  Place _moved(double lat, double lng) =>
      Place(lat: lat, lng: lng, title: title, address: address, country: country);
}
