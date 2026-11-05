import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:logbook/export_pdf.dart';
import 'package:logbook/record.dart';
import 'package:pdf/pdf.dart';

Uint8List _png({int? inkX, int? inkY}) {
  final image = img.Image(width: 400, height: 100);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  if (inkX != null) {
    img.fillRect(
      image,
      x1: inkX,
      y1: inkY!,
      x2: inkX + 19,
      y2: inkY + 9,
      color: img.ColorRgb8(0, 0, 0),
    );
  }
  return img.encodePng(image);
}

ExportEntry _entry(int serial, {bool vip = false}) => ExportEntry(
  LogRecord(
    id: '$serial',
    rawId: '$serial',
    createdAt: DateTime(2026, 11, 5),
    serial: serial,
    ocr: {'date': '05/11/2026'},
  ),
  {
    'name': _png(inkX: 50, inkY: 40),
    'place': _png(inkX: 10, inkY: 10),
    'comment': _png(inkX: 100, inkY: 20),
    'appointment': _png(),
    'signature': null,
  },
  vip: vip,
);

/// Pages in the document, from its uncompressed page objects.
int _pages(Uint8List pdf) =>
    RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(pdf)).length;

void main() {
  group('trimToInk', () {
    test('crops to the ink plus a small margin', () {
      final ink = trimToInk(_png(inkX: 50, inkY: 40))!;
      expect(ink.width, 28);
      expect(ink.height, 18);
      expect(ink.sourceWidth, 400);
      expect(ink.rgba.length, 28 * 18 * 4);
    });

    test('a pad nobody wrote on has no ink', () {
      expect(trimToInk(_png()), isNull);
    });
  });

  group('TableLayout', () {
    test('holds several rows and a larger VIP row on every paper', () {
      for (final page in [
        logbookPageFormat,
        pageFormat(PdfPageFormat.a4.width, PdfPageFormat.a4.height),
        pageFormat(PdfPageFormat.a4.height, PdfPageFormat.a4.width),
      ]) {
        final layout = TableLayout(page);
        expect(layout.rowsPerPage, greaterThan(1));
        expect(layout.vipRowHeight, greaterThan(layout.rowHeight));
      }
    });

    test('a tiny page still fits a row', () {
      final layout = TableLayout(pageFormat(144, 144));
      expect(layout.rowsPerPage, greaterThanOrEqualTo(1));
      expect(layout.rowHeight, greaterThan(0));
    });
  });

  group('paginate', () {
    test('a full page of equal rows stays on one page', () {
      expect(paginate([10, 10, 10], 30), [
        [0, 1, 2],
      ]);
    });

    test('a tall row moves to the next page rather than splitting', () {
      expect(paginate([10, 25, 10], 30), [
        [0],
        [1],
        [2],
      ]);
    });

    test('a row taller than a page still gets a page', () {
      expect(paginate([50, 10], 30), [
        [0],
        [1],
      ]);
    });
  });

  group('InkImage.fitted', () {
    test('scales down to the target, keeping the shape', () {
      final ink = InkImage(Uint8List(400 * 100 * 4), 400, 100, 400);
      final small = ink.fitted(200);
      expect(small.width, 200);
      expect(small.height, 50);
      expect(small.rgba.length, 200 * 50 * 4);
    });

    test('never enlarges', () {
      final ink = InkImage(Uint8List(40 * 10 * 4), 40, 10, 40);
      expect(ink.fitted(200), same(ink));
    });
  });

  group('buildLogbookPdf', () {
    test('a tall comment makes its row taller, leaving fewer on the page',
        () async {
      // about as tall as the column is wide once fitted to it
      final image = img.Image(width: 400, height: 400);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(
        image,
        x1: 0,
        y1: 0,
        x2: 399,
        y2: 399,
        color: img.ColorRgb8(0, 0, 0),
      );
      final tall = img.encodePng(image);
      final layout = TableLayout(logbookPageFormat);
      final pdf = await buildLogbookPdf([
        for (var i = 1; i <= layout.rowsPerPage; i++)
          ExportEntry(
            _entry(i).record,
            {'comment': i == 1 ? tall : _png(inkX: 10, inkY: 10)},
          ),
      ]);
      expect(_pages(pdf), 2);
    });

    test('each VIP gets a page, the rest share pages by row count', () async {
      final perPage = TableLayout(logbookPageFormat).rowsPerPage;
      final pdf = await buildLogbookPdf([
        for (var i = 1; i <= perPage + 1; i++) _entry(i),
        _entry(100, vip: true),
        _entry(101, vip: true),
      ]);
      expect(_pages(pdf), 4);
    });

    test('exactly one full page of visitors takes one page', () async {
      final perPage = TableLayout(logbookPageFormat).rowsPerPage;
      final pdf = await buildLogbookPdf([
        for (var i = 1; i <= perPage; i++) _entry(i),
      ]);
      expect(_pages(pdf), 1);
    });
  });
}
