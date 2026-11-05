/// Turns the book into a printable PDF, laid out as a table.
///
/// Any page size: the book's own 13.8 x 9.6 inches by default, A4, or a custom
/// size. VIP records come first, each as a single row on its own page; everyone
/// else follows, as many rows to a page as the paper holds. Every measurement
/// comes from the page, so the table holds on any paper rather than being tuned
/// to one size.
///
/// The handwriting is the record, so every field is printed as the image the
/// visitor wrote, cropped to the ink so that it is as large as its column
/// allows. Only the date is text, because it is picked, not written.
library;

import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
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

/// The table's columns, left to right, as shares of the page width. [field] is
/// the name the handwriting is stored under.
const _columns = <({String field, String title, double share})>[
  (field: 'date', title: 'DATE', share: 0.09),
  (field: 'name', title: 'NAME', share: 0.19),
  (field: 'place', title: 'PLACE', share: 0.14),
  (field: 'comment', title: 'COMMENT', share: 0.30),
  (field: 'appointment', title: 'APPOINTMENT', share: 0.15),
  (field: 'signature', title: 'SIGNATURE', share: 0.13),
];

/// A row is tall enough for the comment at the shape it was written in; the
/// comment is the field with the most to show.
const _commentRatio = 4.6;
const _cellPadding = 4.0;

const _titleHeight = 26.0;
const _headerHeight = 20.0;
const _footerHeight = 18.0;

/// A VIP's row is this many times the height of an ordinary row.
const _vipRowScale = 3.0;

/// One-line fields stop growing at this share of an ordinary row's height, so
/// a short word such as a place name is not printed huge next to a long one.
const _lineHeightShare = 0.35;

/// A comment may grow to this many times the size it would be uncropped, which
/// keeps a one-word comment in proportion with a full one.
const _commentMaxEnlargement = 2.5;

/// Darker than this on every channel counts as ink. Well below any background
/// a record has been captured on, and well above the pen.
const _inkThreshold = 170;

/// Space kept around the ink when cropping, in image pixels.
const _inkMargin = 4;

/// Handwriting is embedded at this resolution at most: sharp on paper, without
/// a long book's full-size captures filling the tablet's memory.
const _printDpi = 300;

/// A record with its handwriting loaded, ready to lay out.
class ExportEntry {
  const ExportEntry(this.record, this.images, {this.vip = false});
  final LogRecord record;
  final Map<String, Uint8List?> images;

  /// Chosen on the export screen for this export only. Not part of the
  /// record, and never stored.
  final bool vip;
}

/// How rows are arranged on a page of a given format.
class TableLayout {
  factory TableLayout(PdfPageFormat page) {
    final available =
        page.availableHeight - _titleHeight - _headerHeight - _footerHeight;
    final commentWidth =
        page.availableWidth *
        _columns.firstWhere((c) => c.field == 'comment').share;
    final natural = commentWidth / _commentRatio + 2 * _cellPadding;
    final rows = max(1, available ~/ natural);
    // shared out, so that a full page is filled to the bottom
    final height = available / rows;
    return TableLayout._(
      available,
      rows,
      height,
      min(available, height * _vipRowScale),
    );
  }

  const TableLayout._(
    this.available,
    this.rowsPerPage,
    this.rowHeight,
    this.vipRowHeight,
  );

  /// Height the rows of one page share.
  final double available;

  /// How many ordinary rows fit. A long comment makes its row taller, so a
  /// page holding one has fewer.
  final int rowsPerPage;
  final double rowHeight;
  final double vipRowHeight;
}

/// Split rows of the given heights into pages, as index ranges in order. A row
/// is never split, and one taller than a page still gets a page.
List<List<int>> paginate(List<double> heights, double available) {
  final pages = <List<int>>[];
  var used = 0.0;
  for (var i = 0; i < heights.length; i++) {
    // a sliver of tolerance: a full page's rows add up to exactly [available]
    if (pages.isEmpty || used + heights[i] > available + 0.01) {
      pages.add([]);
      used = 0;
    }
    pages.last.add(i);
    used += heights[i];
  }
  return pages;
}

/// The height a row needs for its comment at full column width, so a long
/// comment is printed as large as a short one rather than squeezed to fit.
double _rowHeightFor(
  ExportEntry entry,
  PdfPageFormat page,
  double minimum,
  double available,
) {
  final png = entry.images['comment'];
  final ink = png == null ? null : trimToInk(png);
  if (ink == null) return minimum;
  final share = _columns.firstWhere((c) => c.field == 'comment').share;
  final width = page.availableWidth * share - 2 * _cellPadding;
  final scale = min(
    width / ink.width,
    _commentMaxEnlargement * width / ink.sourceWidth,
  );
  final needed = ink.height * scale + 2 * _cellPadding;
  return min(max(minimum, needed), available);
}

/// [buildLogbookPdf] off the main thread: decoding every record's handwriting
/// would otherwise freeze the screen.
Future<Uint8List> buildLogbookPdfInBackground(
  List<ExportEntry> entries, {
  PdfPageFormat? format,
}) => Isolate.run(() => buildLogbookPdf(entries, format: format));

/// Build the whole document on pages of [format]. VIP records are printed
/// first, then the rest; within each group in serial order, the order a paper
/// book fills in.
Future<Uint8List> buildLogbookPdf(
  List<ExportEntry> entries, {
  PdfPageFormat? format,
}) async {
  final page = format ?? logbookPageFormat;
  final layout = TableLayout(page);
  final inOrder = [...entries]
    ..sort((a, b) {
      final bySerial = a.record.serial.compareTo(b.record.serial);
      return bySerial != 0
          ? bySerial
          : a.record.createdAt.compareTo(b.record.createdAt);
    });
  final vip = inOrder.where((e) => e.vip).toList();
  final others = inOrder.where((e) => !e.vip).toList();

  final doc = pw.Document(title: 'Visitors Book');

  void addTablePage(
    String title,
    List<ExportEntry> rows,
    List<double> rowHeights,
  ) {
    doc.addPage(
      pw.Page(
        pageFormat: page,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: _titleHeight, child: _sectionTitle(title)),
            _table(page, rows, rowHeights, layout.rowHeight),
            pw.Spacer(),
            _pageFooter(context),
          ],
        ),
      ),
    );
  }

  for (final entry in vip) {
    addTablePage('VIP VISITOR', [
      entry,
    ], [
      _rowHeightFor(entry, page, layout.vipRowHeight, layout.available),
    ]);
  }
  final heights = [
    for (final entry in others)
      _rowHeightFor(entry, page, layout.rowHeight, layout.available),
  ];
  for (final onPage in paginate(heights, layout.available)) {
    addTablePage(
      'VISITORS',
      [for (final i in onPage) others[i]],
      [for (final i in onPage) heights[i]],
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

pw.Widget _pageFooter(pw.Context context) => pw.Container(
  height: _footerHeight,
  alignment: pw.Alignment.bottomRight,
  child: pw.Text(
    'Page ${context.pageNumber} of ${context.pagesCount}',
    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
  ),
);

pw.Widget _table(
  PdfPageFormat page,
  List<ExportEntry> rows,
  List<double> rowHeights,
  double ordinaryRowHeight,
) {
  final widths = [for (final c in _columns) page.availableWidth * c.share];
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.6),
    columnWidths: {
      for (var i = 0; i < widths.length; i++) i: pw.FixedColumnWidth(widths[i]),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          for (var i = 0; i < _columns.length; i++)
            pw.Container(
              width: widths[i],
              height: _headerHeight,
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.all(_cellPadding),
              child: pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                child: pw.Text(
                  _columns[i].title,
                  style: pw.TextStyle(
                    fontSize: 8,
                    letterSpacing: 1,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
      for (var r = 0; r < rows.length; r++)
        pw.TableRow(
          children: [
            for (var i = 0; i < _columns.length; i++)
              pw.Container(
                width: widths[i],
                height: rowHeights[r],
                alignment: pw.Alignment.centerLeft,
                padding: const pw.EdgeInsets.all(_cellPadding),
                child: _columns[i].field == 'date'
                    ? _dateCell(
                        rows[r],
                        widths[i] - 2 * _cellPadding,
                        rowHeights[r] - 2 * _cellPadding,
                        ordinaryRowHeight,
                      )
                    : _inkCell(
                        _columns[i].field,
                        rows[r].images[_columns[i].field],
                        widths[i] - 2 * _cellPadding,
                        rowHeights[r] - 2 * _cellPadding,
                        ordinaryRowHeight,
                      ),
              ),
          ],
        ),
    ],
  );
}

/// The ink of a field, as large as its cell allows but no larger than suits
/// the field. A field nobody wrote in stays empty.
pw.Widget _inkCell(
  String field,
  Uint8List? png,
  double width,
  double height,
  double ordinaryRowHeight,
) {
  final ink = png == null ? null : trimToInk(png);
  if (ink == null) return pw.SizedBox();

  final limit = switch (field) {
    'name' || 'place' || 'appointment' || 'date' =>
      ordinaryRowHeight * _lineHeightShare / ink.height,
    'comment' => _commentMaxEnlargement * width / ink.sourceWidth,
    _ => double.infinity,
  };
  final scale = min(min(width / ink.width, height / ink.height), limit);
  final printed = ink.fitted(ink.width * scale * _printDpi / _inch);

  return pw.SizedBox(
    width: ink.width * scale,
    height: ink.height * scale,
    child: pw.Image(
      pw.RawImage(
        bytes: printed.rgba,
        width: printed.width,
        height: printed.height,
      ),
      fit: pw.BoxFit.fill,
    ),
  );
}

/// The date is printed as text, with when the entry was written beneath it.
/// Records made before the picker existed may only have a handwritten date, so
/// fall back to that image.
pw.Widget _dateCell(
  ExportEntry entry,
  double width,
  double height,
  double ordinaryRowHeight,
) {
  final text = entry.record.ocr['date'];
  return pw.Column(
    mainAxisAlignment: pw.MainAxisAlignment.center,
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      if (text != null && text.isNotEmpty)
        pw.Text(text, style: const pw.TextStyle(fontSize: 9))
      else
        _inkCell(
          'date',
          entry.images['date'],
          width,
          height * 0.6,
          ordinaryRowHeight,
        ),
      pw.SizedBox(height: 3),
      pw.Text(
        _stamp(entry.record.createdAt),
        style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700),
      ),
    ],
  );
}

/// Handwriting cropped to its ink.
class InkImage {
  const InkImage(this.rgba, this.width, this.height, this.sourceWidth);
  final Uint8List rgba;
  final int width;
  final int height;

  /// Width of the whole pad the ink was cropped from.
  final int sourceWidth;

  /// This image scaled down to [targetWidth] pixels, or as it is if it is not
  /// wider than that.
  InkImage fitted(double targetWidth) {
    final target = targetWidth.ceil();
    if (target >= width) return this;
    final resized = img.copyResize(
      img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgba.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      ),
      width: target,
      interpolation: img.Interpolation.average,
    );
    return InkImage(
      resized.getBytes(order: img.ChannelOrder.rgba),
      resized.width,
      resized.height,
      sourceWidth,
    );
  }
}

/// Crop a field's PNG to the ink on it. Null when there is no ink, or the
/// image cannot be read.
InkImage? trimToInk(Uint8List png) {
  final decoded = img.decodePng(png);
  if (decoded == null) return null;
  final image = decoded.convert(format: img.Format.uint8, numChannels: 4);
  final pixels = image.getBytes(order: img.ChannelOrder.rgba);
  final w = image.width;
  final h = image.height;

  var left = w, right = -1, top = h, bottom = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      if (pixels[i + 3] > 0 &&
          pixels[i] < _inkThreshold &&
          pixels[i + 1] < _inkThreshold &&
          pixels[i + 2] < _inkThreshold) {
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
  }
  if (right < 0) return null;

  left = max(0, left - _inkMargin);
  top = max(0, top - _inkMargin);
  right = min(w - 1, right + _inkMargin);
  bottom = min(h - 1, bottom + _inkMargin);
  final cropWidth = right - left + 1;
  final cropHeight = bottom - top + 1;

  final rgba = Uint8List(cropWidth * cropHeight * 4);
  for (var y = 0; y < cropHeight; y++) {
    final from = ((top + y) * w + left) * 4;
    rgba.setRange(y * cropWidth * 4, (y + 1) * cropWidth * 4, pixels, from);
  }
  return InkImage(rgba, cropWidth, cropHeight, w);
}

String _stamp(DateTime t) {
  final local = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
