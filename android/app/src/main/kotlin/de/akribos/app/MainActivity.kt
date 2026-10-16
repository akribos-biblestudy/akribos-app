package de.akribos.app

import android.content.pm.ApplicationInfo
import android.webkit.CookieManager
import android.webkit.WebStorage
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.URI

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "de.akribos.app/editor-session")
            .setMethodCallHandler { call, result ->
                if (call.method != "setSession") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val origin = call.argument<String>("origin")
                val session = call.argument<String>("session")
                val uri = try { origin?.let(::URI) } catch (_: Exception) { null }
                val debug = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
                val development = debug && uri?.host?.removeSurrounding("[", "]") in
                    listOf("localhost", "127.0.0.1", "::1", "10.0.2.2")
                if (uri == null || uri.host.isNullOrEmpty() || uri.rawUserInfo != null ||
                    uri.rawQuery != null || uri.rawFragment != null ||
                    (uri.rawPath.isNotEmpty() && uri.rawPath != "/") ||
                    (uri.scheme != "https" && !(development && uri.scheme == "http")) ||
                    (session != null && (session.isEmpty() || session.any {
                        it.code !in 0x21..0x7e || it in "\";,\\"
                    }))
                ) {
                    result.error("invalid_session", "Invalid editor session configuration.", null)
                    return@setMethodCallHandler
                }
                try {
                    val cookies = CookieManager.getInstance()
                    // No Domain or expiry: exact-host, session-only cookie. The
                    // encrypted Dart cookie jar remains the persistent authority.
                    cookies.removeAllCookies {
                        try {
                            WebStorage.getInstance().deleteAllData()
                            val cleaner = WebView(this)
                            cleaner.clearCache(true)
                            cleaner.clearHistory()
                            cleaner.destroy()
                            if (session == null) {
                                cookies.flush()
                                result.success(null)
                            } else {
                                val secure = if (uri.scheme == "https") "; Secure" else ""
                                cookies.setCookie(origin!!, "session=$session; Path=/; HttpOnly; SameSite=Lax$secure") { accepted ->
                                    try {
                                        if (accepted) {
                                            cookies.flush()
                                            result.success(null)
                                        } else {
                                            result.error("session_rejected", "Editor session was not accepted.", null)
                                        }
                                    } catch (_: Exception) {
                                        result.error("session_failed", "Editor session could not be prepared.", null)
                                    }
                                }
                            }
                        } catch (_: Exception) {
                            result.error("session_failed", "Editor session could not be prepared.", null)
                        }
                    }
                } catch (_: Exception) {
                    result.error("session_failed", "Editor session could not be prepared.", null)
                }
            }
    }
}
