import 'package:akribos_app/features/reader/reader_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves duplicate tabs and updates only the active linked group', () {
    const path =
        '/Joh1?layout=single&tab=1.1:BIBLE:A:Joh1&tab=1.2:BIBLE:B:Joh2&tab=1.3:OTHER:B:Joh2&active=1.2&focus=1&search=1.1:Liebe';
    final position = readerPositionFromPath(path)!;
    expect(position.reference, {'book': 43, 'chapter': 2});
    final result = readerPathWithOfflinePosition(path, 'BIBLE', {
      'book': 43,
      'chapter': 3,
      'verse': 16,
    })!;
    expect(result, contains('tab=1.1:BIBLE:A:Joh1'));
    expect(result, contains('tab=1.2:BIBLE:B:Joh3,16'));
    expect(result, contains('tab=1.3:OTHER:B:Joh3,16'));
    expect(result, contains('search=1.1:Liebe'));
    expect(readerPositionFromPath(result)!.reference, {
      'book': 43,
      'chapter': 3,
      'verse': 16,
    });
  });
  test('creates a tab for an offline work without deleting existing tabs', () {
    final result = readerPathWithOfflinePosition(
      '/Joh1?layout=single&tab=1.1:OTHER:A:Joh1&active=1.1&focus=1',
      'NEW',
      {'book': 1, 'chapter': 2},
    )!;
    expect(result, contains('tab=1.1:OTHER:A:Joh1'));
    expect(result, contains('tab=1.2:NEW:-:1Mo2'));
    expect(readerPositionFromPath(result)!.resource, 'NEW');
    expect(
      readerPathWithOfflinePosition('/', 'NEW', {'book': 43, 'chapter': 3}),
      contains('tab=1.1:NEW:-:Joh3'),
    );
  });
  test('uses the focused tile when the same resource is active twice', () {
    const source =
        '/Joh2?layout=columns&tab=1.1:BIBLE:A:Joh1&tab=2.1:BIBLE:B:Joh2&tab=2.2:OTHER:B:Joh2&active=1.1&active=2.1&focus=2';
    final result = readerPathWithOfflinePosition(source, 'BIBLE', {
      'book': 43,
      'chapter': 3,
    })!;
    expect(result, contains('tab=1.1:BIBLE:A:Joh1'));
    expect(result, contains('tab=2.1:BIBLE:B:Joh3'));
    expect(result, contains('tab=2.2:OTHER:B:Joh3'));
    expect(result, contains('active=1.1'));
    expect(result, contains('focus=2'));
  });
}
