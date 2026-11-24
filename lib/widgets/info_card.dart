import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../services/map_tiles.dart';
import '../theme.dart';
import 'mini_map.dart';

/// Where the stamp sits on the photo, as fractions of the photo width.
/// Used both on screen and when burning the stamp into the JPEG, so the
/// saved photo always matches the reference layout on any device.
class StampLayout {
  StampLayout._();
  static const side = 0.039; // left/right margin
  static const bottom = 0.02; // bottom margin
  static double cardWidth(double photoWidth) => photoWidth * (1 - 2 * side);
}

/// The geotag stamp: square map on the left, dark translucent info panel on
/// the right, app badge attached to the panel's top-right corner.
/// Every size is a fraction of the card width (proportions measured from
/// the reference photo), so it renders identically at any resolution.
class InfoCard extends StatefulWidget {
  const InfoCard({super.key, required this.state});

  final AppState state;

  @override
  State<InfoCard> createState() => _InfoCardState();
}

class _InfoCardState extends State<InfoCard> {
  static final _dateFmt = DateFormat('EEEE, dd/MM/yyyy hh:mm a');
  static const _panel = Color(0x99000000); // black @ 60%

  late final Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Repaint only when the minute changes.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final n = DateTime.now();
      if (n.minute != _now.minute) setState(() => _now = n);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  static String _gmt(DateTime t) {
    final o = t.timeZoneOffset;
    final m = o.inMinutes.abs();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'GMT ${o.isNegative ? '-' : '+'}${two(m ~/ 60)}:${two(m % 60)}';
  }

  @override
  Widget build(BuildContext context) => MediaQuery.withNoTextScaling(
        // Stamp must look the same regardless of system font size.
        child: LayoutBuilder(
          builder: (context, box) => ListenableBuilder(
            listenable: widget.state,
            builder: (context, child) => _stamp(box.maxWidth),
          ),
        ),
      );

  Widget _stamp(double cw) {
    final s = widget.state;
    final p = s.place;
    final u = cw / 370; // 1 design unit
    final mapSize = (cw * 0.269).floorToDouble();
    final r = Radius.circular(2.6 * u);

    final title = TextStyle(
      color: Colors.white,
      fontSize: 13.8 * u,
      fontWeight: FontWeight.w400,
      height: 1.22,
      letterSpacing: 0.1 * u,
    );
    final body = TextStyle(
      color: Colors.white,
      fontSize: 8.7 * u,
      fontWeight: FontWeight.w400,
      height: 1.2,
      letterSpacing: 0.1 * u,
    );

    Widget panel(List<Widget> children) => Container(
          constraints: BoxConstraints(minHeight: s.showMap ? mapSize : 0),
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.fromLTRB(8 * u, 7 * u, 6 * u, 7 * u),
          decoration: BoxDecoration(
            color: _panel,
            borderRadius:
                BorderRadius.only(topLeft: r, bottomLeft: r, bottomRight: r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        );

    if (p == null) {
      return panel([
        Row(children: [
          SizedBox(
            width: 12 * u,
            height: 12 * u,
            child: s.locationError == null
                ? const CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary)
                : Icon(Icons.location_off,
                    color: AppColors.primary, size: 12 * u),
          ),
          SizedBox(width: 8 * u),
          Expanded(
              child: Text(s.locationError ?? 'Fetching your location…',
                  style: body)),
        ]),
      ]);
    }

    final flag = p.flag;
    final lines = <Widget>[
      Text(
        flag.isEmpty
            ? (p.title.isEmpty ? 'Current location' : p.title)
            : '${p.title.isEmpty ? 'Current location' : p.title} $flag',
        style: title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      SizedBox(height: 1.5 * u),
      if (s.showAddress && p.address.isNotEmpty)
        Text(p.address,
            style: body, maxLines: 3, overflow: TextOverflow.ellipsis),
      if (s.showCoords)
        Text(
            'Lat ${p.lat.toStringAsFixed(6)}° Long ${p.lng.toStringAsFixed(6)}°',
            style: body,
            maxLines: 1),
      if (s.showDate)
        Text('${_dateFmt.format(_now)} ${_gmt(_now)}',
            style: body, maxLines: 1),
      if (s.note.isNotEmpty)
        Text('Note : ${s.note}',
            style: body, maxLines: 2, overflow: TextOverflow.ellipsis),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _badge(u, r),
        SizedBox(height: 2 * u),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (s.showMap) ...[
              ClipRRect(
                borderRadius: BorderRadius.all(r),
                child: Stack(children: [
                  MiniMap(
                      lat: p.lat,
                      lng: p.lng,
                      size: mapSize,
                      style: s.mapStyle),
                  Positioned(
                    left: 4 * u,
                    bottom: 3 * u,
                    child: Text(MapTiles.attribution(s.mapStyle),
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 6.5 * u,
                            fontWeight: FontWeight.w700,
                            shadows: const [
                              Shadow(color: Colors.black, blurRadius: 2)
                            ])),
                  ),
                ]),
              ),
              SizedBox(width: 7.5 * u),
            ],
            Expanded(child: panel(lines)),
          ],
        ),
      ],
    );
  }

  Widget _badge(double u, Radius r) => Container(
        height: 13.5 * u,
        padding: EdgeInsets.fromLTRB(4 * u, 0, 5 * u, 0),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.all(r),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 10 * u,
            height: 10 * u,
            decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2 * u)),
            child: Icon(Icons.location_on, color: Colors.white, size: 8 * u),
          ),
          SizedBox(width: 5 * u),
          Text('GPS Camera',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 9.6 * u,
                  height: 1,
                  fontWeight: FontWeight.w400)),
        ]),
      );
}
