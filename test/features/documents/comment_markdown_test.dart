import 'package:akribos_app/features/collections/comment_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('untouched rich comments preserve the original HTML byte for byte', () {
    const html =
        '<div><b>Fett</b><br><u>Wichtig</u></div><ul><li>α &amp; שָׁלוֹם</li></ul>';
    final initial = commentToMarkdown(html);
    expect(
      commentFromMarkdown(
        initial,
        originalHtml: html,
        initialMarkdown: initial,
      ),
      html,
    );
  });

  test('edited comments retain bold, lists, line breaks and underlining', () {
    const html =
        '<p><strong>Fett</strong><br>Zeile zwei</p><ul><li>Erster Punkt</li></ul><p><u>Unterstrichen</u></p>';
    final initial = commentToMarkdown(html);
    final output = commentFromMarkdown(
      '$initial\n\nWeiterer Gedanke',
      originalHtml: html,
      initialMarkdown: initial,
    );
    expect(output, contains('<strong>Fett</strong>'));
    expect(output, contains('<br>'));
    expect(output, contains('<ul>'));
    expect(output, contains('<li>Erster Punkt</li>'));
    expect(output, contains('<u>Unterstrichen</u>'));
    expect(output, contains('Weiterer Gedanke'));
  });

  test(
    'links retain their destination under the attribute-free comment contract',
    () {
      final output = commentFromMarkdown(
        '[Quelle](https://example.org/studie)',
      );
      expect(output, '<p>Quelle (https://example.org/studie)</p>');
      expect(output, isNot(contains('<a')));
    },
  );

  test(
    'native preview never treats unsupported markup as executable content',
    () {
      final output = commentFromMarkdown('Text <script>\nAntwort');
      expect(output, contains('&lt;script&gt;'));
      expect(output, isNot(contains('<script>')));
    },
  );

  test(
    'editing literal escaped tags keeps them text rather than formatting',
    () {
      const html = '<p>Wörtlich &lt;u&gt; und &lt;script&gt;</p>';
      final initial = commentToMarkdown(html);
      final output = commentFromMarkdown('$initial\nZusatz');
      expect(output, contains('&#60;u&#62;'));
      expect(output, isNot(contains('<u>')));
      expect(output, contains('&#60;script&#62;'));
    },
  );
}
