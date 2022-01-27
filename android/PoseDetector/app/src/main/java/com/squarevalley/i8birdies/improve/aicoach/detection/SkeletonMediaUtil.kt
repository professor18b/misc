package com.squarevalley.i8birdies.improve.aicoach.detection

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri

/**
 * @author wulei
 */
object SkeletonMediaUtil {

    fun createMediaExtractor(context: Context, uri: Uri): MediaExtractor {
        val extractor = MediaExtractor()
        extractor.setDataSource(context, uri, null)
        return extractor
    }

    fun getVideoBitRate(width: Int, height: Int, frameRate: Int, bitRate: Int): Int {
        val pixels = width * height
//        val kbps = if (pixels >= 1920 * 1080) {
//            9984
//        } else if (pixels >= 1280 * 720) {
//            4992
//        } else if (pixels >= 960 * 540) {
//            2496
//        } else {
//            1856
//        }
//        val compressed = kbps * 1024
        val compressed = (width * height * frameRate * 0.3).toInt()
        if (bitRate in 1 until compressed) {
            return bitRate
        }
        return compressed
    }

    fun getAndSelectVideoTrackIndex(extractor: MediaExtractor): Int {
        for (index in 0 until extractor.trackCount) {
            if (isVideoFormat(extractor.getTrackFormat(index))) {
                extractor.selectTrack(index)
                return index
            }
        }
        return -1
    }

    fun getAndSelectAudioTrackIndex(extractor: MediaExtractor): Int {
        for (index in 0 until extractor.trackCount) {
            if (isAudioFormat(extractor.getTrackFormat(index))) {
                extractor.selectTrack(index)
                return index
            }
        }
        return -1
    }

    fun isVideoFormat(format: MediaFormat): Boolean {
        return getMimeTypeFor(format)?.startsWith("video/") ?: false
    }

    fun isAudioFormat(format: MediaFormat): Boolean {
        return getMimeTypeFor(format)?.startsWith("audio/") ?: false
    }

    fun getMimeTypeFor(format: MediaFormat): String? {
        return format.getString(MediaFormat.KEY_MIME)
    }
}
