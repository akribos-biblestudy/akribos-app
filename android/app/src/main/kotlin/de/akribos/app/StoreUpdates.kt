package de.akribos.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageInfo
import android.net.Uri
import android.os.Build
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.install.InstallException
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.plugin.common.MethodChannel

internal class StoreUpdates(private val activity: Activity) {
    @Suppress("DEPRECATION") // Keep the int overload for Android before API 33.
    private fun installedPackage(): PackageInfo =
        activity.packageManager.getPackageInfo(activity.packageName, 0)

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
        else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun installedFromPlay(): Boolean? = try {
        val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.packageManager.getInstallSourceInfo(activity.packageName).installingPackageName
        } else {
            activity.packageManager.getInstallerPackageName(activity.packageName)
        }
        installer == "com.android.vending"
    } catch (_: Exception) {
        // Installer metadata must not hide the independently readable app version.
        null
    }

    fun info(result: MethodChannel.Result) {
        try {
            val info = installedPackage()
            val version = info.versionName?.takeIf { it.isNotBlank() }
            if (version == null) {
                result.error("package_info", "Installed app version is missing.", null)
                return
            }
            val response = mutableMapOf<String, Any>(
                "version" to version,
                "build" to versionCode(info).toString(),
                "packageName" to activity.packageName,
                "platform" to "android",
            )
            installedFromPlay()?.let { response["storeInstallation"] = it }
            result.success(response)
        } catch (_: Exception) {
            result.error("package_info", "Installed app information is unavailable.", null)
        }
    }

    fun check(result: MethodChannel.Result) {
        try {
            // Direct APKs and other stores cannot use this Play account's update eligibility.
            if (installedFromPlay() == false) {
                result.success(mapOf("status" to "unavailable"))
                return
            }
            val installed = versionCode(installedPackage())
            val manager = AppUpdateManagerFactory.create(activity.applicationContext)
            manager.appUpdateInfo
                .addOnSuccessListener { info ->
                    val availability = info.updateAvailability()
                    // The API defines availableVersionCode only for UPDATE_AVAILABLE.
                    val available = if (availability == UpdateAvailability.UPDATE_AVAILABLE) {
                        info.availableVersionCode()
                    } else -1
                    val status = storeUpdateStatus(
                        installed,
                        availability,
                        available,
                    )
                    val response = mutableMapOf("status" to status)
                    if (status == "available") {
                        response["build"] = available.toString()
                    }
                    result.success(response)
                }
                .addOnFailureListener { error ->
                    val code = (error as? InstallException)?.errorCode
                    if (storeCheckUnsupported(code)) {
                        result.success(mapOf("status" to "unavailable"))
                    } else {
                        // A failed check must never be presented as an up-to-date installation.
                        result.error("store_check", "Google Play could not check for updates.", code)
                    }
                }
        } catch (_: Exception) {
            result.error("store_check", "Google Play could not check for updates.", null)
        }
    }

    fun openStore(): Boolean {
        val url = "https://play.google.com/store/apps/details?id=${activity.packageName}"
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            .addCategory(Intent.CATEGORY_BROWSABLE)
            .setPackage("com.android.vending")
        try {
            activity.startActivity(intent)
            return true
        } catch (_: ActivityNotFoundException) {
            // Opening the fixed public listing in an explicit browser is still useful.
        } catch (_: SecurityException) {
            // Never fall back to an arbitrary app-link handler.
        }
        return PublicBrowser(activity).open(url)
    }
}
