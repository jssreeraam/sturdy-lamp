package com.focusguard.focusguard

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/** Restores locks and reminders after reboot. TIME_SET / TIMEZONE_CHANGED are deliberately ignored. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, intent: Intent) {
        val a = intent.action
        if (a != Intent.ACTION_BOOT_COMPLETED && a != "android.intent.action.QUICKBOOT_POWERON") return
        if (LockStore.remaining(c) > 0) {
            val i = Intent(c, LockGuardService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(i) else c.startService(i)
            } catch (e: Exception) {}
        }
        val sp = c.getSharedPreferences(ReminderReceiver.MISC, Context.MODE_PRIVATE)
        if (sp.getBoolean("remOn", true)) {
            ReminderReceiver.scheduleDaily(c, sp.getInt("remH", 9), sp.getInt("remM", 0))
        }
    }
}
