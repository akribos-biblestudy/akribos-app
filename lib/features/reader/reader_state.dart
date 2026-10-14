import '../../core/json.dart';
import 'books.dart';

const readerLayouts = <String, String>{
  'single': 'Eine Kachel',
  'columns-2': 'Zwei Spalten',
  'columns-3': 'Drei Spalten',
  'columns-4': 'Vier Spalten',
  'rows-2': 'Zwei Zeilen',
  'left-full': 'Links groß',
  'right-full': 'Rechts groß',
  'grid-4': 'Vier Kacheln',
};

/// Server output uses activeSaved*; mutation inputs deliberately use workspace*.
void adoptReaderSelection(Json target, Json response) {
  for (final pair in const {
    'workspaceId': 'activeSavedWorkspaceId',
    'workspaceVersion': 'activeSavedWorkspaceVersion',
    'workspaceContentVersion': 'activeSavedWorkspaceContentVersion',
  }.entries) {
    if (response.containsKey(pair.value)) {
      target[pair.key] = response[pair.value];
    } else if (response.containsKey(pair.key)) {
      target[pair.key] = response[pair.key];
    }
  }
}

Json activeTab(Json tile) => asMaps(tile['tabs']).firstWhere(
  (tab) => tab['id'] == tile['activeTabId'],
  orElse: () => <String, dynamic>{},
);

/// Matches the server's readable URL format. Repeated parameters and contextual
/// word positions are preserved; private workspace versions never enter links.
String encodeReaderState(Json workspace, Json searches, String previousState) {
  String encode(Object? value) =>
      Uri.encodeComponent('$value').replaceAll('%2C', ',');
  final parts = <String>['layout=${encode(workspace['layout'])}'];
  final tiles = asMaps(workspace['tiles']);
  for (var i = 0; i < tiles.length; i++) {
    final tile = tiles[i];
    final tabs = asMaps(tile['tabs']);
    for (var j = 0; j < tabs.length; j++) {
      final tab = tabs[j];
      final coordinate = '${i + 1}.${j + 1}';
      parts.add(
        'tab=$coordinate:${encode(tab['resourceId'])}:${tab['linkSet'] ?? '-'}:${encode(referenceLabel(asMap(tab['reference'])))}',
      );
      if (asString(tab['lookup']).isNotEmpty) {
        parts.add('lookup=$coordinate:${encode(tab['lookup'])}');
      }
      final study = asMap(tab['studyContext']);
      if (study.isNotEmpty) {
        parts.add('source=$coordinate:${encode(study['sourceResourceId'])}');
        parts.add(
          'sourceRef=$coordinate:${encode(referenceLabel(asMap(study['reference'])))}',
        );
        if (asString(study['word']).isNotEmpty) {
          parts.add('word=$coordinate:${encode(study['word'])}');
          if (study['wordPosition'] != null) {
            parts.add('wordPosition=$coordinate:${study['wordPosition']}');
          }
        }
      }
      final search = asString(searches[tab['id']]).trim();
      if (search.isNotEmpty) parts.add('search=$coordinate:${encode(search)}');
    }
    final index = tabs.indexWhere((tab) => tab['id'] == tile['activeTabId']);
    if (index >= 0) parts.add('active=${i + 1}.${index + 1}');
  }
  final focused = tiles.indexWhere(
    (tile) => tile['id'] == workspace['focusedTileId'],
  );
  if (focused >= 0) parts.add('focus=${focused + 1}');
  final previous = Uri.splitQueryString(previousState);
  for (final key in ['notesQuery', 'notesTag', 'notesFilter']) {
    if (previous.containsKey(key)) {
      parts.add('$key=${encode(previous[key]).replaceAll('%3A', ':')}');
    }
  }
  return parts.join('&');
}

/// Align every member, including inactive tabs, without moving other groups.
void updateReadingPosition(
  Json workspace,
  String tileId,
  String tabId,
  Json reference,
) {
  final tiles = asMaps(workspace['tiles']);
  final tile = tiles.firstWhere((tile) => tile['id'] == tileId);
  final tab = asMaps(tile['tabs']).firstWhere((tab) => tab['id'] == tabId);
  final linkSet = tab['linkSet'];
  for (final otherTile in tiles) {
    for (final other in asMaps(otherTile['tabs'])) {
      if (other['id'] == tabId ||
          (linkSet != null && other['linkSet'] == linkSet)) {
        other['reference'] = Map<String, dynamic>.from(reference);
      }
    }
  }
  workspace['focusedTileId'] = tileId;
}

String readerPath(Json workspace, String readerState) {
  final tiles = asMaps(workspace['tiles']);
  final tile = tiles.firstWhere(
    (tile) => tile['id'] == workspace['focusedTileId'],
    orElse: () => tiles.isEmpty ? <String, dynamic>{} : tiles.first,
  );
  final reference = asMap(activeTab(tile)['reference']);
  return '/${referenceLabel(reference)}${readerState.isEmpty ? '' : '?$readerState'}';
}

String readerActionPath(String path, Json data, {String? readerState}) {
  final base = Uri.parse(path).path;
  final state = readerState ?? asString(data['readerState']);
  final parameters = <String>[
    if (state.isNotEmpty) state,
    for (final key in [
      'workspaceId',
      'workspaceVersion',
      'workspaceContentVersion',
    ])
      if (data[key] != null) '$key=${Uri.encodeComponent('${data[key]}')}',
    if (data['readerWorkspaceDetached'] == true) 'workspaceDetached=true',
  ];
  return '$base?${parameters.join('&')}';
}
