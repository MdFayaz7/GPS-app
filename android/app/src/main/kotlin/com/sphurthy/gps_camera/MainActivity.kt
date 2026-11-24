package com.sphurthy.gps_camera

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.media.ExifInterface
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * Native photo stamping: decode -> upright -> draw card -> JPEG -> EXIF GPS.
 * Runs on a single background thread so the UI never janks.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val MAX_SIDE = 4096
    }

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gps_camera/native")
            .setMethodCallHandler { call, result ->
                if (call.method != "stamp") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val src = call.argument<String>("src")!!
                val out = call.argument<String>("out")!!
                val card = call.argument<ByteArray>("card")!!
                val left = call.argument<Double>("left")!!
                val width = call.argument<Double>("width")!!
                val bottom = call.argument<Double>("bottom")!!
                val lat = call.argument<Double>("lat")!!
                val lng = call.argument<Double>("lng")!!
                val time = call.argument<String>("time")!!
                worker.execute {
                    try {
                        stamp(src, out, card, left, width, bottom, lat, lng, time)
                        main.post { result.success(out) }
                    } catch (e: Throwable) {
                        main.post { result.error("STAMP_FAILED", e.message, null) }
                    }
                }
            }
    }

    override fun onDestroy() {
        worker.shutdown()
        super.onDestroy()
    }

    private fun stamp(
        src: String, out: String, card: ByteArray,
        left: Double, width: Double, bottom: Double,
        lat: Double, lng: Double, time: String,
    ) {
        val orientation = ExifInterface(src)
            .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        // Downsample very large sensors (50MP+) so we never run out of memory.
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(src, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > MAX_SIDE) sample *= 2
        val decoded = BitmapFactory.decodeFile(src, BitmapFactory.Options().apply {
            inMutable = true
            inSampleSize = sample
        }) ?: error("Could not decode photo")
        val photo = upright(decoded, orientation)
        val overlay = BitmapFactory.decodeByteArray(card, 0, card.size)
            ?: error("Could not decode overlay")

        // Geometry arrives as fractions of the preview width.
        val pw = photo.width.toFloat()
        val w = (width * pw).toFloat()
        val h = w * overlay.height / overlay.width
        val l = (left * pw).toFloat()
        val t = photo.height - (bottom * pw).toFloat() - h
        Canvas(photo).drawBitmap(
            overlay, null, RectF(l, t, l + w, t + h),
            Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG),
        )
        overlay.recycle()

        FileOutputStream(out).use { photo.compress(Bitmap.CompressFormat.JPEG, 92, it) }
        photo.recycle()

        ExifInterface(out).apply {
            setAttribute(ExifInterface.TAG_GPS_LATITUDE, dms(lat))
            setAttribute(ExifInterface.TAG_GPS_LATITUDE_REF, if (lat >= 0) "N" else "S")
            setAttribute(ExifInterface.TAG_GPS_LONGITUDE, dms(lng))
            setAttribute(ExifInterface.TAG_GPS_LONGITUDE_REF, if (lng >= 0) "E" else "W")
            setAttribute(ExifInterface.TAG_DATETIME, time)
            setAttribute(ExifInterface.TAG_DATETIME_ORIGINAL, time)
            setAttribute(ExifInterface.TAG_SOFTWARE, "GPS Camera")
            saveAttributes()
        }
        File(src).delete()
    }

    private fun upright(b: Bitmap, orientation: Int): Bitmap {
        val m = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> m.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> m.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> m.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> m.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> m.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { m.postRotate(90f); m.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_TRANSVERSE -> { m.postRotate(270f); m.postScale(-1f, 1f) }
            else -> return b
        }
        val r = Bitmap.createBitmap(b, 0, 0, b.width, b.height, m, true)
        if (r !== b) b.recycle()
        if (r.isMutable) return r
        return r.copy(Bitmap.Config.ARGB_8888, true).also { r.recycle() }
    }

    /** Decimal degrees -> EXIF rational "d/1,m/1,s/10000". */
    private fun dms(value: Double): String {
        val a = abs(value)
        val d = a.toInt()
        val minutes = (a - d) * 60
        val m = minutes.toInt()
        val s = ((minutes - m) * 60 * 10000).roundToLong()
        return "$d/1,$m/1,$s/10000"
    }
}
