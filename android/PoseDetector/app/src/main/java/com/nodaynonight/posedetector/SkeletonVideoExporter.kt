package com.nodaynonight.posedetector

import android.content.Context
import android.media.*
import android.net.Uri
import android.os.Build
import android.os.Environment
import androidx.annotation.RequiresApi
import java.nio.ByteBuffer


abstract class ExportException(message: String) : Exception(message)

class VideoTrackNotFoundException : ExportException("video track not found")
class VideoFormatNotSupportException : ExportException("video format not support")
class ExportPathException() : ExportException("export path error")

/**
 * @author wulei
 */
@RequiresApi(Build.VERSION_CODES.M)
class SkeletonVideoExporter {
    companion object {
        fun export(context: Context, uri: Uri) {
            val path = uri.path
            checkNotNull(path) { "path should not be null" }
            println("export path: $path")
            val videoExtractor = createMediaExtractor(context, uri)
            val videoInputTrack = getAndSelectVideoTrackIndex(videoExtractor)
            if (videoInputTrack < 0) {
                throw VideoTrackNotFoundException()
            }
            val videoDecoderFormat = videoExtractor.getTrackFormat(videoInputTrack)

            val outputDir = context.getExternalFilesDir(Environment.DIRECTORY_MOVIES) ?: throw ExportPathException()
            val outputFile = "${outputDir.absolutePath}/exported1.mp4"//${SystemClock.uptimeMillis()}.mp4"
            val muxer = MediaMuxer(outputFile, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val videoTrackIndex = muxer.addTrack(videoDecoderFormat)

            // add audio
            val audioExtractor = createMediaExtractor(context, uri)
            val audioInputTrack = getAndSelectAudioTrackIndex(audioExtractor)
            var audioDecoderFormat: MediaFormat? = null
            var audioTrackIndex = -1
            if (audioInputTrack >= 0) {
                audioDecoderFormat = audioExtractor.getTrackFormat(audioInputTrack)
                audioTrackIndex = muxer.addTrack(audioDecoderFormat)
            }

            muxer.start()
            muxVideo(videoTrackIndex, muxer, videoExtractor, videoDecoderFormat)
            videoExtractor.release()
            println("************** export video finished")
            if (audioDecoderFormat != null) {
                muxAudio(audioTrackIndex, muxer, audioExtractor, audioDecoderFormat)
                audioExtractor.release()
                println("************** export audio finished")
            }
            muxer.stop()
            muxer.release()

            println("************** export finished")
        }

        private fun createMediaExtractor(context: Context, uri: Uri): MediaExtractor {
            val extractor = MediaExtractor()
            extractor.setDataSource(context, uri, null)
            return extractor
        }

        private fun muxAudio(
            trackIndex: Int,
            muxer: MediaMuxer,
            extractor: MediaExtractor,
            decoderFormat: MediaFormat
        ) {
            val mime = decoderFormat.getString(MediaFormat.KEY_MIME)!!
            println("mime: $mime")
            val maxInputSize = if (decoderFormat.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                decoderFormat.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
            } else {
                1024 * 1024
            }
            println("maxInputSize: $maxInputSize")
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
                        muxer.writeSampleData(trackIndex, buffer, bufferInfo)
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

            println(
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
            trackIndex: Int,
            muxer: MediaMuxer,
            extractor: MediaExtractor,
            decoderFormat: MediaFormat
        ) {
            val mime = decoderFormat.getString(MediaFormat.KEY_MIME)!!

            val decoder = try {
                MediaCodec.createDecoderByType(mime)
            } catch (e: Exception) {
                throw VideoFormatNotSupportException()
            }
            val encoder = try {
                MediaCodec.createEncoderByType(mime)
            } catch (e: Exception) {
                throw VideoFormatNotSupportException()
            }

            val width = decoderFormat.getInteger(MediaFormat.KEY_WIDTH)
            val height = decoderFormat.getInteger(MediaFormat.KEY_HEIGHT)
            val frameCount = if (decoderFormat.containsKey("frame-count")) {
                decoderFormat.getInteger("frame-count")
            } else {
                -1
            }
            val frameRate = decoderFormat.getInteger(MediaFormat.KEY_FRAME_RATE)
            val duration = decoderFormat.getLong(MediaFormat.KEY_DURATION)
            val rotation = if (decoderFormat.containsKey(MediaFormat.KEY_ROTATION)) {
                decoderFormat.getInteger(MediaFormat.KEY_ROTATION)
            } else {
                0
            }
            val bitRate = if (decoderFormat.containsKey(MediaFormat.KEY_BIT_RATE)) {
                decoderFormat.getInteger(MediaFormat.KEY_BIT_RATE)
            } else {
                0
            }
            val colorFormat = if (decoderFormat.containsKey(MediaFormat.KEY_COLOR_FORMAT)) {
                decoderFormat.getInteger(MediaFormat.KEY_COLOR_FORMAT)
            } else {
                0
            }

            println(
                "mime: $mime, frameCount: $frameCount, width: $width, height: $height, frameRate: $frameRate, " +
                        "duration: $duration, rotation: $rotation, bitRate: $bitRate, colorFormat: $colorFormat"
            )

            val encoderFormat = MediaFormat.createVideoFormat(mime, width, height)

            // Set some properties. Failing to specify some of these can cause the MediaCodec
            // configure() call to throw an unhelpful exception.
            encoderFormat.setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
            )
            encoderFormat.setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
            encoderFormat.setLong(MediaFormat.KEY_DURATION, duration)
            encoderFormat.setInteger(MediaFormat.KEY_ROTATION, rotation)
            encoderFormat.setInteger(MediaFormat.KEY_BIT_RATE, getVideoBitRate(width, height, bitRate))
            encoderFormat.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)

            encoder.configure(encoderFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            val encoderInputSurface = encoder.createInputSurface()
            decoder.configure(decoderFormat, encoderInputSurface, null, 0)

            decoder.start()
            encoder.start()

            val outBufferInfo = MediaCodec.BufferInfo()
            var outCount = 0
            var renderImageCount = 0

            while (true) {
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
                        } else {
                            val sampleTime = extractor.sampleTime
                            val flags =
                                if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
                                    MediaCodec.BUFFER_FLAG_KEY_FRAME
                                } else {
                                    0
                                }
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

                when (val decoderOutputBufferIndex = decoder.dequeueOutputBuffer(outBufferInfo, 1000)) {
                    MediaCodec.INFO_TRY_AGAIN_LATER -> {
                        // no output available yet
                        //                                println("INFO_TRY_AGAIN_LATER")
                    }
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        //                                println("INFO_OUTPUT_FORMAT_CHANGED")
                    }
                    else -> {
                        check(decoderOutputBufferIndex >= 0)
                        val doRender = (outBufferInfo.size != 0)
                        if (doRender) {
                            decoder.getOutputBuffer(decoderOutputBufferIndex)?.let { buffer ->
                                val joints =
                                    JointDetectionManager.INSTANCE.detect(
                                        buffer,
                                        width,
                                        height,
                                        rotation,
                                        colorFormat
                                    )
                                println("joints: ${joints.getValidJointCount()}")
                                renderImageCount++
                            }
                        }
                        decoder.releaseOutputBuffer(decoderOutputBufferIndex, doRender)

                        if ((outBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            encoder.signalEndOfInputStream()
                        }
                        outCount++
                    }
                }

                val encoderOutputBufferIndex = encoder.dequeueOutputBuffer(outBufferInfo, 1000)
                if (encoderOutputBufferIndex == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    // no output available yet
//                                println("INFO_TRY_AGAIN_LATER")
                } else if (encoderOutputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
//                                println("INFO_OUTPUT_FORMAT_CHANGED")
                } else {
                    check(encoderOutputBufferIndex >= 0)
                    if (outBufferInfo.size != 0) {
                        encoder.getOutputBuffer(encoderOutputBufferIndex)?.let { buffer ->
                            muxer.writeSampleData(trackIndex, buffer, outBufferInfo)
                        }
                    }

                    encoder.releaseOutputBuffer(encoderOutputBufferIndex, false)
                    if ((outBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        break
                    }
                }
            }
            encoderInputSurface.release()
            encoder.stop()
            decoder.stop()
            println("frameCount: $frameCount, outCount: $outCount, renderImageCount: $renderImageCount")
        }

        private fun getVideoBitRate(width: Int, height: Int, bitRate: Int): Int {
            val pixels = width * height
            val kbps = if (pixels >= 1920 * 1080) {
                4992
            } else if (pixels >= 1280 * 720) {
                2496
            } else if (pixels >= 960 * 540) {
                1856
            } else {
                1216
            }
            val compressed = kbps * 1024
            if (bitRate in 1 until compressed) {
                return bitRate
            }
            return compressed
        }

        private fun getAndSelectVideoTrackIndex(extractor: MediaExtractor): Int {
            for (index in 0 until extractor.trackCount) {
                if (isVideoFormat(extractor.getTrackFormat(index))) {
                    extractor.selectTrack(index)
                    return index
                }
            }
            return -1
        }

        private fun getAndSelectAudioTrackIndex(extractor: MediaExtractor): Int {
            for (index in 0 until extractor.trackCount) {
                if (isAudioFormat(extractor.getTrackFormat(index))) {
                    extractor.selectTrack(index)
                    return index
                }
            }
            return -1
        }

        private fun isVideoFormat(format: MediaFormat): Boolean {
            return getMimeTypeFor(format)?.startsWith("video/") ?: false
        }

        private fun isAudioFormat(format: MediaFormat): Boolean {
            return getMimeTypeFor(format)?.startsWith("audio/") ?: false
        }

        private fun getMimeTypeFor(format: MediaFormat): String? {
            return format.getString(MediaFormat.KEY_MIME)
        }
    }
}
