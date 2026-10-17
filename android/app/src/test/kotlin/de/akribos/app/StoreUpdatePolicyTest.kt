package de.akribos.app

import com.google.android.play.core.install.model.InstallErrorCode
import com.google.android.play.core.install.model.UpdateAvailability
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StoreUpdatePolicyTest {
    @Test
    fun `only advertise strictly newer versions that Play makes available`() {
        assertEquals("available", storeUpdateStatus(17L, UpdateAvailability.UPDATE_AVAILABLE, 18))
        assertEquals("current", storeUpdateStatus(17L, UpdateAvailability.UPDATE_AVAILABLE, 17))
        assertEquals("current", storeUpdateStatus(17L, UpdateAvailability.UPDATE_AVAILABLE, 16))
        assertEquals("current", storeUpdateStatus(17L, UpdateAvailability.UPDATE_NOT_AVAILABLE, 18))
        assertEquals("unavailable", storeUpdateStatus(
            17L, UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS, 18,
        ))
        assertEquals("current", storeUpdateStatus(
            Int.MAX_VALUE.toLong() + 1, UpdateAvailability.UPDATE_AVAILABLE, Int.MAX_VALUE,
        ))
    }

    @Test
    fun `unknown eligibility is not an up to date result`() {
        assertEquals("unavailable", storeUpdateStatus(17L, UpdateAvailability.UNKNOWN, 18))
        assertEquals("unavailable", storeUpdateStatus(17L, 999, 18))
    }

    @Test
    fun `unsupported installs differ from failed checks`() {
        for (code in listOf(
            InstallErrorCode.ERROR_API_NOT_AVAILABLE,
            InstallErrorCode.ERROR_APP_NOT_OWNED,
            InstallErrorCode.ERROR_PLAY_STORE_NOT_FOUND,
            InstallErrorCode.ERROR_INSTALL_UNAVAILABLE,
        )) assertTrue(storeCheckUnsupported(code))
        for (code in listOf(
            null,
            InstallErrorCode.ERROR_INTERNAL_ERROR,
            InstallErrorCode.ERROR_UNKNOWN,
            InstallErrorCode.ERROR_INVALID_REQUEST,
            InstallErrorCode.ERROR_INSTALL_NOT_ALLOWED,
        )) assertFalse(storeCheckUnsupported(code))
    }
}
