import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/json.dart';
import '../search/search_screen.dart';
import 'books.dart';

/// Reuse the dictionary explicitly chosen for this link group without changing
/// its tab. An empty id lets the read-only Strong endpoint choose its default.
String preferredReaderLexicon({
  required Json workspace,
  required List<Json> resources,
  required String sourceTileId,
  required Json sourceTab,
  required String strong,
}) {
  final language = strong.startsWith('H') ? 'hbo' : 'grc';
  for (final tile in asMaps(workspace['tiles'])) {
    for (final tab in asMaps(tile['tabs'])) {
      final grouped = sourceTab['linkSet'] != null
          ? tab['linkSet'] == sourceTab['linkSet']
          : tile['id'] == sourceTileId && tab['linkSet'] == null;
      if (!grouped) continue;
      for (final resource in resources) {
        if (resource['id'] == tab['resourceId'] &&
            resource['kind'] == 'lexicon' &&
            resource['language'] == language) {
          return asString(resource['id']);
        }
      }
    }
  }
  return '';
}

/// Returns only an explicitly selected Bible reference or external app route.
/// Opening, scrolling and dismissing the sheet never mutate the workspace.
Future<Json?> showReaderLexiconSheet(
  BuildContext context, {
  required String strong,
  required String lexiconId,
  required String sourceResourceId,
  required Json reference,
  required String word,
  required int wordPosition,
}) async {
  final scope = AppScope.of(context);
  ModalRoute<dynamic>? sheetRoute;
  final result = await showModalBottomSheet<Json>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: scope.eInk ? AnimationStyle.noAnimation : null,
    constraints: const BoxConstraints(maxWidth: 960),
    builder: (sheetContext) {
      sheetRoute = ModalRoute.of(sheetContext);
      return _ReaderLexiconSheet(
        scope: scope,
        strong: strong,
        lexiconId: lexiconId,
        sourceResourceId: sourceResourceId,
        reference: reference,
        word: word,
        wordPosition: wordPosition,
      );
    },
  );
  await sheetRoute?.completed;
  return result;
}

class _ReaderLexiconSheet extends StatefulWidget {
  const _ReaderLexiconSheet({
    required this.scope,
    required this.strong,
    required this.lexiconId,
    required this.sourceResourceId,
    required this.reference,
    required this.word,
    required this.wordPosition,
  });
  final AppScope scope;
  final String strong, lexiconId, sourceResourceId, word;
  final Json reference;
  final int wordPosition;

  @override
  State<_ReaderLexiconSheet> createState() => _ReaderLexiconSheetState();
}

class _ReaderLexiconSheetState extends State<_ReaderLexiconSheet> {
  late String _strong = widget.strong;
  late Json _tab = _studyTab();
  ScrollController? _scrollController;

  Json _studyTab() => {
    'lookup': _strong,
    'resourceId': _strong[0] == widget.strong[0] ? widget.lexiconId : '',
    'studyContext': {
      'sourceResourceId': widget.sourceResourceId,
      'reference': widget.reference,
      // Related articles are not the clicked tagged word. Do not attach that
      // word's assignment status to a different Strong number.
      if (_strong == widget.strong) ...{
        'word': widget.word,
        'wordPosition': widget.wordPosition,
      },
    },
  };

  Future<void> _open(String path) async {
    final uri = Uri.tryParse(path);
    final match = uri == null || uri.hasScheme || uri.hasAuthority
        ? null
        : RegExp(r'^/([GH]\d+)/?$').firstMatch(uri.path);
    if (match != null) {
      if (_scrollController?.hasClients == true) _scrollController!.jumpTo(0);
      setState(() {
        _strong = match[1]!;
        _tab = _studyTab();
      });
    } else {
      Navigator.pop(context, <String, dynamic>{'path': path});
    }
  }

  @override
  Widget build(BuildContext context) => AppScope(
    api: widget.scope.api,
    open: _open,
    refreshSession: widget.scope.refreshSession,
    onAuthenticationChanged: widget.scope.onAuthenticationChanged,
    setNavigationGuard: widget.scope.setNavigationGuard,
    setTheme: widget.scope.setTheme,
    themeMode: widget.scope.themeMode,
    eInk: widget.scope.eInk,
    setEInk: widget.scope.setEInk,
    child: DraggableScrollableSheet(
      initialChildSize: .92,
      minChildSize: .35,
      maxChildSize: .96,
      expand: false,
      builder: (context, controller) {
        _scrollController = controller;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 4, bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lexikon · $_strong',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '„${widget.word}“ · ${referenceLabel(widget.reference)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Lexikon schließen',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: LexiconStudy(
                key: ValueKey(_strong),
                tab: _tab,
                entry: const {},
                scrollController: controller,
                onOpen: (reference) =>
                    Navigator.pop(context, {'reference': reference}),
              ),
            ),
          ],
        );
      },
    ),
  );
}
