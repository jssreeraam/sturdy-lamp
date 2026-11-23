package com.focusguard.focusguard

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.telecom.TelecomManager
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.inputmethod.InputMethodManager
import android.widget.TextView

class BlockerService : AccessibilityService() {
    private var lastKick = 0L
    private val handler = Handler(Looper.getMainLooper())
    private var overlay: View? = null
    private var essentialsAt = 0L
    private var essentialsSet: Set<String> = emptySet()

    private val guarded = setOf(
        "com.android.settings",
        "com.google.android.packageinstaller",
        "com.android.packageinstaller",
        "com.samsung.android.packageinstaller",
        "com.google.android.permissioncontroller",
        "com.miui.securitycenter",
        "com.miui.packageinstaller"
    )

    private val keywords = listOf(
        "focusguard", "accessibility", "device admin", "device administrator",
        "uninstall", "force stop", "date & time", "date and time",
        "clear storage", "clear data", "display over other apps", "draw over other apps"
    )

    /** Things that must always stay usable in whitelist mode: launcher, keyboard, dialer, system UI. */
    private fun essentials(): Set<String> {
        val now = System.currentTimeMillis()
        if (now - essentialsAt < 30000 && essentialsSet.isNotEmpty()) return essentialsSet
        val s = HashSet<String>()
        s.addAll(listOf(
            "android", "com.android.systemui",
            "com.google.android.dialer", "com.android.dialer", "com.android.incallui",
            "com.samsung.android.incallui", "com.samsung.android.dialer",
            "com.android.server.telecom", "com.google.android.gms"
        ))
        try {
            packageManager.queryIntentActivities(
                Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), 0
            ).forEach { s.add(it.activityInfo.packageName) }
        } catch (e: Exception) {}
        try {
            (getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
                .enabledInputMethodList.forEach { s.add(it.packageName) }
        } catch (e: Exception) {}
        try {
            (getSystemService(Context.TELECOM_SERVICE) as TelecomManager)
                .defaultDialerPackage?.let { s.add(it) }
        } catch (e: Exception) {}
        essentialsSet = s
        essentialsAt = now
        return s
    }

    override fun onAccessibilityEvent(e: AccessibilityEvent?) {
        if (e == null) return
        val t = e.eventType
        val pkg = e.packageName?.toString() ?: return
        if (pkg == packageName) return
        if (LockStore.remaining(this) <= 0) return

        // ---- WHITELIST MODE (study timer): only allowed apps + essentials ----
        if (LockStore.allowMode(this)) {
            if (t != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
            if (LockStore.packages(this).contains(pkg)) return
            if (essentials().contains(pkg)) return
            block(true)
            return
        }

        // ---- BLACKLIST MODE (Quick Strict Lock / penalty lock) ----
        if (t != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            t != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) return
        if (LockStore.packages(this).contains(pkg)) { block(false); return }
        if (guarded.contains(pkg)) {
            if (LockStore.nuclear(this)) { block(false); return }
            val root = rootInActiveWindow ?: return
            val sb = StringBuilder()
            collect(root, sb, 0)
            val text = sb.toString().lowercase()
            if (keywords.any { text.contains(it) }) block(false)
        }
    }

    private fun collect(n: AccessibilityNodeInfo?, sb: StringBuilder, depth: Int) {
        if (n == null || depth > 14) return
        n.text?.let { sb.append(it).append(' ') }
        n.contentDescription?.let { sb.append(it).append(' ') }
        for (i in 0 until n.childCount) collect(n.getChild(i), sb, depth + 1)
    }

    private fun block(whitelist: Boolean) {
        val now = System.currentTimeMillis()
        if (now - lastKick < 400) return
        lastKick = now
        showOverlay(whitelist)
        performGlobalAction(GLOBAL_ACTION_HOME)
    }

    /** Full-screen "locked" cover. Uses the Display-over-other-apps permission when granted. */
    private fun showOverlay(whitelist: Boolean) {
        if (overlay != null) return
        try {
            val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val type = if (Build.VERSION.SDK_INT >= 26 && Settings.canDrawOverlays(this))
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
            val mins = (LockStore.remaining(this) / 60000L) + 1
            val tv = TextView(this).apply {
                text = (if (whitelist) "🔒 Study lock\n\nOnly your allowed study apps work right now."
                        else "🔒 Locked by FocusGuard\n\nThis app is blocked right now.") +
                        "\n\n$mins min remaining"
                setTextColor(Color.WHITE)
                textSize = 22f
                gravity = Gravity.CENTER
                setBackgroundColor(Color.parseColor("#F22B3544"))
                setPadding(60, 60, 60, 60)
            }
            val lp = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            )
            wm.addView(tv, lp)
            overlay = tv
            handler.postDelayed({ removeOverlay() }, 1800)
        } catch (e: Exception) {
            overlay = null
        }
    }

    private fun removeOverlay() {
        val v = overlay ?: return
        try {
            (getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(v)
        } catch (e: Exception) {}
        overlay = null
    }

    override fun onDestroy() { removeOverlay(); super.onDestroy() }
    override fun onInterrupt() {}
}
