/// Local storage: one SQLite file on this tablet. Nothing is shared, synced
/// or sent anywhere.
///
/// The two tables from the spec:
///   logbook_raw     - the submission exactly as written (PNG bytes per field)
///   logbook_refined - the same record plus the recognised text
///
/// Images live only in logbook_raw and are joined when needed, rather than
/// copied into both tables, since the bytes are in the row.
///
/// Both tables carry two hidden fields, filled in automatically on save and
/// never shown in the app: serial (the entry's number in the book, 1, 2, 3...)
/// and time (when it was written, HH:mm:ss).
library;

import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'record.dart';

const imageFields = ['name', 'date', 'place', 'comment', 'appointment', 'signature'];
const ocrFields = ['name', 'date', 'place'];

/// Bump when the schema changes, and add a step to [_upgrade].
///
///   1  original two tables
///   2  added logbook_refined.vip
///   3  removed it again - VIP is chosen at export time, not stored
///   4  added hidden serial and time to both tables
const _schemaVersion = 4;

/// What a list view reads from logbook_refined.
const _refinedColumns =
    'id, raw_id, created_at, serial, time, name_ocr, date_ocr, place_ocr';

class LogbookDatabase {
  LogbookDatabase._(this._db);

  final Database _db;
  static LogbookDatabase? _instance;

  static Future<LogbookDatabase> open() async {
    if (_instance != null) return _instance!;
    final path = '${await getDatabasesPath()}/logbook.db';
    final db = await openDatabase(
      path,
      version: _schemaVersion,
      onConfigure: (db) => db.execute('pragma foreign_keys = on'),
      onCreate: _create,
      onUpgrade: _upgrade,
    );
    return _instance = LogbookDatabase._(db);
  }

  /// A fresh install gets the current schema directly.
  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      create table logbook_raw (
        id          text primary key,
        created_at  text not null,
        serial      integer not null,
        time        text not null,
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
        serial     integer not null,
        time       text not null,
        name_ocr   text,
        date_ocr   text,
        place_ocr  text
      )
    ''');
    await _createIndexes(db);
  }

  static Future<void> _createIndexes(DatabaseExecutor db) async {
    await db.execute(
      'create index if not exists logbook_refined_created_at_idx '
      'on logbook_refined (created_at desc)',
    );
    // a serial number belongs to exactly one entry
    await db.execute(
      'create unique index if not exists logbook_raw_serial_idx '
      'on logbook_raw (serial)',
    );
  }

  /// An existing install is moved forward one step at a time. sqflite runs
  /// this inside a transaction: if any step fails, the whole upgrade rolls
  /// back and the data is left exactly as it was.
  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 3) {
      // Drop the vip column added in version 2. Android's SQLite cannot be
      // relied on for ALTER TABLE ... DROP COLUMN, so rebuild the table with
      // the version-3 shape and copy every row across. Naming the columns
      // makes this safe from version 1 too, which never had vip.
      const v3Columns = 'id, raw_id, created_at, name_ocr, date_ocr, place_ocr';
      await db.execute('''
        create table logbook_refined_new (
          id         text primary key,
          raw_id     text not null references logbook_raw(id) on delete cascade,
          created_at text not null,
          name_ocr   text,
          date_ocr   text,
          place_ocr  text
        )
      ''');
      await db.execute(
        'insert into logbook_refined_new ($v3Columns) '
        'select $v3Columns from logbook_refined',
      );
      await db.execute('drop table logbook_refined');
      await db.execute(
        'alter table logbook_refined_new rename to logbook_refined',
      );
    }

    if (from < 4) {
      for (final table in ['logbook_raw', 'logbook_refined']) {
        await db.execute(
          'alter table $table add column serial integer not null default 0',
        );
        await db.execute(
          "alter table $table add column time text not null default ''",
        );
      }

      // Number existing entries in the order they were written. Ties on the
      // timestamp are broken by id so every entry still gets its own number.
      await db.execute('''
        update logbook_raw set serial = (
          select count(*) from logbook_raw earlier
          where earlier.created_at < logbook_raw.created_at
             or (earlier.created_at = logbook_raw.created_at
                 and earlier.id <= logbook_raw.id)
        )
      ''');
      // created_at is local time as yyyy-MM-ddTHH:mm:ss.ffffff; characters
      // 12-19 are exactly the time of day it was written
      await db.execute(
        'update logbook_raw set time = substr(created_at, 12, 8)',
      );
      await db.execute('''
        update logbook_refined set
          serial = (select serial from logbook_raw
                    where logbook_raw.id = logbook_refined.raw_id),
          time   = (select time from logbook_raw
                    where logbook_raw.id = logbook_refined.raw_id)
      ''');
    }

    await _createIndexes(db);
  }

  /// Write the submission to table 1, then its recognised copy to table 2.
  /// The serial number and time are assigned here, not by the caller.
  Future<void> insert(LogRecord record) async {
    await _db.transaction((txn) async {
      final next = await txn.rawQuery(
        'select coalesce(max(serial), 0) + 1 as n from logbook_raw',
      );
      final serial = next.first['n'] as int;
      final time = _timeOfDay(record.createdAt);

      await txn.insert('logbook_raw', {
        'id': record.id,
        'created_at': record.createdAt.toIso8601String(),
        'serial': serial,
        'time': time,
        for (final field in imageFields) field: record.images[field],
      });
      await txn.insert('logbook_refined', {
        'id': record.id,
        'raw_id': record.id,
        'created_at': record.createdAt.toIso8601String(),
        'serial': serial,
        'time': time,
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
      select $_refinedColumns
      from logbook_refined
      order by serial desc
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

String _timeOfDay(DateTime t) {
  final local = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
