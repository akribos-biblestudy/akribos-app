import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/json.dart';
import '../../widgets/common.dart';
import '../documents/document_widgets.dart';
import 'books.dart';
import 'reader_notes.dart';

/// The tablet's secondary column shows private note summaries for the visible
/// chapter. Only chapter changes reload it; verse scrolling leaves it untouched.
class ReaderNotesCompanion extends StatefulWidget {
  const ReaderNotesCompanion({
    super.key,
    required this.reference,
    required this.active,
    required this.flush,
  });

  final Json reference;
  final bool active;
  final Future<bool> Function() flush;

  @override
  State<ReaderNotesCompanion> createState() => ReaderNotesCompanionState();
}

class ReaderNotesCompanionState extends State<ReaderNotesCompanion> {
  final _notes = GlobalKey<ReaderNotesState>();
  late Json _reference = Map.of(widget.reference);

  String get _chapter => referenceLabel({
    'book': _reference['book'],
    'chapter': _reference['chapter'],
  });

  /// Called by the Reader without rebuilding its PageView for every verse.
  void follow(Json reference) {
    final changed =
        reference['book'] != _reference['book'] ||
        reference['chapter'] != _reference['chapter'];
    _reference = Map.of(reference);
    if (changed) setState(() {});
  }

  @override
  void didUpdateWidget(ReaderNotesCompanion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reference = Map.of(widget.reference);
    // The editor is another shell destination. Refresh after returning so a
    // newly created/edited note appears without remounting the Bible.
    if (widget.active && !oldWidget.active) {
      _notes.currentState?.reload();
    }
  }

  Future<void> _open(String path) async {
    if (!await widget.flush() || !mounted) return;
    await AppScope.of(context).open(path);
  }

  Future<void> _create() async {
    if (!await widget.flush() || !mounted) return;
    final fields = await editFeatureFields(context, 'Neue Notiz', [
      const FeatureField('title', 'Titel', required: true),
      FeatureField(
        'passage',
        'Bibelstelle (optional)',
        value: referenceLabel({
          ..._reference,
          'verse': _reference['verse'] ?? 1,
        }),
      ),
    ], submit: 'Anlegen');
    if (fields == null || !mounted) return;
    await runAction(context, '/notes', 'create', {
      ...fields,
      'kind': 'note',
      // Use the normal editor redirect and preserve its existing save guards.
      'returnTo': '/',
    });
  }

  @override
  Widget build(BuildContext context) {
    if (asMap(AppScope.of(context).api.bootstrap['user']).isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Melde dich an, um deine Notizen neben der Bibel zu lesen.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _open('/login'),
                child: const Text('Anmelden'),
              ),
            ],
          ),
        ),
      );
    }
    return ReaderNotes(
      key: _notes,
      reference: _chapter,
      // Notes to a passage remain relevant across Bible translations.
      resourceId: '',
      notesOnly: true,
      initialState: 'notesFilter=current',
      onFilters: (_, _, _) {},
      onOpen: (id) => _open('/notes/${Uri.encodeComponent(id)}?returnTo=%2F'),
      onCreate: _create,
    );
  }
}
