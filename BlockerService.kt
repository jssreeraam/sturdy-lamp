package com.focusguard.focusguard

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class BlockerService : AccessibilityService() {
    private var lastKick = 0L

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
        "clear storage", "clear data"
    )

    override fun onAccessibilityEvent(e: AccessibilityEvent?) {
        if (e == null) return
        val t = e.eventType
        if (t != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            t != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) return
        val pkg = e.packageName?.toString() ?: return
        if (pkg == packageName) return
        if (LockStore.remaining(this) <= 0) return

        if (LockStore.packages(this).contains(pkg)) { kick(); return }

        if (guarded.contains(pkg)) {
            if (LockStore.nuclear(this)) { kick(); return }
            val root = rootInActiveWindow ?: return
            val sb = StringBuilder()
            collect(root, sb, 0)
            val text = sb.toString().lowercase()
            if (keywords.any { text.contains(it) }) kick()
        }
    }

    private fun collect(n: AccessibilityNodeInfo?, sb: StringBuilder, depth: Int) {
        if (n == null || depth > 14) return
        n.text?.let { sb.append(it).append(' ') }
        n.contentDescription?.let { sb.append(it).append(' ') }
        for (i in 0 until n.childCount) collect(n.getChild(i), sb, depth + 1)
    }

    private fun kick() {
        val now = System.currentTimeMillis()
        if (now - lastKick < 400) return
        lastKick = now
        performGlobalAction(GLOBAL_ACTION_HOME)
    }

    override fun onInterrupt() {}
}
