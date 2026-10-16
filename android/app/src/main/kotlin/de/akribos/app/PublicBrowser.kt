package de.akribos.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri

internal class PublicBrowser(private val activity: Activity) {
    @Suppress("DEPRECATION") // The int flag overload also supports Android before API 33.
    fun open(value: String?): Boolean {
        val debug = (activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!isPublicBrowserUrl(value, debug)) return false

        // This URI is only an Intent-resolution pattern; it is never opened or fetched.
        // Resolving the actual operator URL can select our own verified App Link activity.
        val browserProbe = Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com/"))
            .addCategory(Intent.CATEGORY_BROWSABLE)
        val manager = activity.packageManager
        val candidates = try {
            val preferred = manager.resolveActivity(browserProbe, PackageManager.MATCH_DEFAULT_ONLY)
                ?.activityInfo?.packageName
            val matches = manager.queryIntentActivities(
                browserProbe,
                PackageManager.MATCH_DEFAULT_ONLY or PackageManager.GET_RESOLVED_FILTER,
            ).mapNotNull { match ->
                val info = match.activityInfo ?: return@mapNotNull null
                val filter = match.filter
                BrowserActivity(
                    packageName = info.packageName,
                    activityName = info.name,
                    handlesAllHttpsHosts = filter != null &&
                        filter.hasAction(Intent.ACTION_VIEW) &&
                        filter.hasCategory(Intent.CATEGORY_BROWSABLE) &&
                        filter.hasDataScheme("https") && filter.countDataAuthorities() == 0,
                    enabled = info.enabled && info.applicationInfo.enabled,
                    exported = info.exported,
                )
            }
            browserActivities(matches, activity.packageName, preferred)
        } catch (_: SecurityException) {
            return false
        }

        for (candidate in candidates) {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(value))
                .addCategory(Intent.CATEGORY_BROWSABLE)
                .setComponent(ComponentName(candidate.packageName, candidate.activityName))
            try {
                // An explicit browser component bypasses verified App Link dispatch.
                // The original path and fragment stay intact; no session is transferred.
                activity.startActivity(intent)
                return true
            } catch (_: ActivityNotFoundException) {
                // A browser may have been disabled or removed since resolution.
            } catch (_: SecurityException) {
                // Try the next independently resolved browser, never an implicit intent.
            }
        }
        return false
    }
}
