package com.focusguard.focusguard

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack

/** Procedural brown noise (low-pass filtered integrated white noise). Zero audio assets. */
object BrownNoiseEngine {
    @Volatile private var running = false
    private var thread: Thread? = null

    fun start() {
        if (running) return
        running = true
        thread = Thread {
            val sr = 22050
            val buf = ShortArray(2048)
            val min = AudioTrack.getMinBufferSize(sr, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
            val track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sr)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build()
                )
                .setBufferSizeInBytes(maxOf(min, buf.size * 2))
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
            val rnd = java.util.Random()
            var last = 0.0
            var lp = 0.0
            track.play()
            while (running) {
                for (i in buf.indices) {
                    val white = rnd.nextDouble() * 2 - 1
                    last = (last + 0.02 * white) / 1.02
                    val s = last * 3.5
                    lp += 0.2 * (s - lp)
                    buf[i] = (lp.coerceIn(-1.0, 1.0) * 32767 * 0.35).toInt().toShort()
                }
                track.write(buf, 0, buf.size)
            }
            try { track.stop() } catch (e: Exception) {}
            track.release()
        }.also { it.isDaemon = true; it.start() }
    }

    fun stop() { running = false; thread = null }
}
