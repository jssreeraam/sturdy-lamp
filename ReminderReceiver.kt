package com.focusguard.focusguard

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Notification
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import java.util.Calendar

class ReminderReceiver : BroadcastReceiver() {
    companion object {
        const val A_DAILY = "com.focusguard.focusguard.DAILY"
        const val A_DONE = "com.focusguard.focusguard.SESSION_DONE"
        const val CH = "focusguard_reminders"
        const val MISC = "focusguard_misc"

        private fun pi(c: Context, action: String, code: Int) = PendingIntent.getBroadcast(
            c, code, Intent(c, ReminderReceiver::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        private fun am(c: Context) = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        fun scheduleDaily(c: Context, h: Int, m: Int) {
            val cal = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, h); set(Calendar.MINUTE, m)
                set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
                if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
            }
            am(c).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.timeInMillis, pi(c, A_DAILY, 1))
        }

        fun cancelDaily(c: Context) = am(c).cancel(pi(c, A_DAILY, 1))

        fun scheduleSessionAlert(c: Context, delayMs: Long) {
            am(c).setAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + delayMs, pi(c, A_DONE, 2)
            )
        }

        fun cancelSessionAlert(c: Context) = am(c).cancel(pi(c, A_DONE, 2))

        fun notify(c: Context, id: Int, title: String, text: String) {
            val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= 26) {
                nm.createNotificationChannel(NotificationChannel(CH, "Reminders", NotificationManager.IMPORTANCE_DEFAULT))
            }
            val open = PendingIntent.getActivity(
                c, 0, Intent(c, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, CH) else Notification.Builder(c)
            val n = b.setContentTitle(title).setContentText(text)
                .setSmallIcon(c.applicationInfo.icon)
                .setAutoCancel(true).setContentIntent(open).build()
            try { nm.notify(id, n) } catch (e: Exception) {}
        }
    }

    override fun onReceive(c: Context, intent: Intent) {
        when (intent.action) {
            A_DAILY -> {
                val sp = c.getSharedPreferences(MISC, Context.MODE_PRIVATE)
                val due = sp.getInt("due", 0)
                if (sp.getBoolean("remOn", true)) {
                    if (due > 0) notify(c, 2001, "Revision time", "$due topics are due today. Clear them before they pile up.")
                    else notify(c, 2001, "FocusGuard", "No revisions due. A focused block today keeps the streak alive.")
                    scheduleDaily(c, sp.getInt("remH", 9), sp.getInt("remM", 0))
                }
            }
            A_DONE -> notify(c, 2002, "Study block complete", "Open FocusGuard to log what you covered.")
        }
    }
}
