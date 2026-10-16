import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';

/// Open public operator information without handing a verified link back to us.
/// This browser receives no native account session or additional request headers.
Future<void> openOperatorPage(Uri uri) async {
  var opened = false;
  if (['https', 'http'].contains(uri.scheme) &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.toString().contains('\\')) {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        opened =
            await const MethodChannel('de.akribos.app/browser')
                .invokeMethod<bool>('open', {'url': uri.toString()}) ??
            false;
      } else {
        opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }
    } catch (_) {
      // Show the same actionable fallback for unavailable browsers and errors.
    }
  }
  if (!opened) {
    throw ApiException(
      'Die Betreiberseite konnte nicht geöffnet werden. Öffne $uri in deinem Browser.',
    );
  }
}
