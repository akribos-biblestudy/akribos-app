/// App links select a route on the configured server; they never select a different server.
String? appLinkPath(Uri link, Uri origin) {
  Uri target;
  if (link.scheme == 'akribos' && link.host == 'open') {
    final path = link.queryParameters['path'];
    if (path == null ||
        !path.startsWith('/') ||
        path.startsWith('//') ||
        path.contains('\\')) {
      return null;
    }
    target = origin.resolve(path);
  } else {
    if (!['https', 'http'].contains(link.scheme)) return null;
    target = link;
    // Android verifies both web schemes. Open a plain HTTP link on the same
    // canonical HTTPS origin; never send API requests or cookies over HTTP.
    if (link.scheme == 'http' &&
        link.port == 80 &&
        origin.scheme == 'https' &&
        origin.port == 443 &&
        link.host == origin.host) {
      target = link.replace(scheme: 'https', port: 443);
    }
  }
  if (target.origin != origin.origin ||
      target.userInfo.isNotEmpty ||
      target.toString().contains('\\')) {
    return null;
  }
  return '${target.path.isEmpty ? '/' : target.path}${target.hasQuery ? '?${target.query}' : ''}${target.hasFragment ? '#${target.fragment}' : ''}';
}
