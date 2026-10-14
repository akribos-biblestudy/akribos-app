import 'package:flutter_test/flutter_test.dart';
import 'package:akribos_app/core/json.dart';
import 'package:akribos_app/features/reader/books.dart';
import 'package:akribos_app/features/reader/reader_state.dart';
import 'package:akribos_app/features/reader/verse_text.dart';

Json tab(String id, String? group, int chapter) => {
  'id': id,
  'resourceId': 'SEEDDE',
  'linkSet': group,
  'reference': {'book': 43, 'chapter': chapter},
};

void main() {
  test('server selection response maps to mutation guard names without inventing versions', () {
    final Json target = {};
    adoptReaderSelection(target, {
      'activeSavedWorkspaceId': 'saved',
      'activeSavedWorkspaceVersion': 7,
      'activeSavedWorkspaceContentVersion': 14,
    });
    expect(target, {
      'workspaceId': 'saved',
      'workspaceVersion': 7,
      'workspaceContentVersion': 14,
    });
    adoptReaderSelection(target, {
      'activeSavedWorkspaceId': null,
      'activeSavedWorkspaceVersion': null,
      'activeSavedWorkspaceContentVersion': null,
    });
    expect(target.values, everyElement(isNull));
  });
  test('canonical reader state preserves repeated tabs, exact word context and notes filters', () {
    final source = tab('bible', 'A', 3)
      ..['reference'] = {'book': 43, 'chapter': 3, 'verse': 16};
    final lexicon = tab('lexicon', 'A', 3)
      ..['resourceId'] = 'GREEK'
      ..['lookup'] = 'G26'
      ..['studyContext'] = {
        'sourceResourceId': 'SEEDDE',
        'reference': {'book': 43, 'chapter': 3, 'verse': 16},
        'word': 'Liebe',
        'wordPosition': 0,
      };
    final workspace = {
      'layout': 'columns-2',
      'focusedTileId': 'first',
      'tiles': [
        {
          'id': 'first',
          'activeTabId': 'bible',
          'tabs': [source, lexicon],
        },
        {'id': 'second', 'activeTabId': null, 'tabs': []},
      ],
    };
    final state = encodeReaderState(workspace, {
      'lexicon': 'heilige Liebe',
    }, 'notesQuery=Joh3,16%3A%20Glaube&notesTag=Thema&notesFilter=current');
    expect(
      state,
      'layout=columns-2&tab=1.1:SEEDDE:A:Joh3,16&tab=1.2:GREEK:A:Joh3&lookup=1.2:G26&source=1.2:SEEDDE&sourceRef=1.2:Joh3,16&word=1.2:Liebe&wordPosition=1.2:0&search=1.2:heilige%20Liebe&active=1.1&focus=1&notesQuery=Joh3,16:%20Glaube&notesTag=Thema&notesFilter=current',
    );
    expect(readerPath(workspace, state), startsWith('/Joh3,16?'));
    expect(state, isNot(contains('workspaceId')));
  });

  test('reader actions carry all versions separately from shareable state', () {
    final path = readerActionPath('/Joh3?old=1', {
      'readerState': 'layout=single&tab=1.1:SEEDDE:A:Joh3&active=1.1&focus=1',
      'workspaceId': 'id',
      'workspaceVersion': 4,
      'workspaceContentVersion': 17,
      'readerWorkspaceDetached': true,
    });
    final query = Uri.parse(path).queryParameters;
    expect(query['workspaceId'], 'id');
    expect(query['workspaceVersion'], '4');
    expect(query['workspaceContentVersion'], '17');
    expect(query['workspaceDetached'], 'true');
    expect(query.containsKey('old'), false);
  });

  test(
    'position update aligns inactive members and preserves independent groups',
    () {
      final active = tab('active', 'A', 1), inactive = tab('inactive', 'A', 1);
      final independent = tab('independent', null, 4),
          other = tab('other', 'B', 9);
      final Json workspace = {
        'tiles': [
          {
            'id': 'tile1',
            'activeTabId': 'active',
            'tabs': [active, inactive],
          },
          {
            'id': 'tile2',
            'activeTabId': 'independent',
            'tabs': [independent, other],
          },
        ],
      };
      updateReadingPosition(workspace, 'tile1', 'active', {
        'book': 43,
        'chapter': 3,
        'verse': 16,
      });
      expect(active['reference'], inactive['reference']);
      expect(asMap(independent['reference'])['chapter'], 4);
      expect(asMap(other['reference'])['chapter'], 9);
      updateReadingPosition(workspace, 'tile2', 'independent', {
        'book': 43,
        'chapter': 5,
      });
      expect(asMap(active['reference'])['chapter'], 3);
      expect(workspace['focusedTileId'], 'tile2');
    },
  );

  test('nested divine name and red letter containers preserve tagged word positions', () {
    final segments = <dynamic>[
      'Der ',
      {
        'kind': 'nd',
        'children': [
          {'kind': 'w', 'text': 'Herr', 'strong': 'H3068'},
        ],
      },
      ' ist ',
      {
        'kind': 'wj',
        'children': [
          {
            'kind': 'w',
            'text': 'Liebe',
            'strong': 'G26',
            'strongs': ['G26', 'G25'],
          },
        ],
      },
      '.',
    ];
    final runs = verseRuns(segments);
    final words = runs.where((run) => run.word != null).toList();
    expect(words.map((run) => run.position), [0, 1]);
    expect(words.first.divineName, true);
    expect(words.last.redLetter, true);
    expect(strongNumbers(words.last.word!), ['G26', 'G25']);
    expect(versePlainText(segments), 'Der Herr ist Liebe.');
    expect(words.last.wordIndex, 3);
    expect(
      runs.last.wordIndex,
      3,
      reason: 'Adjacent punctuation shares the same highlight word.',
    );
  });

  test('automatic assignment notes require exact marker and immediate studied word', () {
    Json word(String id) => {'kind': 'w', 'text': 'Wort', 'strong': id};
    final note = {
      'kind': 'note',
      'marker': '',
      'text': ' Automatische   Wortzuordnung; fachlich noch nicht bestätigt. ',
    };
    final segments = [
      word('G26'),
      ' ',
      note,
      ' ',
      word('G25'),
      note,
      ' Text ',
      note,
      {'kind': 'note', 'marker': 'a', 'text': assignmentNote},
    ];
    expect(verseRuns(segments).where((run) => run.note != null).length, 1);
    final study = verseRuns(
      segments,
      studiedStrong: 'G26',
    ).where((run) => run.note != null).toList();
    expect(study.length, 2);
    expect(study.first.note, contains('„Wort“ zu G26'));
    expect(
      study.last.note,
      assignmentNote,
      reason: 'Ordinary notes are always visible.',
    );
  });

  test('canon retains German Joel and Malachi division and encoded German references', () {
    expect(bibleBooks.length, 66);
    expect(bibleBooks[28].chapters, 4);
    expect(bibleBooks[38].chapters, 3);
    expect(
      referenceLabel({'book': 45, 'chapter': 8, 'verse': 1, 'verseEnd': 3}),
      'Röm8,1-3',
    );
  });
}
