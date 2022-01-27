package com.squarevalley.i8birdies.improve.aicoach.detection

import android.content.Context
import android.graphics.*
import android.media.*
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import com.osmapps.framework.util.FileUtil
import com.osmapps.golf.common.bean.domain.practice2.JointDetectionResult
import com.osmapps.golf.common.bean.domain.practice2.SwingDetectionResult
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer


abstract class ExportException(message: String) : Exception(message)

class VideoTrackNotFoundException : ExportException("video track not found")
class VideoFormatNotSupportException : ExportException("video format not support")
class ExportPathException : ExportException("export path error")

@RequiresApi(Build.VERSION_CODES.M)
private class MuxerWrapper(
    val muxer: MediaMuxer,
    val jointResult: JointDetectionResult,
    val exportFile: String,
    val segmentIndex: Int,
    val segment: Pair<Int, Int>
) {

    var startTimeUs = -1L
    var endTimeUs = -1L
    var videoTrackIndex = -1
    var audioTrackIndex = -1

    fun inSegment(frameIndex: Int) = frameIndex >= segment.first && frameIndex <= segment.second

    fun inSegment(timeUs: Long) = timeUs in startTimeUs..endTimeUs

    fun addTrack(videoDecoderFormat: MediaFormat, audioDecoderFormat: MediaFormat?) {
        videoTrackIndex = muxer.addTrack(videoDecoderFormat)
        audioDecoderFormat?.let {
            audioTrackIndex = muxer.addTrack(it)
        }
    }

    fun writeVideoSampleData(frameIndex: Int, byteBuffer: ByteBuffer, bufferInfo: MediaCodec.BufferInfo) {
        if (startTimeUs == -1L) {
            println("mux video start -- frameIndex: $frameIndex, segmentIndex: $segmentIndex, segment: $segment")
            startTimeUs = bufferInfo.presentationTimeUs
        }
        endTimeUs = bufferInfo.presentationTimeUs
        muxer.writeSampleData(videoTrackIndex, byteBuffer, bufferInfo)
    }

    fun writeAudioSampleData(byteBuffer: ByteBuffer, bufferInfo: MediaCodec.BufferInfo) {
        muxer.writeSampleData(audioTrackIndex, byteBuffer, bufferInfo)
    }
}

/**
 * @author wulei
 */
@RequiresApi(Build.VERSION_CODES.M)
class SkeletonVideoExporter {

    companion object {

        private var skeletonVideoDir: File? = null
        private const val TAG = "SkeletonVideoExporter"

        private fun getSkeletonVideoDir(): File? {
            if (skeletonVideoDir == null) {
                val newPath = FileUtil.getAppStorageDirectory("skeletonVideo", true)
                skeletonVideoDir = File(newPath)
            }
            skeletonVideoDir?.mkdirs()
            return skeletonVideoDir
        }

        fun export(
            context: Context,
            uri: Uri,
            jointDetectionResult: JointDetectionResult,
            swingDetectionResult: SwingDetectionResult,
            progressHandler: ((swingIndex: Int, jointDetectionResult: JointDetectionResult, exportFile: String?) -> Unit)? = null
        ) {
            val path = uri.path
            checkNotNull(path) { "path should not be null" }
            Log.i(TAG, "export path: $path")
            var extractor = SkeletonMediaUtil.createMediaExtractor(context, uri)
            val videoInputTrack = SkeletonMediaUtil.getAndSelectVideoTrackIndex(extractor)
            if (videoInputTrack < 0) {
                throw VideoTrackNotFoundException()
            }
            val videoDecoderFormat = extractor.getTrackFormat(videoInputTrack)
            val width = videoDecoderFormat.getInteger(MediaFormat.KEY_WIDTH)
            val height = videoDecoderFormat.getInteger(MediaFormat.KEY_HEIGHT)
            val frameCount = if (videoDecoderFormat.containsKey("frame-count")) {
                videoDecoderFormat.getInteger("frame-count")
            } else {
                -1
            }
            val frameRate = videoDecoderFormat.getInteger(MediaFormat.KEY_FRAME_RATE)
            val duration = videoDecoderFormat.getLong(MediaFormat.KEY_DURATION)
            val rotation = if (videoDecoderFormat.containsKey(MediaFormat.KEY_ROTATION)) {
                videoDecoderFormat.getInteger(MediaFormat.KEY_ROTATION)
            } else {
                0
            }
            val bitRate = if (videoDecoderFormat.containsKey(MediaFormat.KEY_BIT_RATE)) {
                videoDecoderFormat.getInteger(MediaFormat.KEY_BIT_RATE)
            } else {
                0
            }

            val mime = videoDecoderFormat.getString(MediaFormat.KEY_MIME)!!
            Log.i(
                TAG,
                "mime: $mime, frameCount: $frameCount, width: $width, height: $height, frameRate: $frameRate, " +
                        "duration: $duration, rotation: $rotation, bitRate: $bitRate"
            )

            val videoEncoderFormat = MediaFormat.createVideoFormat(mime, width, height)
            // Set some properties. Failing to specify some of these can cause the MediaCodec
            // configure() call to throw an unhelpful exception.
            videoEncoderFormat.setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
            )
            videoEncoderFormat.setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
            videoEncoderFormat.setLong(MediaFormat.KEY_DURATION, duration)
            videoEncoderFormat.setInteger(MediaFormat.KEY_ROTATION, rotation)
//            videoEncoderFormat.setInteger(
//                MediaFormat.KEY_BITRATE_MODE,
//                MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CQ
//            )
            videoEncoderFormat.setInteger(
                MediaFormat.KEY_BIT_RATE,
                SkeletonMediaUtil.getVideoBitRate(width, height, frameRate, bitRate)
            )
            videoEncoderFormat.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 0)

            // add audio
            extractor = SkeletonMediaUtil.createMediaExtractor(context, uri)
            val audioInputTrack = SkeletonMediaUtil.getAndSelectAudioTrackIndex(extractor)
            val audioDecoderFormat: MediaFormat?
            if (audioInputTrack >= 0) {
//                audioDecoderFormat = audioExtractor.getTrackFormat(audioInputTrack)
                audioDecoderFormat = null
            } else {
                audioDecoderFormat = null
            }

            createMuxers(jointDetectionResult, swingDetectionResult).forEach { muxerWrapper ->
                try {
                    Log.i(TAG, "************** export video ${muxerWrapper.segmentIndex} start")
                    val videoExtractor = SkeletonMediaUtil.createMediaExtractor(context, uri)
                    videoExtractor.selectTrack(videoInputTrack)
                    muxVideo(
                        videoExtractor,
                        muxerWrapper,
                        videoDecoderFormat,
                        videoEncoderFormat,
                        audioDecoderFormat,
                        false
                    )
                    videoExtractor.release()

                    audioDecoderFormat?.let {
                        val audioExtractor = SkeletonMediaUtil.createMediaExtractor(context, uri)
                        audioExtractor.selectTrack(audioInputTrack)
                        muxAudio(audioExtractor, muxerWrapper, audioDecoderFormat)
                        audioExtractor.release()
                    }
                    muxerWrapper.muxer.stop()
                    muxerWrapper.muxer.release()
                    Log.i(TAG, "************** export video ${muxerWrapper.segmentIndex} end")
                    progressHandler?.invoke(
                        muxerWrapper.segmentIndex,
                        muxerWrapper.jointResult,
                        muxerWrapper.exportFile
                    )
                } catch (ignored: Exception) {
                    Log.i(TAG, "************** export video ${muxerWrapper.segmentIndex} failed， ignored: $ignored")
                    progressHandler?.invoke(muxerWrapper.segmentIndex, muxerWrapper.jointResult, null)
                }
            }
        }

        private fun createMuxers(
            jointDetectionResult: JointDetectionResult,
            swingDetectionResult: SwingDetectionResult
        ): List<MuxerWrapper> {
            val outputDir = getSkeletonVideoDir() ?: throw ExportPathException()
            val muxers = mutableListOf<MuxerWrapper>()
            var index = 0
            swingDetectionResult.detectedSwings.forEach { detectedSwing ->
                val outputFile = "${outputDir.absolutePath}/exported$index.mp4"//${SystemClock.uptimeMillis()}.mp4"
                val muxer = MediaMuxer(outputFile, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                val jointResult = jointDetectionResult.splitBy(detectedSwing, swingDetectionResult.scaled)
                muxers.add(
                    MuxerWrapper(
                        muxer, jointResult, outputFile, index,
                        Pair(detectedSwing.setupSegment.start, detectedSwing.followThroughSegment.end)
                    )
                )
                index++
            }
            return muxers
        }

        private fun muxAudio(
            extractor: MediaExtractor,
            muxerWrapper: MuxerWrapper,
            decoderFormat: MediaFormat
        ) {
            val maxInputSize = if (decoderFormat.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                decoderFormat.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
            } else {
                1024 * 1024
            }

            val buffer = ByteBuffer.allocate(maxInputSize)
            val bufferInfo = MediaCodec.BufferInfo()
            while (true) {
                val chunkSize = extractor.readSampleData(buffer, 0)
                if (chunkSize > 0) {
                    if (extractor.sampleTime > 0) {
                        bufferInfo.offset = 0
                        bufferInfo.presentationTimeUs = extractor.sampleTime
                        bufferInfo.flags = extractor.sampleFlags
                        bufferInfo.size = chunkSize
                        if (muxerWrapper.inSegment(bufferInfo.presentationTimeUs)) {
                            muxerWrapper.writeAudioSampleData(buffer, bufferInfo)
                        }
                    }
                    extractor.advance()
                } else {
                    break
                }
            }
        }

        private fun getAudioEncoderFormat(decoderFormat: MediaFormat): MediaFormat {
            val mime = decoderFormat.getString(MediaFormat.KEY_MIME)
            checkNotNull(mime) { "mime should not be null" }

            val sampleRateHz = decoderFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val channelCount = decoderFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            val aacProfile = if (decoderFormat.containsKey(MediaFormat.KEY_AAC_PROFILE)) {
                decoderFormat.getInteger(MediaFormat.KEY_AAC_PROFILE)
            } else {
                0
            }
            val bitRate = if (decoderFormat.containsKey(MediaFormat.KEY_BIT_RATE)) {
                decoderFormat.getInteger(MediaFormat.KEY_BIT_RATE)
            } else {
                0
            }

            Log.i(
                TAG,
                "mime: $mime, sampleRateHz: $sampleRateHz, channelCount: $channelCount, aacProfile: $aacProfile, " +
                        "bitRate: $bitRate"
            )

            val encoderFormat = MediaFormat.createAudioFormat(mime, sampleRateHz, channelCount)

            encoderFormat.setInteger(
                MediaFormat.KEY_AAC_PROFILE, if (aacProfile == 0) {
                    MediaCodecInfo.CodecProfileLevel.AACObjectHE
                } else {
                    aacProfile
                }
            )
            encoderFormat.setInteger(MediaFormat.KEY_BIT_RATE, getAudioBitRate(bitRate))
            return encoderFormat
        }

        private fun getAudioBitRate(bitRate: Int): Int {
            val value = 64 * 1024
            if (bitRate == 0 || bitRate > value) {
                return value
            }
            return bitRate
        }

        @Throws(VideoFormatNotSupportException::class)
        private fun muxVideo(
            extractor: MediaExtractor,
            muxerWrapper: MuxerWrapper,
            decoderFormat: MediaFormat,
            encoderFormat: MediaFormat,
            audioDecoderFormat: MediaFormat?,
            debugFrameIndex: Boolean = false
        ) {
            val width = encoderFormat.getInteger(MediaFormat.KEY_WIDTH)
            val height = encoderFormat.getInteger(MediaFormat.KEY_HEIGHT)
            val rotation = if (encoderFormat.containsKey(MediaFormat.KEY_ROTATION)) {
                encoderFormat.getInteger(MediaFormat.KEY_ROTATION)
            } else {
                0
            }
            val decodeMime = decoderFormat.getString(MediaFormat.KEY_MIME)!!
            val encodeMime = encoderFormat.getString(MediaFormat.KEY_MIME)!!
            val decoder = try {
                MediaCodec.createDecoderByType(decodeMime)
            } catch (e: Exception) {
                throw VideoFormatNotSupportException()
            }
            val encoder = try {
                MediaCodec.createEncoderByType(encodeMime)
            } catch (e: Exception) {
                throw VideoFormatNotSupportException()
            }

            encoder.configure(encoderFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            val surface = encoder.createInputSurface()
            encoder.start()
            val surfaceToConfig = if (debugFrameIndex) {
                null
            } else {
                surface
            }
            decoder.configure(decoderFormat, surfaceToConfig, null, 0)
            decoder.start()

            var decodeDone = false
            val bufferInfo = MediaCodec.BufferInfo()
            var encodeIndex = 0
            var decoderDequeOutputIndex = 0
            var renderedIndex = 0

            loop@ while (true) {
                if (!decodeDone) {
                    val decoderInputBufferIndex = decoder.dequeueInputBuffer(1000)
                    if (decoderInputBufferIndex >= 0) {
                        decoder.getInputBuffer(decoderInputBufferIndex)?.let { byteBuffer ->
                            val chunkSize = extractor.readSampleData(byteBuffer, 0)
                            if (chunkSize < 0) {
                                // end of stream
                                decoder.queueInputBuffer(
                                    decoderInputBufferIndex,
                                    0,
                                    0,
                                    0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                )
//                                println("queue input, end of stream")
                            } else {
//                                println("queue input, chunkSize: $chunkSize, sampleTime: ${extractor.sampleTime}, flags: ${extractor.sampleFlags}")
                                val sampleTime = extractor.sampleTime
                                val flags = extractor.sampleFlags
//                                    if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
//                                        MediaCodec.BUFFER_FLAG_KEY_FRAME
//                                    } else {
//                                        0
//                                    }
                                decoder.queueInputBuffer(
                                    decoderInputBufferIndex,
                                    0,
                                    chunkSize,
                                    sampleTime,
                                    flags
                                )
                                extractor.advance()
                            }
                        }
                    }

                    when (val decoderOutputBufferIndex = decoder.dequeueOutputBuffer(bufferInfo, 1000)) {
                        MediaCodec.INFO_TRY_AGAIN_LATER,
                        MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED,
                        MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        }
                        else -> {
                            check(decoderOutputBufferIndex >= 0)
//                            println("queue output, size: ${bufferInfo.size}, offset: ${bufferInfo.offset}, presentationTimeUs: ${bufferInfo.presentationTimeUs}, flags: ${bufferInfo.flags}")
                            val doRender = (bufferInfo.size != 0)
                            if (doRender) {
                                if (debugFrameIndex) {
                                    decoder.getOutputBuffer(decoderOutputBufferIndex)?.let { buffer ->
                                        val ba = ByteArray(buffer.remaining())
                                        buffer.get(ba)
                                        val yuvImage = YuvImage(ba, ImageFormat.NV21, width, height, null)
                                        val outputStream = ByteArrayOutputStream()
                                        yuvImage.compressToJpeg(Rect(0, 0, width, height), 80, outputStream)
                                        val outputBytes: ByteArray = outputStream.toByteArray()
                                        val bmp = BitmapFactory.decodeByteArray(outputBytes, 0, outputBytes.size)
                                        if (bmp != null) {
                                            val canvas = surface.lockCanvas(null)
                                            canvas.drawBitmap(bmp, 0F, 0F, null)
                                            val paint = Paint()
                                            paint.textSize = 32F
                                            canvas.drawText("$renderedIndex", 100F, 100F, paint)
                                            surface.unlockCanvasAndPost(canvas)
                                        }
                                        renderedIndex++
                                    }
                                }
                            }
                            decoderDequeOutputIndex++
                            decoder.releaseOutputBuffer(decoderOutputBufferIndex, doRender)
                            if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0 ||
                                decoderDequeOutputIndex > muxerWrapper.segment.second
                            ) {
                                encoder.signalEndOfInputStream()
                                decodeDone = true
                            }
                        }
                    }
                }

                when (val encoderOutputBufferIndex = encoder.dequeueOutputBuffer(bufferInfo, 1000)) {
                    MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    }
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        muxerWrapper.addTrack(encoder.outputFormat, audioDecoderFormat)
                        muxerWrapper.muxer.setOrientationHint(rotation)
                        muxerWrapper.muxer.start()
                    }
                    else -> {
                        check(encoderOutputBufferIndex >= 0)
//                        println("encode, size: ${bufferInfo.size}, offset: ${bufferInfo.offset}, presentationTimeUs: ${bufferInfo.presentationTimeUs}, flags: ${bufferInfo.flags}")
                        if (bufferInfo.size != 0 && (bufferInfo.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0)) {
                            encoder.getOutputBuffer(encoderOutputBufferIndex)?.let { buffer ->
                                if (muxerWrapper.inSegment(encodeIndex)) {
//                                    println("muxer encodeIndex: $encodeIndex")
                                    muxerWrapper.writeVideoSampleData(encodeIndex, buffer, bufferInfo)
                                }
                                encodeIndex++
                            }
                        }

                        encoder.releaseOutputBuffer(encoderOutputBufferIndex, false)
                        if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            break@loop
                        }
                    }
                }
            }
            decoder.stop()
            decoder.release()
            encoder.stop()
            encoder.release()
            Log.i(
                TAG,
                "muxVideo: decoderDequeOutputIndex: $decoderDequeOutputIndex, renderedIndex: $renderedIndex, encodedCount: $encodeIndex"
            )
        }
    }
}

