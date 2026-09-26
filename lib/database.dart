/// Local storage: SQLite on the tablet, no server.
///
/// The two tables from the spec survive the move:
///   logbook_raw     - the submission exactly as written (PNG bytes per field)
///   logbook_refined - the same record plus the recognised text
///
/// Two departures from the web schema, both deliberate:
///  * ids are UUID strings, not auto-increment integers. Two tablets would
///    both create "record 17"; this is what makes peer-to-peer sync possible
///    later without rewriting the data.
///  * images live only in logbook_raw and are joined when needed, rather than
///    copied into both tables. The web version could copy cheaply because it
///    stored short paths; here the bytes are in the row.
library;

import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'record.dart';

const imageFields = ['name', 'date', 'place', 'comment', 'appointment', 'signature'];
const ocrFields = ['name', 'date', 'place'];

class LogbookDatabase {
  LogbookDatabase._(this._db);

  final Database _db;
  static LogbookDatabase? _instance;

  static Future<LogbookDatabase> open() async {
    if (_instance != null) return _instance!;
    final path = '${await getDatabasesPath()}/logbook.db';
    final db = await openDatabase(
      path,
      version: 1,
      onConfigure: (db) => db.execute('pragma foreign_keys = on'),
      onCreate: (db, _) async {
        await db.execute('''
          create table logbook_raw (
            id          text primary key,
            created_at  text not null,
            name        blob,
            date        blob,
            place       blob,
            comment     blob,
            signature   blob,
            appointment blob
          )
        ''');
        await db.execute('''
          create table logbook_refined (
            id         text primary key,
            raw_id     text not null references logbook_raw(id) on delete cascade,
            created_at text not null,
            name_ocr   text,
            date_ocr   text,
            place_ocr  text
          )
        ''');
        await db.execute(
          'create index logbook_refined_created_at_idx '
          'on logbook_refined (created_at desc)',
        );
      },
    );
    return _instance = LogbookDatabase._(db);
  }

  /// Write the submission to table 1, then its recognised copy to table 2.
  Future<void> insert(LogRecord record) async {
    await _db.transaction((txn) async {
      await txn.insert('logbook_raw', {
        'id': record.id,
        'created_at': record.createdAt.toIso8601String(),
        for (final field in imageFields) field: record.images[field],
      });
      await txn.insert('logbook_refined', {
        'id': record.id,
        'raw_id': record.id,
        'created_at': record.createdAt.toIso8601String(),
        for (final field in ocrFields) '${field}_ocr': record.ocr[field],
      });
    });
  }

  /// Every record, newest first, without the image bytes.
  ///
  /// The list view only needs the recognised text; loading six PNGs per record
  /// to render a list would be wasteful.
  Future<List<LogRecord>> listRecords() async {
    final rows = await _db.rawQuery('''
      select id, raw_id, created_at, name_ocr, date_ocr, place_ocr
      from logbook_refined
      order by created_at desc
    ''');
    return rows.map(LogRecord.fromRow).toList();
  }

  /// The handwriting for one record, fetched only when it is shown.
  Future<Map<String, Uint8List?>> imagesFor(String rawId) async {
    final rows = await _db.query(
      'logbook_raw',
      columns: imageFields,
      where: 'id = ?',
      whereArgs: [rawId],
      limit: 1,
    );
    if (rows.isEmpty) return {};
    final row = rows.first;
    return {
      for (final field in imageFields) field: row[field] as Uint8List?,
    };
  }

  Future<int> count() async {
    final rows = await _db.rawQuery('select count(*) as n from logbook_refined');
    return (rows.first['n'] as int?) ?? 0;
  }
}
