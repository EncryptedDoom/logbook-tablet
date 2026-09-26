/// The book itself: search, recent entries, and the form to add one.
library;

import 'package:flutter/material.dart';

import 'database.dart';
import 'date_field.dart';
import 'handwriting_pad.dart';
import 'record.dart';
import 'recogniser.dart';
import 'record_view.dart';
import 'search.dart' as search;

class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key, required this.db, required this.recogniser});

  final LogbookDatabase db;
  final Recogniser recogniser;

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  /// One pad per field. Ratios chosen so a field looks the same here as it
  /// does when the record is read back.
  static const _fields = <String, double>{
    'name': 3.8,
    'place': 3.8,
    'comment': 4.6,
    'appointment': 10.5,
    'signature': 2.6,
  };

  final _controllers = {
    for (final field in _fields.keys) field: HandwritingPadController(),
  };
  final _searchControllers = {
    for (final field in search.searchFields) field: TextEditingController(),
  };

  DateTime _date = DateTime.now();

  List<LogRecord> _all = [];
  List<LogRecord> _shown = [];
  bool _saving = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final c in _searchControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final records = await widget.db.listRecords();
    if (!mounted) return;
    setState(() {
      _all = records;
      _applySearch();
    });
  }

  Map<String, String> get _criteria => {
        for (final field in search.searchFields)
          field: _searchControllers[field]!.text,
      };

  bool get _searching =>
      _criteria.values.any((term) => term.trim().isNotEmpty);

  void _applySearch() {
    final criteria = _criteria;
    final active = Map.fromEntries(
      criteria.entries.where((e) => e.value.trim().isNotEmpty),
    );
    if (active.isEmpty) {
      _shown = _all;
      return;
    }

    final hits = _all.where((record) {
      return active.entries.every((entry) {
        final value = record.ocr[entry.key];
        return search.exactFields.contains(entry.key)
            ? search.dateMatches(entry.value, value)
            : search.fieldMatches(entry.value, value);
      });
    }).toList();

    hits.sort((a, b) => search
        .matchScore(active, {
          for (final f in search.searchFields) '${f}_ocr': b.ocr[f],
        })
        .compareTo(search.matchScore(active, {
          for (final f in search.searchFields) '${f}_ocr': a.ocr[f],
        })));
    _shown = hits;
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _status = 'Saving...';
    });

    try {
      // capture every pad first, so recognition runs on what was written
      final written = <String, Handwriting>{};
      for (final entry in _controllers.entries) {
        written[entry.key] = await entry.value.read();
      }

      if (written.values.every((w) => w.isEmpty)) {
        setState(() {
          _saving = false;
          _status = 'Nothing written yet.';
        });
        return;
      }

      // name and place are recognised; the date is picked, so it is already
      // exact and needs no recognition at all
      final ocr = <String, String?>{'date': DateField.format(_date)};
      for (final field in ocrFields.where((f) => f != 'date')) {
        ocr[field] = await widget.recogniser.read(written[field]!.strokes);
      }

      final record = LogRecord(
        id: LogRecord.newId(),
        rawId: '',
        createdAt: DateTime.now(),
        images: {
          for (final entry in written.entries) entry.key: entry.value.png,
        },
        ocr: ocr,
      );
      await widget.db.insert(
        LogRecord(
          id: record.id,
          rawId: record.id,
          createdAt: record.createdAt,
          images: record.images,
          ocr: record.ocr,
        ),
      );

      for (final c in _controllers.values) {
        c.clear();
      }
      _date = DateTime.now();
      await _load();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _status = 'Entry recorded.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _status = 'Could not save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visitors Book'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${_shown.length} ${_shown.length == 1 ? "entry" : "entries"} '
                '${_searching ? "found" : "recorded"}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _searchBar(),
          const SizedBox(height: 24),
          _recentEntries(),
          const SizedBox(height: 24),
          _form(),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final field in search.searchFields) ...[
              Expanded(
                child: TextField(
                  controller: _searchControllers[field],
                  decoration: InputDecoration(
                    labelText: field[0].toUpperCase() + field.substring(1),
                    hintText: field == 'date' ? 'e.g. 14/09/2026' : null,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(_applySearch),
                ),
              ),
              const SizedBox(width: 12),
            ],
            SizedBox(
              height: 56,
              child: OutlinedButton(
                onPressed: _searching
                    ? () {
                        for (final c in _searchControllers.values) {
                          c.clear();
                        }
                        setState(_applySearch);
                      }
                    : null,
                child: const Text('Clear'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentEntries() {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _searching ? 'SEARCH RESULTS' : 'RECENT ENTRIES',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          if (_shown.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                _searching ? 'No matching records.' : 'No records yet.',
              ),
            )
          else
            ...(_searching ? _shown : _shown.take(5)).map(
              (record) => ListTile(
                title: Text(record.ocr['name']?.isNotEmpty == true
                    ? record.ocr['name']!
                    : '(name not read)'),
                subtitle: Text([
                  record.ocr['place'] ?? '',
                  record.ocr['date'] ?? '',
                ].where((s) => s.isNotEmpty).join('  ·  ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        RecordView(db: widget.db, record: record),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _form() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final field in ['name', 'place']) ...[
                  Expanded(
                    child: HandwritingPad(
                      label: field,
                      controller: _controllers[field]!,
                      aspectRatio: _fields[field]!,
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: DateField(
                    value: _date,
                    onChanged: (d) => setState(() => _date = d),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            HandwritingPad(
              label: 'comment',
              controller: _controllers['comment']!,
              aspectRatio: _fields['comment']!,
            ),
            const SizedBox(height: 16),
            HandwritingPad(
              label: 'appointment',
              controller: _controllers['appointment']!,
              aspectRatio: _fields['appointment']!,
            ),
            const SizedBox(height: 16),
            // signature sits small and to the right, as on paper
            Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.4,
                child: HandwritingPad(
                  label: 'signature',
                  controller: _controllers['signature']!,
                  aspectRatio: _fields['signature']!,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(_status,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(width: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(200, 56),
                  ),
                  onPressed: _saving ? null : _submit,
                  child: const Text('RECORD ENTRY'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
