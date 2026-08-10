package com.aiboxingcoach.pose_landmarker

import android.content.Context
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
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
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Runs MediaPipe Pose Landmarker over a recorded clip in VIDEO mode and streams
 * the landmark sequence back to Dart.
 *
 * Design (see docs/v0.5-pose-integration.md §1): file-in, not live. We decode
 * one frame per sample interval with MediaMetadataRetriever, run detectForVideo
 * on each, and emit progress so the rest-period UI can move. This trades peak
 * throughput for simplicity; the wall-clock budget is a stage-0.3 measurement to
 * take on the target device, and the lever if it doesn't fit is the sample rate.
 */
class PoseLandmarkerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private lateinit var methods: MethodChannel
    private lateinit var progress: EventChannel
    private lateinit var appContext: Context

    private val mainHandler = Handler(Looper.getMainLooper())
    private val cancelled = AtomicBoolean(false)
    private var worker: Thread? = null

    // How many landmarks MediaPipe Pose emits per frame.
    private val landmarkCount = 33

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
        var landmarker: PoseLandmarker? = null
        val retriever = MediaMetadataRetriever()
        try {
            landmarker = buildLandmarker(modelPath)
            retriever.setDataSource(videoPath)

            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            if (durationMs <= 0L) {
                post(events) { events.error("decode", "could not read clip duration", null) }
                return
            }

            val step = if (sampleEveryMs <= 0L) 33L else sampleEveryMs
            val totalFrames = (durationMs / step).toInt() + 1
            val frames = ArrayList<Map<String, Any?>>(totalFrames)

            var index = 0
            var tMs = 0L
            while (tMs <= durationMs) {
                if (cancelled.get()) {
                    post(events) { events.endOfStream() }
                    return
                }
                val bitmap = retriever.getFrameAtTime(
                    tMs * 1000L, // microseconds
                    MediaMetadataRetriever.OPTION_CLOSEST,
                )
                if (bitmap != null) {
                    val mpImage = BitmapImageBuilder(bitmap).build()
                    val result = landmarker.detectForVideo(mpImage, tMs)
                    frames.add(frameToMap(index, tMs.toDouble(), result))
                    bitmap.recycle()
                }

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
                tMs += step
            }

            post(events) {
                events.success(
                    mapOf(
                        "framesProcessed" to index,
                        "totalFrames" to totalFrames,
                        "frames" to frames,
                    )
                )
                events.endOfStream()
            }
        } catch (t: Throwable) {
            post(events) { events.error("estimation_failed", t.message ?: "$t", null) }
        } finally {
            try {
                retriever.release()
            } catch (_: Throwable) {
            }
            landmarker?.close()
        }
    }

    private fun buildLandmarker(modelPath: String): PoseLandmarker {
        val buffer = readFileToDirectBuffer(modelPath)
        // Prefer the GPU delegate; fall back to CPU if it can't be created.
        return try {
            createLandmarker(buffer, Delegate.GPU)
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
                        // PoseLandmarker exposes visibility; default to 0 if absent.
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
}
