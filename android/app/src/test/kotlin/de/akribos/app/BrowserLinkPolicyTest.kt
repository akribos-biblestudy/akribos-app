package de.akribos.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BrowserLinkPolicyTest {
    private val ownPackage = "de.akribos.app"
    private val firstBrowser = BrowserActivity("browser.first", "Browser", true)
    private val defaultBrowser = BrowserActivity("browser.default", "Browser", true)

    @Test
    fun `exclude our app and domain handlers even when they are preferred`() {
        val candidates = listOf(
            BrowserActivity(ownPackage, "MainActivity", true),
            BrowserActivity("another.domain.app", "AppLink", false),
            firstBrowser,
        )
        assertEquals(listOf(firstBrowser), browserActivities(candidates, ownPackage, ownPackage))
        assertEquals(
            listOf(firstBrowser),
            browserActivities(candidates, ownPackage, "another.domain.app"),
        )
    }

    @Test
    fun `prefer default browser and retain only launchable fallback activities`() {
        val candidates = listOf(
            firstBrowser,
            firstBrowser.copy(activityName = "Disabled", enabled = false),
            firstBrowser.copy(activityName = "Private", exported = false),
            defaultBrowser,
            defaultBrowser,
        )
        assertEquals(
            listOf(defaultBrowser, firstBrowser),
            browserActivities(candidates, ownPackage, defaultBrowser.packageName),
        )
        assertEquals(
            listOf(firstBrowser, defaultBrowser),
            browserActivities(candidates, ownPackage, null),
        )
    }

    @Test
    fun `no browser yields no implicit app fallback`() {
        val candidates = listOf(BrowserActivity(ownPackage, "MainActivity", false))
        assertTrue(browserActivities(candidates, ownPackage, ownPackage).isEmpty())
    }

    @Test
    fun `accept public HTTPS paths fragments and custom server ports`() {
        for (value in listOf(
            "https://akribos.de/datenschutz#konto-loeschen",
            "https://akribos.de/impressum",
            "https://bible.example:8443/datenschutz?lang=de#konto-loeschen",
        )) assertTrue(value, isPublicBrowserUrl(value, false))
    }

    @Test
    fun `reject malformed URLs credentials unsafe schemes and release HTTP`() {
        for (value in listOf(
            null, "", "/datenschutz", "https:///datenschutz", "https:akribos.de",
            "javascript:alert(1)", "file:///private", "intent://akribos.de",
            "https://user:password@akribos.de/datenschutz", "https://@akribos.de",
            "https://akribos.de\\@other.example", "https://akribos.de/\nprivacy",
            "http://akribos.de/datenschutz", "http://localhost/datenschutz",
            "https://akribos.de:0/privacy", "https://akribos.de:65536/privacy",
        )) assertFalse(value, isPublicBrowserUrl(value, false))
    }

    @Test
    fun `development HTTP is restricted to local debug targets`() {
        for (host in listOf("localhost", "127.0.0.1", "[::1]", "10.0.2.2")) {
            val url = "http://$host:5173/datenschutz#konto-loeschen"
            assertTrue(url, isPublicBrowserUrl(url, true))
            assertFalse(url, isPublicBrowserUrl(url, false))
        }
        assertFalse(isPublicBrowserUrl("http://akribos.de/datenschutz", true))
        assertFalse(isPublicBrowserUrl("http://localhost.example/datenschutz", true))
    }
}
