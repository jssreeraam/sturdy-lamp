package com.focusguard.focusguard

import android.content.Context
import android.os.SystemClock
import android.provider.Settings

/**
 * Lock state backed by the MONOTONIC clock (SystemClock.elapsedRealtime),
 * so changing Android Date & Time can never shorten or clear a lock.
 * Across a reboot the monotonic clock resets, so we re-anchor once from the
 * wall-clock end time that was saved when the lock began.
 */
object LockStore {
    private const val P = "focusguard_lock"
    private fun sp(c: Context) = c.getSharedPreferences(P, Context.MODE_PRIVATE)

    private fun bootCount(c: Context): Int = try {
        Settings.Global.getInt(c.contentResolver, Settings.Global.BOOT_COUNT)
    } catch (e: Exception) { -1 }

    /**
     * allow=false: [pkgs] are BLOCKED (Quick Strict Lock / penalty lock).
     * allow=true : ONLY [pkgs] (plus system essentials) may run (study timer whitelist).
     */
    fun start(c: Context, durationMs: Long, pkgs: Collection<String>, nuclear: Boolean, allow: Boolean = false) {
        val curRem = remaining(c)
        val sameMode = curRem > 0 && allowMode(c) == allow
        val now = SystemClock.elapsedRealtime()
        val dur = if (sameMode) maxOf(durationMs, curRem) else durationMs
        val merged = HashSet<String>(pkgs)
        if (sameMode) merged.addAll(packages(c))
        val nuc = nuclear || (sameMode && nuclear(c))
        sp(c).edit()
            .putLong("endElapsed", now + dur)
            .putLong("endWall", System.currentTimeMillis() + dur)
            .putInt("boot", bootCount(c))
            .putStringSet("pkgs", merged)
            .putBoolean("nuclear", nuc)
            .putBoolean("allow", allow)
            .apply()
    }

    fun clear(c: Context) {
        sp(c).edit().remove("endElapsed").remove("endWall").remove("boot")
            .remove("pkgs").remove("nuclear").remove("allow").apply()
    }

    /** Remaining lock time in ms (0 if none). */
    fun remaining(c: Context): Long {
        val s = sp(c)
        val end = s.getLong("endElapsed", 0L)
        if (end == 0L) return 0L
        val now = SystemClock.elapsedRealtime()
        val storedBoot = s.getInt("boot", -1)
        val curBoot = bootCount(c)
        val rebooted = storedBoot != -1 && curBoot != -1 && storedBoot != curBoot
        val rem: Long
        if (rebooted || end - now > 1000L * 60 * 60 * 24 * 40) {
            rem = s.getLong("endWall", 0L) - System.currentTimeMillis()
            if (rem > 0) {
                s.edit().putLong("endElapsed", now + rem).putInt("boot", curBoot).apply()
            }
        } else {
            rem = end - now
        }
        if (rem <= 0) { clear(c); return 0L }
        return rem
    }

    fun active(c: Context) = remaining(c) > 0
    fun packages(c: Context): Set<String> = sp(c).getStringSet("pkgs", emptySet()) ?: emptySet()
    fun nuclear(c: Context) = sp(c).getBoolean("nuclear", false)
    fun allowMode(c: Context) = sp(c).getBoolean("allow", false)
}
