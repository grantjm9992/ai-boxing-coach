package com.aiboxingcoach.pose_landmarker

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
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Runs MediaPipe Pose Landmarker over a recorded clip in VIDEO mode and streams
 * the landmark sequence back to Dart.
 *
 * Design (docs/v0.5-pose-integration.md §1): file-in, not live. The clip is
 * decoded **sequentially** with MediaExtractor + MediaCodec — one continuous
 * decode pass, sampling a frame roughly every `sampleEveryMs` — and each sampled
 * frame is run through detectForVideo. Sequential decode is dramatically faster
 * than the old MediaMetadataRetriever.getFrameAtTime path, which re-seeks and
 * re-decodes from a keyframe for *every* sample. If streaming fails on an
 * unusual codec, we fall back to the retriever path so analysis still completes.
 */
class PoseLandmarkerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private lateinit var methods: MethodChannel
    private lateinit var progress: EventChannel
    private lateinit var appContext: Context

    private val mainHandler = Handler(Looper.getMainLooper())
    private val cancelled = AtomicBoolean(false)
    private var worker: Thread? = null

    private val landmarkCount = 33

    private class CancelledException : Exception()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "pose_landmarker/methods")
        methods.setMethodCallHandler(this)
        progress = EventChannel(binding.binaryMessenger, "pose_landmarker/progress")
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
            "grabFrames" -> {
                val videoPath = call.argument<String>("videoPath")
                val times = call.argument<List<Number>>("timestampsMs")
                if (videoPath == null || times == null) {
                    result.error("bad_args", "videoPath and timestampsMs required", null)
                    return
                }
                // Decode off the main thread; deliver the result back on it.
                Thread {
                    try {
                        val frames = grabFrames(videoPath, times.map { it.toLong() })
                        mainHandler.post { result.success(frames) }
                    } catch (t: Throwable) {
                        mainHandler.post { result.error("grab_failed", describe(t), null) }
                    }
                }.start()
            }
            else -> result.notImplemented()
        }
    }

    /** JPEG bytes for each timestamp (ms), via the rotation-correct retriever. */
    private fun grabFrames(videoPath: String, timesMs: List<Long>): List<ByteArray> {
        val retriever = MediaMetadataRetriever()
        val out = ArrayList<ByteArray>(timesMs.size)
        try {
            retriever.setDataSource(videoPath)
            for (tMs in timesMs) {
                val bitmap = retriever.getFrameAtTime(
                    tMs * 1000L,
                    MediaMetadataRetriever.OPTION_CLOSEST,
                ) ?: continue
                val stream = ByteArrayOutputStream()
                bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, stream)
                bitmap.recycle()
                out.add(stream.toByteArray())
            }
        } finally {
            try {
                retriever.release()
            } catch (_: Throwable) {
            }
        }
        return out
    }

    // -- EventChannel: onListen starts the estimation run --------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        @Suppress("UNCHECKED_CAST")
        val args = arguments as? Map<String, Any?> ?: run {
            events.error("bad_args", "expected an arguments map", null)
            return
        }
        val videoPath = args["videoPath"] as? String
        val modelPath = args["modelPath"] as? String
        val sampleEveryMs = (args["sampleEveryMs"] as? Number)?.toLong() ?: 33L
        if (videoPath == null || modelPath == null) {
            events.error("bad_args", "videoPath and modelPath are required", null)
            return
        }

        cancelled.set(false)
        worker = Thread { runEstimation(videoPath, modelPath, sampleEveryMs, events) }
            .also { it.start() }
    }

    override fun onCancel(arguments: Any?) {
        cancelled.set(true)
    }

    // -- the work -----------------------------------------------------------

    private fun runEstimation(
        videoPath: String,
        modelPath: String,
        sampleEveryMs: Long,
        events: EventChannel.EventSink,
    ) {
        try {
            val step = if (sampleEveryMs <= 0L) 33L else sampleEveryMs
            val durationMs = readDurationMs(videoPath)
            if (durationMs <= 0L) {
                post(events) { events.error("decode", "could not read clip duration", null) }
                return
            }
            // The raw decoded frames are in the sensor orientation; MediaCodec
            // does not apply the container's rotation the way getFrameAtTime
            // does. Read it here and rotate each frame so MediaPipe sees exactly
            // the upright image the video player shows.
            val rotationDegrees = readRotationDegrees(videoPath)
            val totalFrames = (durationMs / step).toInt() + 1

            val frames: ArrayList<Map<String, Any?>> = try {
                runPass(modelPath, totalFrames, events) { onFrame ->
                    decodeStreaming(videoPath, step, rotationDegrees, onFrame)
                }
            } catch (c: CancelledException) {
                post(events) { events.endOfStream() }
                return
            } catch (t: Throwable) {
                // An unusual codec / container: fall back to the slow but robust
                // frame-by-frame retriever path with a fresh landmarker.
                Log.w(TAG, "streaming decode failed, falling back to retriever", t)
                try {
                    runPass(modelPath, totalFrames, events) { onFrame ->
                        decodeWithRetriever(videoPath, durationMs, step, onFrame)
                    }
                } catch (c: CancelledException) {
                    post(events) { events.endOfStream() }
                    return
                }
            }

            post(events) {
                events.success(
                    mapOf(
                        "framesProcessed" to frames.size,
                        "totalFrames" to totalFrames,
                        "frames" to frames,
                    )
                )
                events.endOfStream()
            }
        } catch (t: Throwable) {
            post(events) { events.error("estimation_failed", describe(t), null) }
        }
    }

    /**
     * A diagnostic, one-line rendering of a throwable: its class name, message,
     * and the whole `cause` chain, plus the top native/stack frame of the root
     * cause. MediaPipe wraps the real failure several layers deep, and only the
     * message reaches the UI — so surface enough here to identify it without a
     * logcat. Temporary aid while chasing the pose-init regression.
     */
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

    /**
     * One decode+detect pass. Builds a fresh landmarker (so VIDEO-mode timestamps
     * start monotonic), runs [decode] — which calls back with each sampled frame —
     * and returns the collected landmark frames.
     */
    private fun runPass(
        modelPath: String,
        totalFrames: Int,
        events: EventChannel.EventSink,
        decode: (onFrame: (Bitmap, Long) -> Unit) -> Unit,
    ): ArrayList<Map<String, Any?>> {
        val landmarker = buildLandmarker(modelPath)
        val frames = ArrayList<Map<String, Any?>>(totalFrames)
        var index = 0
        try {
            decode { bitmap, tMs ->
                if (cancelled.get()) throw CancelledException()
                val mpImage = BitmapImageBuilder(bitmap).build()
                val result = landmarker.detectForVideo(mpImage, tMs)
                frames.add(frameToMap(index, tMs.toDouble(), result))
                bitmap.recycle()
                if (index % 15 == 0) {
                    val processed = index
                    post(events) {
                        events.success(
                            mapOf(
                                "framesProcessed" to processed,
                                "totalFrames" to totalFrames,
                            )
                        )
                    }
                }
                index += 1
            }
        } finally {
            landmarker.close()
        }
        return frames
    }

    // -- decoders -----------------------------------------------------------

    /** Sequential decode via MediaExtractor + MediaCodec, sampling by timestamp. */
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
                // INFO_TRY_AGAIN_LATER / INFO_OUTPUT_FORMAT_CHANGED: loop again.
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

    /** The original per-frame path — slow (re-seeks per sample) but robust. */
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
                val bitmap = retriever.getFrameAtTime(
                    tMs * 1000L,
                    MediaMetadataRetriever.OPTION_CLOSEST,
                )
                if (bitmap != null) onFrame(bitmap, tMs)
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

    /** The clip's rotation (0/90/180/270) — the same the video player applies. */
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

    // -- YUV_420_888 -> Bitmap ----------------------------------------------

    /**
     * Convert the decoded frame straight to an ARGB_8888 [Bitmap]. The previous
     * path went YUV → NV21 → JPEG-encode → JPEG-decode per frame — a full codec
     * round-trip just to get a Bitmap, and the dominant cost of a pose run. Here
     * we do one integer BT.601 (full-range) conversion pass and hand MediaPipe
     * the same pixels directly. Stride-aware, so it is correct for both planar
     * and semi-planar YUV_420_888 layouts.
     */
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
                // Full-range BT.601, fixed-point (×256): 1.402, 0.344, 0.714, 1.772.
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

    private fun buildLandmarker(modelPath: String): PoseLandmarker {
        // CPU only. Selecting the GPU delegate makes MediaPipe populate its GPU
        // acceleration options proto, and on some devices' ART that proto's
        // schema fails to build reflectively — "Field platform_ for <obf> not
        // found" — taking createFromOptions down with it. The old GPU-first,
        // CPU-fallback path didn't help: the GPU attempt already triggers the
        // bad schema build, and the fallback just rebuilds and rethrows it.
        // VIDEO-mode pose over a recorded clip is fine on CPU.
        return createLandmarker(readFileToDirectBuffer(modelPath), Delegate.CPU)
    }

    private fun createLandmarker(model: ByteBuffer, delegate: Delegate): PoseLandmarker {
        val base = BaseOptions.builder()
            .setModelAssetBuffer(model)
            .setDelegate(delegate)
            .build()
        val options = PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(base)
            .setRunningMode(RunningMode.VIDEO)
            .setNumPoses(1)
            .setMinPoseDetectionConfidence(0.5f)
            .setMinPosePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .build()
        return PoseLandmarker.createFromOptions(appContext, options)
    }

    private fun frameToMap(
        index: Int,
        timestampMs: Double,
        result: PoseLandmarkerResult,
    ): Map<String, Any?> {
        val landmarks = ArrayList<List<Double>>(landmarkCount)
        val poses = result.landmarks()
        if (poses.isNotEmpty()) {
            for (lm in poses[0]) {
                landmarks.add(
                    listOf(
                        lm.x().toDouble(),
                        lm.y().toDouble(),
                        lm.z().toDouble(),
                        (if (lm.visibility().isPresent) lm.visibility().get() else 0f).toDouble(),
                    )
                )
            }
        }
        return mapOf("i" to index, "t" to timestampMs, "lm" to landmarks)
    }

    private fun readFileToDirectBuffer(path: String): ByteBuffer {
        val bytes = File(path).readBytes()
        val buffer = ByteBuffer.allocateDirect(bytes.size)
        buffer.put(bytes)
        buffer.rewind()
        return buffer
    }

    private inline fun post(events: EventChannel.EventSink, crossinline block: () -> Unit) {
        mainHandler.post { block() }
    }

    private companion object {
        const val TAG = "PoseLandmarker"
    }
}
