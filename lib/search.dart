/// Searching records by name, date and place.
///
/// A direct port of the Python search.py from the web version, including the
/// thresholds, which were measured rather than guessed. See the comments.
library;

const searchFields = ['name', 'date', 'place'];

/// Fields where a near-miss is a wrong answer, not a mangled read. "5/9/26"
/// and "5/4/26" are 0.83 similar but are different days, so dates match by
/// substring only - never fuzzily.
const exactFields = ['date'];

/// Measured on real OCR output: genuine reads of "Mumbai"/"Shourya" scored
/// 0.62-0.73, while wrong records ("Delhi", "Weuerg") topped out at 0.31. This
/// sits in that gap. On-device recognition is far more accurate than the
/// Tesseract output this was tuned against, so it could be tightened.
const fuzzyThreshold = 0.55;

/// Short queries fuzzy-match almost anything, so require them to be substrings.
const minFuzzyQuery = 3;

final _punctuation = RegExp(r'[^\w\s]+');

/// Dates are written every which way - 14/09/2026, 14/9/26, 14-9-26 - so both
/// the stored read and the query are reduced to dd/mm/yyyy before comparing.
/// Day first, matching how the book is written.
final _dateDmy = RegExp(r'(\d{1,2})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{2,4})');
final _dateIso = RegExp(r'(\d{4})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{1,2})');

/// A two-digit year means this century. Fine for a visitors book.
const _century = 2000;

/// Read a year from 2, 3 or 4 digits, tolerating trailing recognition noise.
int _year(String digits) {
  if (digits.length >= 4) {
    final head = digits.substring(0, 4);
    if (head.startsWith('19') || head.startsWith('20')) return int.parse(head);
  }
  return _century + int.parse(digits.substring(0, 2));
}

/// Reduce any recognisable date to dd/mm/yyyy, or null if there is none.
String? canonicalDate(String? text) {
  if (text == null || text.isEmpty) return null;

  int day, month, year;
  final iso = _dateIso.firstMatch(text);
  if (iso != null) {
    year = int.parse(iso.group(1)!);
    month = int.parse(iso.group(2)!);
    day = int.parse(iso.group(3)!);
  } else {
    final dmy = _dateDmy.firstMatch(text);
    if (dmy == null) return null;
    day = int.parse(dmy.group(1)!);
    month = int.parse(dmy.group(2)!);
    year = _year(dmy.group(3)!);
  }

  if (day < 1 || day > 31 || month < 1 || month > 12) return null;
  return '${day.toString().padLeft(2, '0')}/'
      '${month.toString().padLeft(2, '0')}/'
      '${year.toString().padLeft(4, '0')}';
}

/// Lowercase, drop punctuation, collapse whitespace.
String normalise(String? text) {
  if (text == null || text.isEmpty) return '';
  return text
      .toLowerCase()
      .replaceAll(_punctuation, ' ')
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .join(' ');
}

/// Ratio of matching characters, the same measure Python's difflib uses.
double _ratio(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1.0;
  if (a.isEmpty || b.isEmpty) return 0.0;
  final matches = _matchingBlocks(a, b);
  return 2.0 * matches / (a.length + b.length);
}

/// Total length of the matching blocks, found recursively on the longest
/// common contiguous run - the same approach as difflib's SequenceMatcher.
int _matchingBlocks(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;

  var bestI = 0, bestJ = 0, bestLen = 0;
  final lengths = List<int>.filled(b.length + 1, 0);

  for (var i = 0; i < a.length; i++) {
    final next = List<int>.filled(b.length + 1, 0);
    for (var j = 0; j < b.length; j++) {
      if (a[i] == b[j]) {
        next[j + 1] = lengths[j] + 1;
        if (next[j + 1] > bestLen) {
          bestLen = next[j + 1];
          bestI = i - bestLen + 1;
          bestJ = j - bestLen + 1;
        }
      }
    }
    lengths.setAll(0, next);
  }

  if (bestLen == 0) return 0;
  return bestLen +
      _matchingBlocks(a.substring(0, bestI), b.substring(0, bestJ)) +
      _matchingBlocks(a.substring(bestI + bestLen), b.substring(bestJ + bestLen));
}

/// Best match of the query against the value, its tokens, or its letters.
///
/// The spaces-removed comparison matters: recognition can break words apart,
/// and rejoining recovers the match.
double similarity(String query, String value) {
  if (query.isEmpty || value.isEmpty) return 0.0;
  final candidates = <String>[
    value,
    value.replaceAll(' ', ''),
    ...value.split(' '),
  ];
  var best = 0.0;
  for (final candidate in candidates) {
    if (candidate.isEmpty) continue;
    final score = _ratio(query, candidate);
    if (score > best) best = score;
  }
  return best;
}

/// Does one record field satisfy one search term?
bool fieldMatches(String query, String? value, {bool fuzzy = true}) {
  final q = normalise(query);
  final v = normalise(value);
  if (q.isEmpty) return true; // an empty term filters nothing
  if (v.isEmpty) return false; // nothing was read, so it cannot match
  if (v.contains(q) || v.replaceAll(' ', '').contains(q)) return true;
  if (!fuzzy || q.length < minFuzzyQuery) return false;
  return similarity(q, v) >= fuzzyThreshold;
}

/// Compare two dates by meaning rather than spelling.
bool dateMatches(String query, String? value) {
  final qDate = canonicalDate(query);
  final vDate = canonicalDate(value);
  if (qDate != null && vDate != null) return qDate == vDate;
  // a partial query like "14/09", or an unreadable value
  return fieldMatches(query, value, fuzzy: false);
}

/// How well a record answers the query, for ordering results.
double matchScore(Map<String, String> criteria, Map<String, String?> ocr) {
  final scores = <double>[];
  criteria.forEach((field, query) {
    if (query.trim().isEmpty) return;
    scores.add(similarity(normalise(query), normalise(ocr['${field}_ocr'])));
  });
  if (scores.isEmpty) return 0;
  return scores.reduce((a, b) => a + b) / scores.length;
}
