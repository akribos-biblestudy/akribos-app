import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/json.dart';
import 'verse_text.dart';

/// A fixed-size action overview; account-sized catalogues live on separate pages.
Future<String?> showReaderVerseMenu(
  BuildContext context, {
  required String reference,
  required String text,
  required bool signedIn,
  required List<Json> styles,
  required List<Json> highlights,
  required List<Json> lists,
  required Set<String> selectedLists,
  ReaderMenuPage initialPage = ReaderMenuPage.actions,
  bool multiple = false,
  bool canSelectVerse = false,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 720),
  builder: (_) => ReaderVerseMenu(
    reference: reference,
    text: text,
    signedIn: signedIn,
    styles: styles,
    highlights: highlights,
    lists: lists,
    selectedLists: selectedLists,
    initialPage: initialPage,
    multiple: multiple,
    canSelectVerse: canSelectVerse,
  ),
);

enum ReaderMenuPage { actions, marks, lists }

class ReaderVerseMenu extends StatefulWidget {
  const ReaderVerseMenu({
    super.key,
    required this.reference,
    required this.text,
    required this.signedIn,
    required this.styles,
    required this.highlights,
    required this.lists,
    required this.selectedLists,
    this.initialPage = ReaderMenuPage.actions,
    this.multiple = false,
    this.canSelectVerse = false,
  });

  final String reference, text;
  final bool signedIn;
  final List<Json> styles, highlights, lists;
  final Set<String> selectedLists;
  final ReaderMenuPage initialPage;
  final bool multiple;
  final bool canSelectVerse;

  @override
  State<ReaderVerseMenu> createState() => _ReaderVerseMenuState();
}

class _ReaderVerseMenuState extends State<ReaderVerseMenu> {
  late ReaderMenuPage _page = widget.initialPage;

  void _select(String action) => Navigator.pop(context, action);
  void _open(ReaderMenuPage page) => setState(() => _page = page);

  Widget _header() => Row(
    children: [
      if (_page != ReaderMenuPage.actions && !widget.multiple)
        IconButton(
          tooltip: 'Zurück zu den Versaktionen',
          onPressed: () => _open(ReaderMenuPage.actions),
          icon: const Icon(Icons.arrow_back),
        ),
      Expanded(
        child: Text(switch (_page) {
          ReaderMenuPage.actions => widget.reference,
          ReaderMenuPage.marks => 'Markieren · ${widget.reference}',
          ReaderMenuPage.lists => 'Sammlungen · ${widget.reference}',
        }, style: Theme.of(context).textTheme.titleMedium),
      ),
      if (widget.canSelectVerse && _page == ReaderMenuPage.actions)
        IconButton(
          tooltip: 'Vers auswählen',
          onPressed: () => _select('select'),
          icon: const Icon(Icons.check_box_outlined),
        ),
      IconButton(
        tooltip: 'Versmenü schließen',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close),
      ),
    ],
  );

  Widget _actions(BoxConstraints constraints) {
    final actions = <(String, String, IconData, VoidCallback)>[
      if (widget.signedIn) ...[
        (
          'marks',
          'Markieren',
          Icons.highlight_outlined,
          () => _open(ReaderMenuPage.marks),
        ),
        (
          'lists',
          'Sammlungen',
          Icons.playlist_add,
          () => _open(ReaderMenuPage.lists),
        ),
      ],
      ('note', 'Notiz', Icons.note_add_outlined, () => _select('note')),
      ('share', 'Teilen', Icons.share_outlined, () => _select('share')),
    ];
    final scaler = MediaQuery.textScalerOf(context);
    final width = constraints.maxWidth - 32;
    final labelStyle = Theme.of(context).textTheme.labelLarge;
    final labelWidths = actions.map((action) {
      final painter = TextPainter(
        text: TextSpan(text: action.$2, style: labelStyle),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    });
    // One line per label, including real font metrics and accessibility scaling.
    // Icon (24), gap (8), horizontal padding (24), plus rounding clearance.
    final minimumWidth = labelWidths.reduce(math.max).ceilToDouble() + 57;
    final availableColumns = math.max(
      1,
      ((width + 8) / (minimumWidth + 8)).floor(),
    );
    final columns = actions.length <= availableColumns
        ? actions.length
        : availableColumns >= 2
        ? 2
        : 1;
    final actionWidth = (width - (columns - 1) * 8) / columns;
    final preview = constraints.maxHeight >= 420 && scaler.scale(14) <= 21;
    return SingleChildScrollView(
      key: const ValueKey('verse-menu-overview-scroll'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            if (preview) ...[
              Text(
                widget.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
            ],
            for (var start = 0; start < actions.length; start += columns) ...[
              if (start > 0) const SizedBox(height: 8),
              IntrinsicHeight(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var index = start;
                      index < math.min(start + columns, actions.length);
                      index++
                    ) ...[
                      if (index > start) const SizedBox(width: 8),
                      SizedBox(
                        width: actionWidth,
                        child: _action(actions[index]),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (!widget.signedIn) ...[
              const SizedBox(height: 12),
              Tooltip(
                message: 'Zum Markieren und Sammeln anmelden',
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: () => _select('login'),
                  icon: const Icon(Icons.login),
                  label: const Text('Anmelden', maxLines: 1, softWrap: false),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _action((String, String, IconData, VoidCallback) action) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('verse-action-${action.$1}'),
        onTap: action.$4,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(action.$3, size: 24, color: colors.primary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    action.$2,
                    maxLines: 1,
                    softWrap: false,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _markChoices() => ListView(
    key: const ValueKey('verse-menu-marks'),
    padding: const EdgeInsets.only(bottom: 16),
    children: [
      for (final style in widget.styles)
        ListTile(
          leading: CircleAvatar(
            backgroundColor: verseColor(asString(style['color'])),
            radius: 12,
          ),
          title: Text(asString(style['name'], 'Markieren')),
          onTap: () => _select('highlight:${style['id']}'),
        ),
      if (widget.styles.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Noch keine Markierungsstile vorhanden.'),
        ),
      const Divider(),
      for (
        var index = 0;
        !widget.multiple && index < widget.highlights.length;
        index++
      )
        ListTile(
          leading: const Icon(Icons.format_color_reset),
          title: Text(
            'Markierung „${widget.highlights[index]['name'] ?? 'Markierung'}“ entfernen',
          ),
          onTap: () => _select('removeRange:$index'),
        ),
      ListTile(
        leading: const Icon(Icons.format_color_reset),
        title: Text(
          widget.multiple
              ? 'Versmarkierungen entfernen'
              : 'Versmarkierung entfernen',
        ),
        onTap: () => _select('removeHighlight'),
      ),
    ],
  );

  Widget _listChoices() => ListView(
    key: const ValueKey('verse-menu-lists'),
    padding: const EdgeInsets.only(bottom: 16),
    children: [
      ListTile(
        leading: const Icon(Icons.add),
        title: Text(
          widget.multiple
              ? 'Neue Sammlung mit diesen Versen'
              : 'Neue Sammlung mit diesem Vers',
        ),
        onTap: () => _select('newList'),
      ),
      if (widget.lists.isNotEmpty) const Divider(),
      for (final list in widget.lists)
        ListTile(
          leading: Icon(
            widget.selectedLists.contains(asString(list['id']))
                ? Icons.playlist_add_check
                : Icons.playlist_add,
          ),
          title: Text(asString(list['title'])),
          subtitle: Text(
            widget.selectedLists.contains(asString(list['id']))
                ? widget.multiple
                      ? 'Alle Verse enthalten · Tippen zum Entfernen'
                      : 'Vers enthalten · Tippen zum Entfernen'
                : widget.multiple
                ? 'Fehlende Verse hinzufügen'
                : 'Vers hinzufügen',
          ),
          onTap: () => _select('list:${list['id']}'),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _page == ReaderMenuPage.actions || widget.multiple,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _open(ReaderMenuPage.actions);
    },
    child: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) => _page == ReaderMenuPage.actions
            ? _actions(constraints)
            : SizedBox(
                height: math.min(560, constraints.maxHeight),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: _header(),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _page == ReaderMenuPage.marks
                          ? _markChoices()
                          : _listChoices(),
                    ),
                  ],
                ),
              ),
      ),
    ),
  );
}
