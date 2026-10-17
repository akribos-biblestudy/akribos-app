package de.akribos.app

import com.google.android.play.core.install.model.InstallErrorCode
import com.google.android.play.core.install.model.UpdateAvailability

internal fun storeUpdateStatus(
    installedVersionCode: Long,
    availability: Int,
    availableVersionCode: Int,
): String = when (availability) {
    UpdateAvailability.UPDATE_AVAILABLE ->
        if (availableVersionCode.toLong() > installedVersionCode) "available" else "current"
    UpdateAvailability.UPDATE_NOT_AVAILABLE -> "current"
    else -> "unavailable"
}

internal fun storeCheckUnsupported(errorCode: Int?): Boolean = when (errorCode) {
    InstallErrorCode.ERROR_API_NOT_AVAILABLE,
    InstallErrorCode.ERROR_APP_NOT_OWNED,
    InstallErrorCode.ERROR_PLAY_STORE_NOT_FOUND,
    InstallErrorCode.ERROR_INSTALL_UNAVAILABLE -> true
    else -> false
}
