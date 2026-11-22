package com.focusguard.focusguard

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

class LockGuardService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val nid = 4101
    private val channel = "focusguard_lock"

    private val tick = object : Runnable {
        override fun run() {
            val r = LockStore.remaining(this@LockGuardService)
            if (r <= 0) {
                stopForeground(true)
                stopSelf()
                return
            }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .notify(nid, build(r))
            handler.postDelayed(this, 15000)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createChannel()
        val r = LockStore.remaining(this)
        if (r <= 0) { stopSelf(); return START_NOT_STICKY }
        val n = build(r)
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(nid, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(nid, n)
        }
        handler.removeCallbacks(tick)
        handler.postDelayed(tick, 15000)
        return START_STICKY
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel(channel, "Study lock", NotificationManager.IMPORTANCE_LOW)
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(ch)
        }
    }

    private fun build(remMs: Long): Notification {
        val s = remMs / 1000
        val txt = String.format("%dh %02dm remaining", s / 3600, (s % 3600) / 60)
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channel) else Notification.Builder(this)
        return b.setContentTitle("FocusGuard lock active")
            .setContentText(txt)
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setOngoing(true)
            .setContentIntent(pi)
            .build()
    }

    override fun onDestroy() { handler.removeCallbacks(tick); super.onDestroy() }
    override fun onBind(intent: Intent?): IBinder? = null
}
