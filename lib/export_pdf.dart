/// Turns the book into a printable PDF.
///
/// Any page size: the book's own 13.8 x 9.6 inches by default, A4, or a custom
/// size. VIP records come first, one to a page; everyone else follows, four
/// to a page. Every record is scaled to fit its space, so the layout holds on
/// any paper rather than being tuned to one size.
///
/// The handwriting is the record, so every field is printed as the image the
/// visitor wrote. Only the date is text, because it is picked, not written.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'record.dart';

const _inch = PdfPageFormat.inch;

/// 13.8 wide by 9.6 tall - wider than tall, so landscape. The default.
final logbookPageFormat = pageFormat(13.8 * _inch, 9.6 * _inch);

/// A page of the given size in points (1/72 inch), with a margin that suits
/// it: half an inch on full-size paper, less on small paper so a tiny custom
/// page is not mostly margin.
PdfPageFormat pageFormat(double width, double height) {
  final shortest = min(width, height);
  final margin = min(0.5 * _inch, shortest * 0.06);
  return PdfPageFormat(width, height, marginAll: margin);
}

/// Same proportions as the pads on screen, so a field prints at the shape it
/// was written in rather than being squashed or stretched.
const _ratios = <String, double>{
  'name': 3.8,
  'place': 3.8,
  'comment': 4.6,
  'appointment': 10.5,
  'signature': 2.6,
};

/// Non-VIP records per page, as a grid. Change these two to change the count.
const _gridColumns = 2;
const _gridRows = 2;
const _perPage = _gridColumns * _gridRows;

const _cardPadding = 8.0;
const _cardGap = 12.0;

/// A record with its handwriting loaded, ready to lay out.
class ExportEntry {
  const ExportEntry(this.record, this.images, {this.vip = false});
  final LogRecord record;
  final Map<String, Uint8List?> images;

  /// Chosen on the export screen for this export only. Not part of the
  /// record, and never stored.
  final bool vip;
}

/// Build the whole document on pages of [format]. VIP records are printed
/// first, then the rest; within each group in serial order, the order a paper
/// book fills in.
Future<Uint8List> buildLogbookPdf(
  List<ExportEntry> entries, {
  PdfPageFormat? format,
}) async {
  final page = format ?? logbookPageFormat;
  final byDate = [...entries]..sort((a, b) {
      final bySerial = a.record.serial.compareTo(b.record.serial);
      return bySerial != 0
          ? bySerial
          : a.record.createdAt.compareTo(b.record.createdAt);
    });
  final vip = byDate.where((e) => e.vip).toList();
  final others = byDate.where((e) => !e.vip).toList();

  final doc = pw.Document(title: 'Visitors Book');

  for (final entry in vip) {
    doc.addPage(
      pw.Page(
        pageFormat: page,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _pageHeader('VIP VISITOR', entry.record.createdAt),
            pw.SizedBox(height: 12),
            // Built at full width, then scaled down to whatever height is
            // left, so a VIP entry always fills its page without overflowing.
            pw.Expanded(
              child: pw.FittedBox(
                fit: pw.BoxFit.contain,
                alignment: pw.Alignment.topLeft,
                child: _recordBody(
                  entry,
                  width: page.availableWidth,
                  gap: 14,
                  labelSize: 10,
                ),
              ),
            ),
            _pageFooter(context),
          ],
        ),
      ),
    );
  }

  // A fixed grid per page rather than letting cards flow: a record at its
  // natural width is too tall for two rows of two, so each one is scaled to
  // fit its cell instead. That makes the count per page exact, whatever the
  // handwriting looks like.
  final cellWidth =
      (page.availableWidth - (_gridColumns - 1) * _cardGap) / _gridColumns;
  final innerWidth = cellWidth - 2 * _cardPadding;

  for (var start = 0; start < others.length; start += _perPage) {
    final onPage = others.sublist(start, min(start + _perPage, others.length));
    doc.addPage(
      pw.Page(
        pageFormat: page,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _sectionTitle('VISITORS'),
            pw.SizedBox(height: 10),
            pw.Expanded(
              child: pw.Column(
                children: [
                  for (var r = 0; r < _gridRows; r++) ...[
                    if (r > 0) pw.SizedBox(height: _cardGap),
                    pw.Expanded(
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          for (var c = 0; c < _gridColumns; c++) ...[
                            if (c > 0) pw.SizedBox(width: _cardGap),
                            pw.Expanded(
                              child: _cell(
                                r * _gridColumns + c < onPage.length
                                    ? onPage[r * _gridColumns + c]
                                    : null,
                                innerWidth,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _pageFooter(context),
          ],
        ),
      ),
    );
  }

  return doc.save();
}

pw.Widget _sectionTitle(String text) => pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 14,
        letterSpacing: 3,
        fontWeight: pw.FontWeight.bold,
      ),
    );

pw.Widget _pageHeader(String title, DateTime recorded) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        _sectionTitle(title),
        pw.Text(
          'Recorded ${_stamp(recorded)}',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      ],
    );

pw.Widget _pageFooter(pw.Context context) => pw.Container(
      alignment: pw.Alignment.centerRight,
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Text(
        'Page ${context.pageNumber} of ${context.pagesCount}',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
    );

/// One grid cell holding a non-VIP record: the same layout as a VIP page,
/// built at the cell's width and then scaled down to the cell's height. An
/// empty cell (the last page may not be full) is left blank, with no border.
pw.Widget _cell(ExportEntry? entry, double innerWidth) {
  if (entry == null) return pw.SizedBox();
  // The border goes round the record, not the cell, and the whole card is
  // scaled and centred in the cell - so on paper whose cells are a different
  // shape from a record (A4 portrait, say) the card still fits snugly rather
  // than sitting at the top of a mostly empty box.
  return pw.FittedBox(
    fit: pw.BoxFit.contain,
    alignment: pw.Alignment.center,
    child: pw.Container(
      padding: const pw.EdgeInsets.all(_cardPadding),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            _stamp(entry.record.createdAt),
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 4),
          _recordBody(entry, width: innerWidth, gap: 8, labelSize: 8),
        ],
      ),
    ),
  );
}

/// Name, place and date across the top; comment and appointment full width;
/// signature small and to the right - the same arrangement as the form.
pw.Widget _recordBody(
  ExportEntry entry, {
  required double width,
  required double gap,
  required double labelSize,
}) {
  final third = (width - 2 * gap) / 3;
  return pw.SizedBox(
    width: width,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _imageField(entry, 'name', third, labelSize),
            pw.SizedBox(width: gap),
            _imageField(entry, 'place', third, labelSize),
            pw.SizedBox(width: gap),
            _dateField(entry, third, labelSize),
          ],
        ),
        pw.SizedBox(height: gap),
        _imageField(entry, 'comment', width, labelSize),
        pw.SizedBox(height: gap),
        _imageField(entry, 'appointment', width, labelSize),
        pw.SizedBox(height: gap),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: _imageField(entry, 'signature', width * 0.4, labelSize),
        ),
      ],
    ),
  );
}

pw.Widget _label(String text, double size) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: size,
          letterSpacing: 1,
          color: PdfColors.grey700,
        ),
      ),
    );

pw.Widget _imageField(
  ExportEntry entry,
  String field,
  double width,
  double labelSize,
) {
  final png = entry.images[field];
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      _label(field.toUpperCase(), labelSize),
      pw.Container(
        width: width,
        height: width / _ratios[field]!,
        // drawn over the image, not under it: the handwriting PNG has an
        // opaque white background that otherwise paints the outline out
        foregroundDecoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        ),
        child: png == null
            ? pw.SizedBox()
            : pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain),
      ),
    ],
  );
}

/// The date is printed as text. Records made before the picker existed may
/// only have a handwritten date, so fall back to that image.
pw.Widget _dateField(ExportEntry entry, double width, double labelSize) {
  final text = entry.record.ocr['date'];
  final png = entry.images['date'];
  final height = width / _ratios['name']!;

  final pw.Widget content;
  if (text != null && text.isNotEmpty) {
    content = pw.Text(text, style: pw.TextStyle(fontSize: height * 0.4));
  } else if (png != null) {
    content = pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain);
  } else {
    content = pw.SizedBox();
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      _label('DATE', labelSize),
      pw.Container(
        width: width,
        height: height,
        alignment: pw.Alignment.centerLeft,
        padding: pw.EdgeInsets.symmetric(horizontal: height * 0.15),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        ),
        child: content,
      ),
    ],
  );
}

String _stamp(DateTime t) {
  final local = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
