package com.aiboxingcoach.pose_landmarker

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
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
            else -> result.notImplemented()
        }
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
            val totalFrames = (durationMs / step).toInt() + 1

            val frames: ArrayList<Map<String, Any?>> = try {
                runPass(modelPath, totalFrames, events) { onFrame ->
                    decodeStreaming(videoPath, step, onFrame)
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
            post(events) { events.error("estimation_failed", t.message ?: "$t", null) }
        }
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
                            if (bitmap != null) onFrame(bitmap, ptsUs / 1000L)
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

    // -- YUV_420_888 -> Bitmap ----------------------------------------------

    private fun imageToBitmap(image: Image): Bitmap? {
        if (image.format != ImageFormat.YUV_420_888) return null
        val nv21 = yuv420ToNv21(image)
        val yuv = YuvImage(nv21, ImageFormat.NV21, image.width, image.height, null)
        val out = ByteArrayOutputStream()
        yuv.compressToJpeg(Rect(0, 0, image.width, image.height), 85, out)
        val bytes = out.toByteArray()
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
    }

    private fun yuv420ToNv21(image: Image): ByteArray {
        val width = image.width
        val height = image.height
        val chromaWidth = width / 2
        val chromaHeight = height / 2
        val nv21 = ByteArray(width * height + 2 * chromaWidth * chromaHeight)

        val yPlane = image.planes[0]
        val yBuffer = yPlane.buffer
        val yRowStride = yPlane.rowStride
        val yPixStride = yPlane.pixelStride
        var pos = 0
        for (row in 0 until height) {
            val rowStart = row * yRowStride
            for (col in 0 until width) {
                nv21[pos++] = yBuffer.get(rowStart + col * yPixStride)
            }
        }

        // NV21 chroma is interleaved V, U.
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer
        val uRowStride = uPlane.rowStride
        val uPixStride = uPlane.pixelStride
        val vRowStride = vPlane.rowStride
        val vPixStride = vPlane.pixelStride
        for (row in 0 until chromaHeight) {
            for (col in 0 until chromaWidth) {
                nv21[pos++] = vBuffer.get(row * vRowStride + col * vPixStride)
                nv21[pos++] = uBuffer.get(row * uRowStride + col * uPixStride)
            }
        }
        return nv21
    }

    // -- MediaPipe ----------------------------------------------------------

    private fun buildLandmarker(modelPath: String): PoseLandmarker {
        return try {
            createLandmarker(readFileToDirectBuffer(modelPath), Delegate.GPU)
        } catch (_: Throwable) {
            createLandmarker(readFileToDirectBuffer(modelPath), Delegate.CPU)
        }
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
