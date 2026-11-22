package com.focusguard.focusguard

import android.Manifest
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "focusguard/blocker")
            .setMethodCallHandler { call, result ->
                try { handle(call, result) } catch (e: Exception) { result.error("ERR", e.message, null) }
            }
    }

    private fun admin() = ComponentName(this, FocusAdminReceiver::class.java)

    @Suppress("DEPRECATION")
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "apps" -> {
                val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                val list = packageManager.queryIntentActivities(i, 0)
                    .map { mapOf("pkg" to it.activityInfo.packageName, "label" to it.loadLabel(packageManager).toString()) }
                    .filter { it["pkg"] != packageName }
                    .distinctBy { it["pkg"] }
                    .sortedBy { (it["label"] ?: "").lowercase() }
                result.success(list)
            }
            "startLock" -> {
                val ms = call.argument<Number>("ms")!!.toLong()
                val pkgs = call.argument<List<String>>("pkgs") ?: emptyList()
                val nuclear = call.argument<Boolean>("nuclear") ?: false
                LockStore.start(this, ms, pkgs, nuclear)
                val i = Intent(this, LockGuardService::class.java)
                if (Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
                result.success(true)
            }
            "clearLock" -> { LockStore.clear(this); stopService(Intent(this, LockGuardService::class.java)); result.success(true) }
            "lockStatus" -> {
                val r = LockStore.remaining(this)
                result.success(mapOf(
                    "active" to (r > 0), "remainingMs" to r,
                    "nuclear" to LockStore.nuclear(this),
                    "pkgs" to LockStore.packages(this).toList()
                ))
            }
            "isA11yEnabled" -> {
                val s = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
                result.success(s.contains(packageName) && s.contains("BlockerService"))
            }
            "openA11y" -> {
                startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(true)
            }
            "isAdminActive" -> {
                val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                result.success(dpm.isAdminActive(admin()))
            }
            "requestAdmin" -> {
                val i = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                    .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin())
                    .putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Prevents uninstalling FocusGuard while a study lock is active.")
                startActivity(i)
                result.success(true)
            }
            "removeAdmin" -> {
                if (LockStore.active(this)) { result.success(false) } else {
                    val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                    dpm.removeActiveAdmin(admin())
                    result.success(true)
                }
            }
            "keepScreenOn" -> {
                val on = call.argument<Boolean>("on") ?: false
                runOnUiThread {
                    if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                result.success(true)
            }
            "startNoise" -> { BrownNoiseEngine.start(); result.success(true) }
            "stopNoise" -> { BrownNoiseEngine.stop(); result.success(true) }
            "vibrate" -> {
                val p = (call.argument<List<Number>>("p") ?: listOf(0, 100)).map { it.toLong() }.toLongArray()
                val v = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                if (Build.VERSION.SDK_INT >= 26) {
                    v.vibrate(VibrationEffect.createWaveform(p, -1))
                } else {
                    v.vibrate(p, -1)
                }
                result.success(true)
            }
            "requestNotif" -> {
                if (Build.VERSION.SDK_INT >= 33 &&
                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 77)
                }
                result.success(true)
            }
            "setReminder" -> {
                val on = call.argument<Boolean>("on") ?: true
                val h = call.argument<Int>("h") ?: 9
                val m = call.argument<Int>("m") ?: 0
                getSharedPreferences(ReminderReceiver.MISC, Context.MODE_PRIVATE).edit()
                    .putBoolean("remOn", on).putInt("remH", h).putInt("remM", m).apply()
                if (on) ReminderReceiver.scheduleDaily(this, h, m) else ReminderReceiver.cancelDaily(this)
                result.success(true)
            }
            "setDueCount" -> {
                getSharedPreferences(ReminderReceiver.MISC, Context.MODE_PRIVATE).edit()
                    .putInt("due", call.argument<Int>("n") ?: 0).apply()
                result.success(true)
            }
            "scheduleSessionAlert" -> {
                ReminderReceiver.scheduleSessionAlert(this, call.argument<Number>("ms")!!.toLong())
                result.success(true)
            }
            "cancelSessionAlert" -> { ReminderReceiver.cancelSessionAlert(this); result.success(true) }
            else -> result.notImplemented()
        }
    }
}
