/// Choose which records are VIP for this export, pick a page size, then print
/// the book or save it as a PDF on the tablet.
///
/// The VIP choice exists only on this screen and only for this export. It is
/// not part of the record, it is not stored, and it is not shown anywhere
/// else. Every visit to this screen starts with everyone as non-VIP.
///
/// Nothing here sends data off the tablet: printing goes to a printer the
/// tablet can reach, and saving writes a file to a folder the user picks.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'box_style.dart';
import 'database.dart';
import 'export_pdf.dart';
import 'record.dart';

/// Paper sizes offered, as width x height in points, portrait way up.
enum PaperSize {
  logbook(
    'Logbook (13.8 x 9.6 in)',
    9.6 * PdfPageFormat.inch,
    13.8 * PdfPageFormat.inch,
  ),
  a4('A4 (210 x 297 mm)', 210 * PdfPageFormat.mm, 297 * PdfPageFormat.mm),
  a3('A3 (297 x 420 mm)', 297 * PdfPageFormat.mm, 420 * PdfPageFormat.mm),
  letter(
    'Letter (8.5 x 11 in)',
    8.5 * PdfPageFormat.inch,
    11 * PdfPageFormat.inch,
  ),
  custom('Custom size', 0, 0);

  const PaperSize(this.label, this.shortSide, this.longSide);
  final String label;
  final double shortSide;
  final double longSide;
}

enum Unit {
  mm('mm', PdfPageFormat.mm),
  inch('in', PdfPageFormat.inch);

  const Unit(this.label, this.points);
  final String label;
  final double points;
}

/// Sanity limits for a custom page, in inches: smaller is unreadable, larger
/// is not a sheet of paper any printer takes.
const _minSideInches = 2.0;
const _maxSideInches = 48.0;

const _files = MethodChannel('logbook/files');

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key, required this.db});

  final LogbookDatabase db;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  List<LogRecord> _records = [];

  /// Record ids marked VIP for this export. In memory only.
  final Set<String> _vip = {};

  PaperSize _paper = PaperSize.logbook;
  bool _landscape = true;
  Unit _unit = Unit.mm;
  final _customWidth = TextEditingController();
  final _customHeight = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _customWidth.dispose();
    _customHeight.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final records = await widget.db.listRecords();
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  void _setVip(String id, bool vip) {
    setState(() => vip ? _vip.add(id) : _vip.remove(id));
  }

  /// The chosen page, or null with a reason when a custom size is not valid.
  (PdfPageFormat?, String?) get _page {
    double a, b;
    if (_paper == PaperSize.custom) {
      final w = double.tryParse(_customWidth.text.trim());
      final h = double.tryParse(_customHeight.text.trim());
      if (w == null || h == null) return (null, 'Enter a width and a height.');
      final min = _minSideInches * PdfPageFormat.inch / _unit.points;
      final max = _maxSideInches * PdfPageFormat.inch / _unit.points;
      String fmt(double v) => v.toStringAsFixed(_unit == Unit.mm ? 0 : 1);
      if (w < min || h < min || w > max || h > max) {
        return (
          null,
          'Each side must be between ${fmt(min)} and ${fmt(max)} ${_unit.label}.',
        );
      }
      a = w * _unit.points;
      b = h * _unit.points;
    } else {
      a = _paper.shortSide;
      b = _paper.longSide;
    }
    // landscape puts the longer side across, portrait puts it down
    final long = a > b ? a : b;
    final short = a > b ? b : a;
    return (
      _landscape ? pageFormat(long, short) : pageFormat(short, long),
      null,
    );
  }

  String _describe(PdfPageFormat f) {
    final u = _paper == PaperSize.custom ? _unit : _defaultUnit(_paper);
    String v(double pts) =>
        (pts / u.points).toStringAsFixed(u == Unit.mm ? 0 : 1);
    return '${v(f.width)} x ${v(f.height)} ${u.label}, '
        '${_landscape ? "landscape" : "portrait"}';
  }

  Unit _defaultUnit(PaperSize p) =>
      p == PaperSize.a4 || p == PaperSize.a3 ? Unit.mm : Unit.inch;

  /// Load every record's handwriting and lay out the document.
  Future<Uint8List?> _build(PdfPageFormat format) async {
    setState(() {
      _busy = true;
      _status = 'Preparing ${_records.length} records...';
    });
    try {
      final entries = <ExportEntry>[];
      for (final record in _records) {
        final images = await widget.db.imagesFor(record.rawId);
        entries.add(ExportEntry(record, images, vip: _vip.contains(record.id)));
      }
      return await buildLogbookPdf(entries, format: format);
    } catch (e) {
      if (mounted) setState(() => _status = 'Export failed: $e');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _fileName {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'visitors-book-${now.year}-${two(now.month)}-${two(now.day)}.pdf';
  }

  /// Save to a folder the user picks on the tablet, through Android's own
  /// "Save as" dialog.
  Future<void> _save() async {
    final format = _page.$1;
    if (format == null) return;
    final bytes = await _build(format);
    if (bytes == null) return;
    try {
      final saved = await _files.invokeMethod<String>('savePdf', {
        'bytes': bytes,
        'name': _fileName,
      });
      if (!mounted) return;
      setState(
        () => _status = saved == null ? 'Save cancelled.' : 'Saved $_fileName',
      );
    } on PlatformException catch (e) {
      if (mounted) setState(() => _status = 'Could not save: ${e.message}');
    }
  }

  /// To a printer, at the chosen page size.
  Future<void> _print() async {
    final format = _page.$1;
    if (format == null) return;
    final bytes = await _build(format);
    if (bytes == null) return;
    await Printing.layoutPdf(
      name: _fileName,
      format: format,
      onLayout: (_) async => bytes,
    );
    if (mounted) setState(() => _status = '');
  }

  @override
  Widget build(BuildContext context) {
    final (format, problem) = _page;
    final ready = !_busy && _records.isNotEmpty && format != null;
    final vipCount = _vip.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Export'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '$vipCount VIP  ·  ${_records.length - vipCount} non-VIP',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _pageSettings(format, problem),
                const Divider(height: 1),
                if (_records.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No records to export yet.'),
                  )
                else
                  for (final record in _records) ...[
                    _row(record),
                    const Divider(height: 1),
                  ],
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _busy ? 'Working...' : _status,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (_busy) ...[
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
              ],
              OutlinedButton.icon(
                onPressed: ready ? _print : null,
                icon: const Icon(Icons.print),
                label: const Text('PRINT'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(140, 56),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: ready ? _save : null,
                icon: const Icon(Icons.save_alt),
                label: const Text('SAVE AS PDF'),
                style: FilledButton.styleFrom(minimumSize: const Size(180, 56)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pageSettings(PdfPageFormat? format, String? problem) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PAGE', style: theme.textTheme.labelLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            // the boxes carry labels above them, so line up their bottoms
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              SizedBox(
                width: 260,
                child: BoxLabel(
                  'Paper size',
                  child: DropdownButtonFormField<PaperSize>(
                    initialValue: _paper,
                    decoration: boxInput(context),
                    style: boxText,
                    dropdownColor: boxFill,
                    iconEnabledColor: boxInk,
                    borderRadius: boxRadius,
                    items: [
                      for (final p in PaperSize.values)
                        DropdownMenuItem(value: p, child: Text(p.label)),
                    ],
                    onChanged: _busy
                        ? null
                        : (p) => setState(() => _paper = p ?? _paper),
                  ),
                ),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('Landscape'),
                    icon: Icon(Icons.crop_landscape),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('Portrait'),
                    icon: Icon(Icons.crop_portrait),
                  ),
                ],
                selected: {_landscape},
                onSelectionChanged: _busy
                    ? null
                    : (s) => setState(() => _landscape = s.first),
              ),
            ],
          ),
          if (_paper == PaperSize.custom) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                _dimension(_customWidth, 'Width'),
                _dimension(_customHeight, 'Height'),
                SegmentedButton<Unit>(
                  segments: [
                    for (final u in Unit.values)
                      ButtonSegment(value: u, label: Text(u.label)),
                  ],
                  selected: {_unit},
                  onSelectionChanged: _busy
                      ? null
                      : (s) => setState(() => _unit = s.first),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            problem ?? 'Page: ${_describe(format!)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: problem != null ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dimension(TextEditingController controller, String label) {
    return SizedBox(
      width: 140,
      child: BoxLabel(
        label,
        child: TextField(
          controller: controller,
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
          ],
          style: boxText,
          cursorColor: boxInk,
          decoration: boxInput(context, suffix: _unit.label),
          onChanged: (_) => setState(() {}),
        ),
      ),
    );
  }

  Widget _row(LogRecord record) {
    final name = record.ocr['name'];
    final details = [
      record.ocr['place'] ?? '',
      record.ocr['date'] ?? '',
    ].where((s) => s.isNotEmpty).join('  ·  ');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      title: Text(name != null && name.isNotEmpty ? name : '(name not read)'),
      subtitle: details.isEmpty ? null : Text(details),
      trailing: RadioGroup<bool>(
        groupValue: _vip.contains(record.id),
        onChanged: (value) {
          if (value != null && !_busy) _setVip(record.id, value);
        },
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Radio<bool>(value: true),
            Text('VIP'),
            SizedBox(width: 24),
            Radio<bool>(value: false),
            Text('Non-VIP'),
          ],
        ),
      ),
    );
  }
}
