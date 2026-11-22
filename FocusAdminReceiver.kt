package com.focusguard.focusguard

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

/** Opt-in Uninstall Guard: while active, Android greys out Uninstall for this app. */
class FocusAdminReceiver : DeviceAdminReceiver() {
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence =
        "Disabling the Uninstall Guard removes protection for your study locks."
}
