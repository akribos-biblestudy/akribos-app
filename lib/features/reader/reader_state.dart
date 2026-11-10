import '../../core/json.dart';
import 'books.dart';

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

/// Native tabs form one sequence. Reordering an imported multi-tile URL
/// normalizes that sequence to one local tile without losing tab contents,
/// link groups, lookup context, IDs or the currently selected tab.
bool moveReaderTab(Json workspace, String tabId, int destination) {
  final tiles = asMaps(workspace['tiles']);
  final tabs = [for (final tile in tiles) ...asMaps(tile['tabs'])];
  final oldIndex = tabs.indexWhere((tab) => tab['id'] == tabId);
  if (oldIndex < 0 || destination < 0 || destination > tabs.length) {
    return false;
  }
  final newIndex = destination.clamp(0, tabs.length - 1);
  if (oldIndex == newIndex) return false;
  final focused = tiles.firstWhere(
    (tile) => tile['id'] == workspace['focusedTileId'],
    orElse: () => tiles.first,
  );
  final selected = activeTab(focused);
  tabs.insert(newIndex, tabs.removeAt(oldIndex));
  workspace['layout'] = 'single';
  workspace['tiles'] = [
    {
      ...focused,
      'tabs': tabs,
      'activeTabId': selected['id'] ?? tabs.first['id'],
    },
  ];
  workspace['focusedTileId'] = focused['id'];
  return true;
}

/// Local activation follows the existing link-group rule without a server write.
void activateReaderTab(Json workspace, String tileId, String tabId) {
  final tiles = asMaps(workspace['tiles']);
  final tile = tiles.firstWhere((tile) => tile['id'] == tileId);
  final source = activeTab(tile);
  final target = asMaps(tile['tabs']).firstWhere((tab) => tab['id'] == tabId);
  final group = target['linkSet'];
  Json? reference;
  if (group != null) {
    if (group == source['linkSet']) {
      reference = asMap(source['reference']);
    } else {
      for (final peerTile in tiles) {
        if (peerTile == tile) continue;
        final peer = activeTab(peerTile);
        if (peer['linkSet'] == group) {
          reference = asMap(peer['reference']);
          break;
        }
      }
    }
  }
  if (reference != null && reference.isNotEmpty) {
    updateReadingPosition(workspace, tileId, tabId, reference);
  }
  tile['activeTabId'] = tabId;
  workspace['focusedTileId'] = tileId;
}

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

/// Only public Reader state is stored or shared. Ignore account workspace guards
/// even when they arrived in an old link or a legacy server response.
String localReaderAddress(String path) {
  final uri = Uri.parse(path);
  const fields = {
    'layout',
    'tab',
    'active',
    'focus',
    'lookup',
    'source',
    'sourceRef',
    'word',
    'wordPosition',
    'search',
    'notesQuery',
    'notesTag',
    'notesFilter',
  };
  final state = uri.query
      .split('&')
      .where(
        (part) => fields.contains(Uri.decodeComponent(part.split('=').first)),
      )
      .join('&');
  return '${uri.path.isEmpty ? '/Joh1' : uri.path}${state.isEmpty ? '' : '?$state'}';
}

String readerActionPath(String path, Json data, {String? readerState}) {
  final state = readerState ?? asString(data['readerState']);
  final local = localReaderAddress('${Uri.parse(path).path}?$state');
  return '$local${local.contains('?') ? '&' : '?'}workspaceDetached=true';
}

/// Restore an offline position while retaining local tabs and linked groups.
String? readerPathWithOfflinePosition(
  String path,
  String resourceId,
  Json ref,
) {
  final book = asInt(ref['book']);
  final chapter = asInt(ref['chapter']);
  if (book < 1 ||
      book > bibleBooks.length ||
      chapter < 1 ||
      resourceId.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(path);
  if (uri == null) return null;
  final parts = uri.query.split('&').where((s) => s.isNotEmpty).toList();
  if (!parts.any((part) => part.startsWith('layout='))) {
    parts.add('layout=single');
  }
  final tabs = <int, List<String>>{};
  for (var i = 0; i < parts.length; i++) {
    if (!parts[i].startsWith('tab=')) continue;
    final fields = parts[i].substring(4).split(':');
    if (fields.length == 4 && RegExp(r'^\d+\.\d+$').hasMatch(fields[0])) {
      tabs[i] = fields;
    }
  }
  final active = parts
      .where((part) => part.startsWith('active='))
      .map((part) => part.substring(7))
      .toSet();
  final matches = tabs.entries
      .where((entry) => Uri.decodeComponent(entry.value[1]) == resourceId)
      .toList();
  final focus = uri.queryParameters['focus'];
  final chosen =
      matches
          .where(
            (entry) =>
                entry.value[0].startsWith('$focus.') &&
                active.contains(entry.value[0]),
          )
          .firstOrNull ??
      matches.where((entry) => active.contains(entry.value[0])).firstOrNull ??
      matches.firstOrNull;
  String coordinate;
  final encodedReference = Uri.encodeComponent(referenceLabel(ref))
      .replaceAll('%2C', ',');
  if (chosen == null) {
    final max = tabs.values
        .map((fields) => fields[0].split('.'))
        .where((fields) => fields[0] == '1')
        .map((fields) => int.tryParse(fields[1]) ?? 0)
        .fold(0, (int a, int b) => a > b ? a : b);
    coordinate = '1.${max + 1}';
    parts.add(
      'tab=$coordinate:${Uri.encodeComponent(resourceId)}:-:$encodedReference',
    );
  } else {
    coordinate = chosen.value[0];
    final group = chosen.value[2];
    for (final entry in tabs.entries) {
      if (entry.key == chosen.key ||
          (group != '-' && group.isNotEmpty && entry.value[2] == group)) {
        entry.value[3] = encodedReference;
        parts[entry.key] = 'tab=${entry.value.join(':')}';
      }
    }
  }
  final tile = coordinate.split('.').first;
  parts.removeWhere((part) {
    if (part.startsWith('focus=')) return true;
    return part.startsWith('active=$tile.');
  });
  parts.add('active=$coordinate');
  parts.add('focus=$tile');
  return '/${referenceLabel(ref)}?${parts.join('&')}';
}

/// Extract the focused tab and reference from a local Reader snapshot.
({String resource, Json reference})? readerPositionFromPath(String path) {
  final uri = Uri.tryParse(path);
  if (uri == null) return null;
  final focus = uri.queryParameters['focus'] ?? '1';
  final active = uri.queryParametersAll['active']
      ?.where((value) => value.startsWith('$focus.'))
      .firstOrNull;
  if (active == null) return null;
  for (final raw in uri.query.split('&')) {
    if (!raw.startsWith('tab=')) continue;
    final fields = raw.substring(4).split(':');
    if (fields.length != 4 || fields[0] != active) continue;
    final resource = Uri.decodeComponent(fields[1]);
    final label = Uri.decodeComponent(fields[3]);
    for (final book in bibleBooks) {
      if (!label.startsWith(book.abbreviation)) continue;
      final match = RegExp(r'^(\d+)(?:,(\d+)(?:-(\d+))?)?$')
          .firstMatch(label.substring(book.abbreviation.length));
      if (match == null) continue;
      final chapter = int.parse(match.group(1)!);
      if (chapter < 1 || chapter > book.chapters) return null;
      return (
        resource: resource,
        reference: {
          'book': book.id,
          'chapter': chapter,
          if (match.group(2) != null) 'verse': int.parse(match.group(2)!),
          if (match.group(3) != null) 'verseEnd': int.parse(match.group(3)!),
        },
      );
    }
  }
  return null;
}
