# FocusGuard (NEET PG / INI-CET)

Offline-first Flutter + Kotlin study guardian. No INTERNET permission. Built entirely by GitHub Actions.

## Build the APK (no PC needed)
1. Create a new GitHub repo and upload everything in this folder (keep the `.github` folder).
2. Push to `main`, or open Actions -> "Build FocusGuard APK" -> Run workflow.
3. When it finishes, download the `FocusGuard-APKs` artifact. Install `app-arm64-v8a-release.apk` on most phones.

## First-run setup on the phone
1. Rules tab -> Enable the Accessibility blocker (needed for locks to close apps).
   On Android 13+ you may first need App info -> three dots -> "Allow restricted settings".
2. Rules tab -> pick distraction apps, set a Guardian PIN (give it to Mom/Dad), optionally enable Uninstall Guard.
3. Study tab -> tap the INI-CET / NEET PG tiles to set your real exam dates (defaults are placeholders).
4. Rules tab -> Goals: adjust Duty Day / Off Day hours.

## Layout
- `lib/` Flutter UI, SQLite store, spaced repetition, stats, ML Kit camera proctor
- `android/app/src/main/kotlin/.../` LockStore, BlockerService, FocusAdminReceiver, LockGuardService, BootReceiver, ReminderReceiver, BrownNoiseEngine, MainActivity
- `.github/workflows/build-apk.yml` CI build
