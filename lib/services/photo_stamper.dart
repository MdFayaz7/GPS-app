import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../widgets/info_card.dart';

/// Burns the info card into the captured photo.
///
/// Only the small card is rendered in Dart; decoding, compositing, JPEG
/// encoding and EXIF GPS tagging run natively on a background thread
/// (see MainActivity.kt) – no multi-MB buffers cross the channel.
/// Placement uses [StampLayout] fractions of the photo width, so the stamp
/// lands in the same spot on every device and photo resolution.
class PhotoStamper {
  PhotoStamper._();

  static const _channel = MethodChannel('gps_camera/native');
  static final _fileFmt = DateFormat('yyyyMMdd_HHmmss_SSS');
  static final _exifFmt = DateFormat('yyyy:MM:dd HH:mm:ss');

  static Future<String> stamp({
    required String photoPath,
    required RenderRepaintBoundary card,
    required Place place,
    required DateTime time,
  }) async {
    await SchedulerBinding.instance.endOfFrame; // card fully painted
    // ~2600px wide card: crisp on 12MP photos, cheap to encode.
    final img =
        await card.toImage(pixelRatio: math.min(7, 2600 / card.size.width));
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();

    final out =
        '${File(photoPath).parent.path}/GPSCam_${_fileFmt.format(time)}.jpg';
    final result = await _channel.invokeMethod<String>('stamp', {
      'src': photoPath,
      'out': out,
      'card': png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      'left': StampLayout.side,
      'width': 1 - 2 * StampLayout.side,
      'bottom': StampLayout.bottom,
      'lat': place.lat,
      'lng': place.lng,
      'time': _exifFmt.format(time),
    });
    return result!;
  }
}
