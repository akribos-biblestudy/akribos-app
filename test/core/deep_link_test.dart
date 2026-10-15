import 'package:akribos_app/core/deep_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final origin = Uri.parse('https://akribos.de');

  test('verified HTTPS links keep repeated reader parameters and fragments', () {
    const path =
        '/Joh3,16?layout=columns-2&tab=1.1:LUT:A:Joh3,16&tab=2.1:ELB:B:Ro8,1&active=1.1&active=2.1&focus=1#v16';
    expect(appLinkPath(Uri.parse('https://akribos.de$path'), origin), path);
    expect(appLinkPath(origin, origin), '/');
  });

  test(
    'HTTP incoming links are upgraded only for the same canonical HTTPS host',
    () {
      expect(
        appLinkPath(Uri.parse('http://akribos.de/Joh3,16?q=Liebe'), origin),
        '/Joh3,16?q=Liebe',
      );
      expect(
        appLinkPath(Uri.parse('http://akribos.de:80/notes'), origin),
        '/notes',
      );
      for (final value in [
        'http://evil.test/Joh3,16',
        'http://akribos.de:8080/Joh3,16',
        'https://akribos.de:444/Joh3,16',
        'https://akribos.de.evil.test/Joh3,16',
        'https://user:secret@akribos.de/Joh3,16',
        'http://user:secret@akribos.de/Joh3,16',
        'file:///Joh3,16',
      ]) {
        expect(appLinkPath(Uri.parse(value), origin), isNull);
      }
    },
  );

  test('custom links remain confined to the configured server', () {
    expect(
      appLinkPath(
        Uri.parse('akribos://open?path=%2Fworkspaces%2Fexample%3Ffrom%3Dlink'),
        origin,
      ),
      '/workspaces/example?from=link',
    );
    expect(
      appLinkPath(Uri.parse('akribos://open?path=%2F%2Fevil.test'), origin),
      isNull,
    );
    expect(
      appLinkPath(
        Uri.parse('akribos://open?path=https%3A%2F%2Fevil.test'),
        origin,
      ),
      isNull,
    );
  });
}
