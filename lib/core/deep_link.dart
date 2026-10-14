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
  }
  if (target.origin != origin.origin ||
      target.userInfo.isNotEmpty ||
      target.toString().contains('\\')) {
    return null;
  }
  return '${target.path}${target.hasQuery ? '?${target.query}' : ''}${target.hasFragment ? '#${target.fragment}' : ''}';
}
