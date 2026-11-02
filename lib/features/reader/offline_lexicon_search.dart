import 'package:html/parser.dart' as html_parser;

import '../../core/json.dart';

// Canonical Latin and Greek decompositions; combining marks are removed below.
// This is a bounded local approximation of PostgreSQL unaccent rather than its
// complete, server-configurable dictionary.
const _accented =
    r'àáâãäåçèéêëìíîïñòóôõöùúûüýÿāăąćĉċčďēĕėęěĝğġģĥĩīĭįĵķĺļľńņňōŏőŕŗřśŝşšţťũūŭůűųŵŷźżžơưǎǐǒǔǖǘǚǜǟǡǣǧǩǫǭǯǰǵǹǻǽǿȁȃȅȇȉȋȍȏȑȓȕȗșțȟȧȩȫȭȯȱȳʹάέήίόύώΐϊϋΰϓϔḁḃḅḇḉḋḍḏḑḓḕḗḙḛḝḟḡḣḥḧḩḫḭḯḱḳḵḷḹḻḽḿṁṃṅṇṉṋṍṏṑṓṕṗṙṛṝṟṡṣṥṧṩṫṭṯṱṳṵṷṹṻṽṿẁẃẅẇẉẋẍẏẑẓẕẖẗẘẙẛạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹἀἁἂἃἄἅἆἇἐἑἒἓἔἕἠἡἢἣἤἥἦἧἰἱἲἳἴἵἶἷὀὁὂὃὄὅὐὑὒὓὔὕὖὗὠὡὢὣὤὥὦὧὰάὲέὴήὶίὸόὺύὼώᾀᾁᾂᾃᾄᾅᾆᾇᾐᾑᾒᾓᾔᾕᾖᾗᾠᾡᾢᾣᾤᾥᾦᾧᾰᾱᾲᾳᾴᾶᾷιῂῃῄῆῇῐῑῒΐῖῗῠῡῢΰῤῥῦῧῲῳῴῶῷ';
const _unaccented =
    r'aaaaaaceeeeiiiinooooouuuuyyaaaccccdeeeeegggghiiiijklllnnnooorrrssssttuuuuuuwyzzzouaiouuuuuaaægkooʒjgnaæøaaeeiioorruusthaeooooyʹαεηιουωιιυυϒϒabbbcdddddeeeeefghhhhhiikkkllllmmmnnnnoooopprrrrsssssttttuuuuuvvwwwwwxxyzzzhtwyſaaaaaaaaaaaaeeeeeeeeiioooooooooooouuuuuuuyyyyααααααααεεεεεεηηηηηηηηιιιιιιιιοοοοοουυυυυυυυωωωωωωωωααεεηηιιοουυωωααααααααηηηηηηηηωωωωωωωωαααααααιηηηηηιιιιιιυυυυρρυυωωωωω';
const _special = <String, String>{
  'ß': 'ss',
  'æ': 'ae',
  'œ': 'oe',
  'ø': 'o',
  'ł': 'l',
  'đ': 'd',
  'ð': 'd',
  'þ': 'th',
  'ħ': 'h',
  'ı': 'i',
  'ŋ': 'n',
};
final _combining = RegExp(r'[\p{M}]', unicode: true);
final _decomposed = <String, String>{
  for (var i = 0; i < _accented.length; i++)
    _accented[i]: _unaccented[i].toLowerCase(),
};

String normalizeOfflineLexiconText(String value) {
  final out = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final letter = String.fromCharCode(rune);
    if (_combining.hasMatch(letter)) continue;
    final replacement = _special[letter];
    if (replacement != null) {
      out.write(replacement);
      continue;
    }
    final base = _decomposed[letter] ?? letter;
    out.write(_special[base] ?? base);
  }
  return out.toString();
}

/// Mirrors the server's accepted prefixed Strong-ID syntax and range.
String? normalizeOfflineStrongId(String input) {
  final match = RegExp(r'^\s*([GgHh])\s*0*(\d{1,5})\s*$').firstMatch(input);
  if (match == null) return null;
  final prefix = match[1]!.toUpperCase();
  final number = int.parse(match[2]!);
  if (number < 1 || number > (prefix == 'G' ? 6020 : 8674)) return null;
  return '$prefix$number';
}

/// Runs in a worker isolate only after the user asks for a full-text search.
List<String> buildOfflineLexiconSearchIndex(List<Json> entries) => [
  for (final entry in entries)
    normalizeOfflineLexiconText(
      [
        entry['strong'],
        entry['lemma'],
        entry['transliteration'],
        entry['pronunciation'],
        for (final key in [
          'definitionHtml',
          'derivationHtml',
          'kjvDefinitionHtml',
        ]) ...[
          html_parser.parseFragment(asString(entry[key])).text,
          html_parser
              .parseFragment(asString(asMap(entry['germanTranslation'])[key]))
              .text,
        ],
      ].map(asString).join(' '),
    ),
];
