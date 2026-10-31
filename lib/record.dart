import 'dart:math';
import 'dart:typed_data';

/// One visit: six handwritten fields, plus what the recogniser made of the
/// three that are searchable.
class LogRecord {
  LogRecord({
    required this.id,
    required this.rawId,
    required this.createdAt,
    this.serial = 0,
    this.time = '',
    this.images = const {},
    this.ocr = const {},
  });

  factory LogRecord.fromRow(Map<String, Object?> row) => LogRecord(
        id: row['id'] as String,
        rawId: row['raw_id'] as String? ?? row['id'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
        serial: row['serial'] as int? ?? 0,
        time: row['time'] as String? ?? '',
        ocr: {
          'name': row['name_ocr'] as String?,
          'date': row['date_ocr'] as String?,
          'place': row['place_ocr'] as String?,
        },
      );

  final String id;
  final String rawId;
  final DateTime createdAt;

  /// Hidden fields, filled in by the database when the record is saved and
  /// never shown on screen: the entry's number in the book (1, 2, 3...) and
  /// the time it was written (HH:mm:ss).
  final int serial;
  final String time;

  /// PNG bytes per field. Empty in list views, which do not need them.
  final Map<String, Uint8List?> images;

  /// Recognised text for name, date and place.
  final Map<String, String?> ocr;

  /// Internal row key. Random rather than sequential only so that it carries
  /// no meaning - the visible-order number is [serial].
  static String newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
