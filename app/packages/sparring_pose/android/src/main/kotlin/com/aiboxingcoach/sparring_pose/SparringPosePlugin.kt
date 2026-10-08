package com.aiboxingcoach.sparring_pose

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Sparring mode's pose extractor: MediaPipe Pose Landmarker over a recorded
 * clip in VIDEO mode, returning **every** detected body per sampled frame —
 * not just the first — each with an appearance descriptor for identity
 * tracking (docs/SPARRING.md).
 *
 * Deliberately separate from the `pose_landmarker` plugin, which serves the
 * single-person pipeline and stays untouched. The decode loop (MediaExtractor +
 * MediaCodec, retriever fallback, YUV → ARGB) is a copy of that plugin's; a fix
 * to one belongs in both.
 *
 * Wire format, per frame: `{i, t, poses: [{lm: Float32[33*4], app: Float32[22]}]}`.
 * `lm` is x, y, z, visibility per landmark (MediaPipe order); `app` is two
 * 11-bin colour histograms (torso, then shorts) — see [appearance].
 *
 * Frames stream back in batches with the progress events (rather than one
 * huge message at the end), so a long round never has to cross the channel in
 * one piece. A `{reset: true}` event tells Dart to drop what it has (the
 * streaming decoder failed part-way and the fallback decoder starts again).
 */
class SparringPosePlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private lateinit var methods: MethodChannel
    private lateinit var progress: EventChannel
    private lateinit var appContext: Context

    private val mainHandler = Handler(Looper.getMainLooper())
    private val cancelled = AtomicBoolean(false)
    private var worker: Thread? = null

    private class CancelledException : Exception()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "sparring_pose/methods")
        methods.setMethodCallHandler(this)
        progress = EventChannel(binding.binaryMessenger, "sparring_pose/progress")
        progress.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        progress.setStreamHandler(null)
        cancelled.set(true)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "cancel" -> {
                cancelled.set(true)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // -- EventChannel: onListen starts the extraction run -------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        @Suppress("UNCHECKED_CAST")
        val args = arguments as? Map<String, Any?> ?: run {
            events.error("bad_args", "expected an arguments map", null)
            return
        }
        val videoPath = args["videoPath"] as? String
        val modelPath = args["modelPath"] as? String
        val sampleEveryMs = (args["sampleEveryMs"] as? Number)?.toLong() ?: 50L
        val maxPoses = ((args["maxPoses"] as? Number)?.toInt() ?: 3).coerceIn(1, 4)
        if (videoPath == null || modelPath == null) {
            events.error("bad_args", "videoPath and modelPath are required", null)
            return
        }

        cancelled.set(false)
        worker = Thread { runExtraction(videoPath, modelPath, sampleEveryMs, maxPoses, events) }
            .also { it.start() }
    }

    override fun onCancel(arguments: Any?) {
        cancelled.set(true)
    }

    // -- the work -----------------------------------------------------------

    private fun runExtraction(
        videoPath: String,
        modelPath: String,
        sampleEveryMs: Long,
        maxPoses: Int,
        events: EventChannel.EventSink,
    ) {
        try {
            val step = if (sampleEveryMs <= 0L) 50L else sampleEveryMs
            val durationMs = readDurationMs(videoPath)
            if (durationMs <= 0L) {
                post { events.error("decode", "could not read clip duration", null) }
                return
            }
            val rotationDegrees = readRotationDegrees(videoPath)
            val totalFrames = (durationMs / step).toInt() + 1

            val processed: Int = try {
                runPass(modelPath, maxPoses, totalFrames, events) { onFrame ->
                    decodeStreaming(videoPath, step, rotationDegrees, onFrame)
                }
            } catch (c: CancelledException) {
                post { events.endOfStream() }
                return
            } catch (t: Throwable) {
                Log.w(TAG, "streaming decode failed, falling back to retriever", t)
                post { events.success(mapOf("reset" to true)) }
                try {
                    runPass(modelPath, maxPoses, totalFrames, events) { onFrame ->
                        decodeWithRetriever(videoPath, durationMs, step, onFrame)
                    }
                } catch (c: CancelledException) {
                    post { events.endOfStream() }
                    return
                }
            }

            post {
                events.success(
                    mapOf(
                        "framesProcessed" to processed,
                        "totalFrames" to totalFrames,
                        "done" to true,
                    )
                )
                events.endOfStream()
            }
        } catch (t: Throwable) {
            post { events.error("extraction_failed", describe(t), null) }
        }
    }

    /**
     * One decode+detect pass with a fresh landmarker (VIDEO-mode timestamps must
     * start monotonic). Sends frames in batches with each progress event and
     * returns how many frames it processed.
     */
    private fun runPass(
        modelPath: String,
        maxPoses: Int,
        totalFrames: Int,
        events: EventChannel.EventSink,
        decode: (onFrame: (Bitmap, Long) -> Unit) -> Unit,
    ): Int {
        val landmarker = buildLandmarker(modelPath, maxPoses)
        var batch = ArrayList<Map<String, Any?>>(BATCH)
        var index = 0
        try {
            decode { bitmap, tMs ->
                if (cancelled.get()) throw CancelledException()
                val mpImage = BitmapImageBuilder(bitmap).build()
                val result = landmarker.detectForVideo(mpImage, tMs)
                val poses = ArrayList<Map<String, Any?>>(result.landmarks().size)
                for (pose in result.landmarks()) {
                    poses.add(
                        mapOf(
                            "lm" to landmarksToArray(pose),
                            "app" to appearance(bitmap, pose),
                        )
                    )
                }
                batch.add(mapOf("i" to index, "t" to tMs.toDouble(), "poses" to poses))
                bitmap.recycle()
                index += 1
                if (batch.size >= BATCH) {
                    val toSend = batch
                    val done = index
                    batch = ArrayList(BATCH)
                    post {
                        events.success(
                            mapOf(
                                "framesProcessed" to done,
                                "totalFrames" to totalFrames,
                                "frames" to toSend,
                            )
                        )
                    }
                }
            }
        } finally {
            landmarker.close()
        }
        if (batch.isNotEmpty()) {
            val toSend = batch
            val done = index
            post {
                events.success(
                    mapOf(
                        "framesProcessed" to done,
                        "totalFrames" to totalFrames,
                        "frames" to toSend,
                    )
                )
            }
        }
        return index
    }

    private fun landmarksToArray(pose: List<NormalizedLandmark>): FloatArray {
        val out = FloatArray(LANDMARKS * 4)
        val n = min(pose.size, LANDMARKS)
        for (k in 0 until n) {
            val lm = pose[k]
            out[k * 4] = lm.x()
            out[k * 4 + 1] = lm.y()
            out[k * 4 + 2] = lm.z()
            out[k * 4 + 3] = if (lm.visibility().isPresent) lm.visibility().get() else 0f
        }
        return out
    }

    // -- appearance ---------------------------------------------------------

    /**
     * Two 11-bin colour histograms — the torso (top) and the shorts — sampled
     * from regions the pose itself locates. Kit colour is the strongest identity
     * cue in a gym, and computing it here, during the one decode pass, avoids a
     * second decode. Bins 0–7: hue (chromatic pixels); 8: black; 9: grey;
     * 10: white. Each histogram sums to 1, or is all zero when its region wasn't
     * visible. Mirrored exactly by the iOS plugin.
     */
    private fun appearance(bitmap: Bitmap, pose: List<NormalizedLandmark>): FloatArray {
        val out = FloatArray(APPEARANCE_BINS * 2)
        if (pose.size < LANDMARKS) return out
        val w = bitmap.width
        val h = bitmap.height
        fun vis(i: Int) = if (pose[i].visibility().isPresent) pose[i].visibility().get() else 0f
        fun x(i: Int) = pose[i].x()
        fun y(i: Int) = pose[i].y()

        val torsoOk = vis(11) >= MIN_VIS && vis(12) >= MIN_VIS && vis(23) >= MIN_VIS && vis(24) >= MIN_VIS
        if (!torsoOk) return out
        val top = min(y(11), y(12))
        val bottom = max(y(23), y(24))
        val torsoH = bottom - top
        if (torsoH <= 0f) return out

        // Torso: inner part of the shoulder–hip quad. Side-on the shoulders
        // overlap in x, so the width never drops below half the torso height.
        val cx = (x(11) + x(12) + x(23) + x(24)) / 4f
        val spanX = max(max(x(11), x(12)), max(x(23), x(24))) - min(min(x(11), x(12)), min(x(23), x(24)))
        val torsoW = max(spanX, 0.5f * torsoH)
        histogram(
            bitmap, w, h,
            cx - 0.35f * torsoW, top + 0.15f * torsoH,
            cx + 0.35f * torsoW, bottom - 0.1f * torsoH,
            out, 0,
        )

        // Shorts: hips down to halfway to the knees.
        val hipY = (y(23) + y(24)) / 2f
        val hipX = (x(23) + x(24)) / 2f
        val kneesOk = vis(25) >= MIN_VIS && vis(26) >= MIN_VIS
        val seg = if (kneesOk) ((y(25) + y(26)) / 2f - hipY) else 0.4f * torsoH
        val shortsH = if (seg > 0f) 0.5f * seg else 0.2f * torsoH
        val shortsW = max(kotlin.math.abs(x(23) - x(24)), 0.35f * torsoH)
        histogram(
            bitmap, w, h,
            hipX - 0.5f * shortsW, hipY,
            hipX + 0.5f * shortsW, hipY + shortsH,
            out, APPEARANCE_BINS,
        )
        return out
    }

    private fun histogram(
        bitmap: Bitmap,
        w: Int,
        h: Int,
        nx0: Float,
        ny0: Float,
        nx1: Float,
        ny1: Float,
        out: FloatArray,
        offset: Int,
    ) {
        val x0 = (nx0 * w).toInt().coerceIn(0, w - 1)
        val y0 = (ny0 * h).toInt().coerceIn(0, h - 1)
        val x1 = (nx1 * w).toInt().coerceIn(0, w - 1)
        val y1 = (ny1 * h).toInt().coerceIn(0, h - 1)
        val rw = x1 - x0
        val rh = y1 - y0
        if (rw < 2 || rh < 2) return
        val pixels = IntArray(rw * rh)
        bitmap.getPixels(pixels, 0, rw, x0, y0, rw, rh)
        val stride = max(1, sqrt((rw * rh).toDouble() / MAX_SAMPLES).toInt())
        var count = 0
        var row = 0
        while (row < rh) {
            var col = 0
            while (col < rw) {
                val p = pixels[row * rw + col]
                out[offset + colourBin((p shr 16) and 0xFF, (p shr 8) and 0xFF, p and 0xFF)] += 1f
                count++
                col += stride
            }
            row += stride
        }
        if (count == 0) return
        for (k in 0 until APPEARANCE_BINS) out[offset + k] /= count.toFloat()
    }

    /** HSV bin for one pixel; see [appearance]. */
    private fun colourBin(r: Int, g: Int, b: Int): Int {
        val mx = max(r, max(g, b))
        val mn = min(r, min(g, b))
        val v = mx / 255f
        val s = if (mx == 0) 0f else (mx - mn).toFloat() / mx
        if (v < 0.2f) return 8
        if (s < 0.25f) return if (v < 0.7f) 9 else 10
        val d = (mx - mn).toFloat()
        var hue = when (mx) {
            r -> 60f * (((g - b) / d) % 6f)
            g -> 60f * (((b - r) / d) + 2f)
            else -> 60f * (((r - g) / d) + 4f)
        }
        if (hue < 0f) hue += 360f
        return min(7, (hue / 45f).toInt())
    }

    // -- decoders (copied from pose_landmarker) -----------------------------

    private fun decodeStreaming(
        videoPath: String,
        stepMs: Long,
        rotationDegrees: Int,
        onFrame: (Bitmap, Long) -> Unit,
    ) {
        val extractor = MediaExtractor()
        extractor.setDataSource(videoPath)
        var trackIndex = -1
        var format: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val f = extractor.getTrackFormat(i)
            if (f.getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true) {
                trackIndex = i
                format = f
                break
            }
        }
        if (trackIndex < 0 || format == null) {
            extractor.release()
            throw IllegalStateException("no video track in $videoPath")
        }
        extractor.selectTrack(trackIndex)
        val mime = format.getString(MediaFormat.KEY_MIME)!!
        format.setInteger(
            MediaFormat.KEY_COLOR_FORMAT,
            MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible,
        )
        val codec = MediaCodec.createDecoderByType(mime)
        codec.configure(format, null, null, 0)
        codec.start()

        val info = MediaCodec.BufferInfo()
        val stepUs = stepMs * 1000L
        var nextSampleUs = 0L
        var sawInputEOS = false
        var sawOutputEOS = false
        try {
            while (!sawOutputEOS) {
                if (cancelled.get()) throw CancelledException()

                if (!sawInputEOS) {
                    val inIndex = codec.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val inBuf = codec.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(inBuf, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(
                                inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            sawInputEOS = true
                        } else {
                            codec.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                val outIndex = codec.dequeueOutputBuffer(info, 10_000)
                if (outIndex >= 0) {
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        sawOutputEOS = true
                    }
                    val ptsUs = info.presentationTimeUs
                    if (info.size > 0 && ptsUs >= nextSampleUs) {
                        val image = codec.getOutputImage(outIndex)
                        if (image != null) {
                            val bitmap = imageToBitmap(image)
                            image.close()
                            if (bitmap != null) {
                                onFrame(rotateBitmap(bitmap, rotationDegrees), ptsUs / 1000L)
                            }
                        }
                        nextSampleUs = (ptsUs / stepUs + 1) * stepUs
                    }
                    codec.releaseOutputBuffer(outIndex, false)
                }
            }
        } finally {
            try {
                codec.stop()
            } catch (_: Throwable) {
            }
            codec.release()
            extractor.release()
        }
    }

    private fun decodeWithRetriever(
        videoPath: String,
        durationMs: Long,
        stepMs: Long,
        onFrame: (Bitmap, Long) -> Unit,
    ) {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(videoPath)
            var tMs = 0L
            while (tMs <= durationMs) {
                if (cancelled.get()) throw CancelledException()
                val frame = retriever.getFrameAtTime(
                    tMs * 1000L,
                    MediaMetadataRetriever.OPTION_CLOSEST,
                )
                if (frame != null) {
                    // getPixels needs a software ARGB_8888 bitmap.
                    val bitmap = if (frame.config == Bitmap.Config.ARGB_8888) {
                        frame
                    } else {
                        frame.copy(Bitmap.Config.ARGB_8888, false).also { frame.recycle() }
                    }
                    onFrame(bitmap, tMs)
                }
                tMs += stepMs
            }
        } finally {
            try {
                retriever.release()
            } catch (_: Throwable) {
            }
        }
    }

    private fun readDurationMs(videoPath: String): Long {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(videoPath)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
        } catch (_: Throwable) {
            0L
        } finally {
            try {
                retriever.release()
            } catch (_: Throwable) {
            }
        }
    }

    private fun readRotationDegrees(videoPath: String): Int {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(videoPath)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
        } catch (_: Throwable) {
            0
        } finally {
            try {
                retriever.release()
            } catch (_: Throwable) {
            }
        }
    }

    private fun rotateBitmap(src: Bitmap, degrees: Int): Bitmap {
        val normalized = ((degrees % 360) + 360) % 360
        if (normalized == 0) return src
        val matrix = Matrix().apply { postRotate(normalized.toFloat()) }
        val rotated =
            Bitmap.createBitmap(src, 0, 0, src.width, src.height, matrix, true)
        if (rotated !== src) src.recycle()
        return rotated
    }

    /** YUV_420_888 → ARGB_8888, full-range BT.601 (copied from pose_landmarker). */
    private fun imageToBitmap(image: Image): Bitmap? {
        if (image.format != ImageFormat.YUV_420_888) return null
        val width = image.width
        val height = image.height

        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]
        val yBuffer = yPlane.buffer
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer
        val yRowStride = yPlane.rowStride
        val yPixStride = yPlane.pixelStride
        val uRowStride = uPlane.rowStride
        val uPixStride = uPlane.pixelStride
        val vRowStride = vPlane.rowStride
        val vPixStride = vPlane.pixelStride

        val argb = IntArray(width * height)
        var idx = 0
        for (row in 0 until height) {
            val yRowStart = row * yRowStride
            val chromaRow = row shr 1
            val uRowStart = chromaRow * uRowStride
            val vRowStart = chromaRow * vRowStride
            for (col in 0 until width) {
                val y = yBuffer.get(yRowStart + col * yPixStride).toInt() and 0xFF
                val chromaCol = col shr 1
                val u = (uBuffer.get(uRowStart + chromaCol * uPixStride).toInt() and 0xFF) - 128
                val v = (vBuffer.get(vRowStart + chromaCol * vPixStride).toInt() and 0xFF) - 128
                var r = y + ((359 * v) shr 8)
                var g = y - ((88 * u) shr 8) - ((183 * v) shr 8)
                var b = y + ((454 * u) shr 8)
                if (r < 0) r = 0 else if (r > 255) r = 255
                if (g < 0) g = 0 else if (g > 255) g = 255
                if (b < 0) b = 0 else if (b > 255) b = 255
                argb[idx++] = -0x1000000 or (r shl 16) or (g shl 8) or b
            }
        }
        return Bitmap.createBitmap(argb, width, height, Bitmap.Config.ARGB_8888)
    }

    // -- MediaPipe ----------------------------------------------------------

    /** CPU only — see the pose_landmarker plugin for why the GPU delegate is off. */
    private fun buildLandmarker(modelPath: String, maxPoses: Int): PoseLandmarker {
        val base = BaseOptions.builder()
            .setModelAssetBuffer(readFileToDirectBuffer(modelPath))
            .setDelegate(Delegate.CPU)
            .build()
        val options = PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(base)
            .setRunningMode(RunningMode.VIDEO)
            // More than two: in a gym, a coach or another pair can be in shot,
            // and with only two slots VIDEO-mode tracking can lock onto a
            // bystander and starve a fighter. The tracker picks the fighters.
            .setNumPoses(maxPoses)
            .setMinPoseDetectionConfidence(0.5f)
            .setMinPosePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .build()
        return PoseLandmarker.createFromOptions(appContext, options)
    }

    private fun readFileToDirectBuffer(path: String): ByteBuffer {
        val bytes = File(path).readBytes()
        val buffer = ByteBuffer.allocateDirect(bytes.size)
        buffer.put(bytes)
        buffer.rewind()
        return buffer
    }

    private fun describe(t: Throwable): String {
        val sb = StringBuilder()
        var cur: Throwable? = t
        var depth = 0
        while (cur != null && depth < 8) {
            if (depth > 0) sb.append("  ← caused by: ")
            sb.append(cur.javaClass.name)
            cur.message?.let { sb.append(": ").append(it) }
            val next = cur.cause
            if (next == null) {
                cur.stackTrace.firstOrNull()?.let { sb.append("  @ ").append(it.toString()) }
            }
            cur = if (next === cur) null else next
            depth++
        }
        return sb.toString()
    }

    private inline fun post(crossinline block: () -> Unit) {
        mainHandler.post { block() }
    }

    private companion object {
        const val TAG = "SparringPose"
        const val LANDMARKS = 33
        const val APPEARANCE_BINS = 11
        const val MIN_VIS = 0.3f
        const val MAX_SAMPLES = 600.0
        const val BATCH = 20
    }
}
