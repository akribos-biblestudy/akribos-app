import 'package:akribos_app/features/documents/document_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('acknowledging an in-flight save preserves newer keystrokes', () {
    final draft = DocumentDraft(title: 'Titel', markdown: 'Alt', revision: 4);
    draft.markdown = 'Erste Änderung';
    final submitted = draft.snapshot();
    draft.markdown = 'Weitere Änderung während der Anfrage';
    draft.acknowledge(submitted, 5);
    expect(draft.markdown, 'Weitere Änderung während der Anfrage');
    expect(draft.dirty, isTrue);
    expect(draft.snapshot()['revision'], 5);
  });

  test('discard returns to the last acknowledged body, preserving exact Markdown', () {
    const body =
        '| A | B |\n| --- | --- |\n| α | שָׁלוֹם |\n\nText[^1]\n\n[^1]: Fußnote';
    final draft = DocumentDraft(title: 'Studie', markdown: body, revision: 1);
    draft.markdown = '$body\nErgänzung';
    draft.acknowledge(draft.snapshot(), 2);
    draft.markdown = 'Nicht gespeichert';
    draft.title = 'Falscher Titel';
    draft.discard();
    expect(draft.markdown, '$body\nErgänzung');
    expect(draft.title, 'Studie');
    expect(draft.revision, 2);
    expect(draft.dirty, isFalse);
  });

  test(
    'local recovery retains stale revision until explicit conflict resolution',
    () {
      final draft = DocumentDraft(
        title: 'Titel',
        markdown: 'Server',
        revision: 8,
      );
      draft.markdown = 'Lokaler Entwurf';
      draft.revision = 3;
      expect(draft.snapshot(), {
        'title': 'Titel',
        'markdown': 'Lokaler Entwurf',
        'revision': 3,
      });
      expect(draft.dirty, isTrue);
    },
  );
}
