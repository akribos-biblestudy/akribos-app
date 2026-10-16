package de.akribos.app

import java.net.URI

internal data class BrowserActivity(
    val packageName: String,
    val activityName: String,
    val handlesAllHttpsHosts: Boolean,
    val enabled: Boolean = true,
    val exported: Boolean = true,
)

internal fun browserActivities(
    candidates: List<BrowserActivity>,
    ownPackage: String,
    preferredPackage: String?,
): List<BrowserActivity> = candidates
    .filter {
        it.packageName != ownPackage && it.handlesAllHttpsHosts && it.enabled && it.exported
    }
    .distinctBy { it.packageName to it.activityName }
    .sortedBy { if (it.packageName == preferredPackage) 0 else 1 }

internal fun isPublicBrowserUrl(value: String?, debug: Boolean): Boolean {
    if (value.isNullOrEmpty() || value.any { it == '\\' || it.isISOControl() }) return false
    val uri = try { URI(value) } catch (_: Exception) { return false }
    if (uri.isOpaque || uri.host.isNullOrEmpty() || uri.rawUserInfo != null ||
        (uri.port != -1 && uri.port !in 1..65535)
    ) return false
    val development = debug && uri.host.removeSurrounding("[", "]") in
        listOf("localhost", "127.0.0.1", "::1", "10.0.2.2")
    return uri.scheme == "https" || (development && uri.scheme == "http")
}
