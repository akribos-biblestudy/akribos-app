// Canonical German names and chapter counts from Akribos src/lib/bible.
class BibleBook {
  const BibleBook(this.id, this.name, this.abbreviation, this.chapters);
  final int id;
  final String name;
  final String abbreviation;
  final int chapters;
}

const bibleBooks = <BibleBook>[
  BibleBook(1, '1.Mose', '1Mo', 50),
  BibleBook(2, '2.Mose', '2Mo', 40),
  BibleBook(3, '3.Mose', '3Mo', 27),
  BibleBook(4, '4.Mose', '4Mo', 36),
  BibleBook(5, '5.Mose', '5Mo', 34),
  BibleBook(6, 'Josua', 'Jos', 24),
  BibleBook(7, 'Richter', 'Ri', 21),
  BibleBook(8, 'Rut', 'Ruth', 4),
  BibleBook(9, '1.Samuel', '1Sam', 31),
  BibleBook(10, '2.Samuel', '2Sam', 24),
  BibleBook(11, '1.Könige', '1Kön', 22),
  BibleBook(12, '2.Könige', '2Kön', 25),
  BibleBook(13, '1.Chronik', '1Chr', 29),
  BibleBook(14, '2.Chronik', '2Chr', 36),
  BibleBook(15, 'Esra', 'Esra', 10),
  BibleBook(16, 'Nehemia', 'Neh', 13),
  BibleBook(17, 'Esther', 'Est', 10),
  BibleBook(18, 'Hiob', 'Hi', 42),
  BibleBook(19, 'Psalmen', 'Ps', 150),
  BibleBook(20, 'Sprüche', 'Spr', 31),
  BibleBook(21, 'Prediger', 'Pred', 12),
  BibleBook(22, 'Hoheslied', 'Hld', 8),
  BibleBook(23, 'Jesaja', 'Jes', 66),
  BibleBook(24, 'Jeremia', 'Jer', 52),
  BibleBook(25, 'Klagelieder', 'Klgl', 5),
  BibleBook(26, 'Hesekiel', 'Hes', 48),
  BibleBook(27, 'Daniel', 'Dan', 12),
  BibleBook(28, 'Hosea', 'Hos', 14),
  BibleBook(29, 'Joel', 'Joel', 4),
  BibleBook(30, 'Amos', 'Am', 9),
  BibleBook(31, 'Obadja', 'Obd', 1),
  BibleBook(32, 'Jona', 'Jona', 4),
  BibleBook(33, 'Micha', 'Mi', 7),
  BibleBook(34, 'Nahum', 'Nah', 3),
  BibleBook(35, 'Habakuk', 'Hab', 3),
  BibleBook(36, 'Zefanja', 'Zef', 3),
  BibleBook(37, 'Haggai', 'Hag', 2),
  BibleBook(38, 'Sacharja', 'Sach', 14),
  BibleBook(39, 'Maleachi', 'Mal', 3),
  BibleBook(40, 'Matthäus', 'Mt', 28),
  BibleBook(41, 'Markus', 'Mk', 16),
  BibleBook(42, 'Lukas', 'Lk', 24),
  BibleBook(43, 'Johannes', 'Joh', 21),
  BibleBook(44, 'Apostelgeschichte', 'Apg', 28),
  BibleBook(45, 'Römer', 'Röm', 16),
  BibleBook(46, '1.Korinther', '1Kor', 16),
  BibleBook(47, '2.Korinther', '2Kor', 13),
  BibleBook(48, 'Galater', 'Gal', 6),
  BibleBook(49, 'Epheser', 'Eph', 6),
  BibleBook(50, 'Philipper', 'Phil', 4),
  BibleBook(51, 'Kolosser', 'Kol', 4),
  BibleBook(52, '1.Thessalonicher', '1Thess', 5),
  BibleBook(53, '2.Thessalonicher', '2Thess', 3),
  BibleBook(54, '1.Timotheus', '1Tim', 6),
  BibleBook(55, '2.Timotheus', '2Tim', 4),
  BibleBook(56, 'Titus', 'Tit', 3),
  BibleBook(57, 'Philemon', 'Phlm', 1),
  BibleBook(58, 'Hebräer', 'Hebr', 13),
  BibleBook(59, 'Jakobus', 'Jak', 5),
  BibleBook(60, '1.Petrus', '1Petr', 5),
  BibleBook(61, '2.Petrus', '2Petr', 3),
  BibleBook(62, '1.Johannes', '1Joh', 5),
  BibleBook(63, '2.Johannes', '2Joh', 1),
  BibleBook(64, '3.Johannes', '3Joh', 1),
  BibleBook(65, 'Judas', 'Jud', 1),
  BibleBook(66, 'Offenbarung', 'Offb', 22),
];

String bookName(int id) =>
    id >= 1 && id <= bibleBooks.length ? bibleBooks[id - 1].name : '$id';
String referenceLabel(Map<String, dynamic> ref) {
  final id = (ref['book'] as num?)?.toInt() ?? 43;
  final short = id >= 1 && id <= bibleBooks.length
      ? bibleBooks[id - 1].abbreviation
      : '$id';
  final chapter = ref['chapter'] ?? 1;
  final verse = ref['verse'];
  final end = ref['verseEnd'];
  return '$short$chapter${verse == null ? '' : ',$verse'}${end == null ? '' : '-$end'}';
}
