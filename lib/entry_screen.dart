/// The book itself: search, recent entries, and the form to add one.
library;

import 'package:flutter/material.dart';

import 'database.dart';
import 'date_field.dart';
import 'export_screen.dart';
import 'handwriting_pad.dart';
import 'record.dart';
import 'recogniser.dart';
import 'record_view.dart';
import 'search.dart' as search;
import 'theme.dart';

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
  // the single box in the AppBar's search panel, and which fields it targets
  final _queryController = TextEditingController();
  final Set<String> _searchTargets = {};

  DateTime _date = DateTime.now();

  List<LogRecord> _all = [];
  List<LogRecord> _shown = [];
  bool _saving = false;
  String _status = '';

  bool _searchExpanded = false;
  bool _recentExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
    // the Record Entry button's enabled state follows whatever is on the pads
    for (final c in _controllers.values) {
      c.addListener(_onInkChanged);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.removeListener(_onInkChanged);
      c.dispose();
    }
    for (final c in _searchControllers.values) {
      c.dispose();
    }
    _queryController.dispose();
    super.dispose();
  }

  void _onInkChanged() => setState(() {});

  /// Same rule _submit uses to refuse an empty entry, so the button's
  /// enabled state never promises something _submit would then reject.
  bool get _hasAnyInk => _controllers.values.any((c) => !c.isEmpty);

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

  /// Each field the user filled in must match (AND) - this is what powered
  /// the original three-box search and is unchanged.
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

  /// The new single-box panel: one query against whichever fields are
  /// chip-selected, matching if ANY of them hits - not the AND that filling
  /// in all three boxes used to mean. Falls back to _applySearch's AND when
  /// only one field is targeted, since OR and AND of one term are the same.
  void _applyQueryAcrossFields(String text, Set<String> fields) {
    final targets = fields.isEmpty ? search.searchFields.toSet() : fields;
    final query = text.trim();
    if (query.isEmpty || targets.length <= 1) {
      for (final field in search.searchFields) {
        _searchControllers[field]!.text = targets.contains(field) ? text : '';
      }
      _applySearch();
      return;
    }

    final hits = _all.where((record) {
      return targets.any((field) {
        final value = record.ocr[field];
        return search.exactFields.contains(field)
            ? search.dateMatches(query, value)
            : search.fieldMatches(query, value);
      });
    }).toList();

    hits.sort((a, b) => search
        .matchScore({for (final f in targets) f: query},
            {for (final f in targets) '${f}_ocr': b.ocr[f]})
        .compareTo(search.matchScore({for (final f in targets) f: query},
            {for (final f in targets) '${f}_ocr': a.ocr[f]})));

    // keep the per-field boxes in sync so Clear and _searching still work
    for (final field in search.searchFields) {
      _searchControllers[field]!.text = targets.contains(field) ? text : '';
    }
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
      appBar: _buildAppBar(context),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_searchExpanded) ...[
                _searchPanel(),
                const SizedBox(height: AppSpacing.sm),
              ],
              _recentEntriesStrip(),
              const SizedBox(height: AppSpacing.sm),
              Expanded(child: _form()),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      titleSpacing: AppSpacing.sm,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/images/crest.png', height: 32),
          const SizedBox(width: AppSpacing.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '7th Battalion Visitors Book',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '${_shown.length} ${_shown.length == 1 ? "entry" : "entries"} '
                '${_searching ? "found" : "recorded"}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: _searchExpanded ? 'Close search' : 'Search',
          icon: Icon(_searchExpanded ? Icons.close : Icons.search),
          onPressed: () => setState(() => _searchExpanded = !_searchExpanded),
        ),
        IconButton(
          tooltip: 'Export',
          icon: const Icon(Icons.picture_as_pdf_outlined),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ExportScreen(db: widget.db)),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }

  /// The query box's text, against whichever fields are chip-selected (any
  /// of the three, if none are picked).
  void _applyQuery(String text) {
    setState(() => _applyQueryAcrossFields(text, _searchTargets));
  }

  /// A search icon in the AppBar expands into this: one field plus filter
  /// chips for which of name/date/place it searches.
  Widget _searchPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              controller: _queryController,
              decoration: const InputDecoration(
                hintText: 'Search entries',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _applyQuery,
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                for (final field in search.searchFields)
                  FilterChip(
                    label: Text(field[0].toUpperCase() + field.substring(1)),
                    selected: _searchTargets.contains(field),
                    onSelected: (_) {
                      setState(() {
                        _searchTargets.contains(field)
                            ? _searchTargets.remove(field)
                            : _searchTargets.add(field);
                      });
                      _applyQuery(_queryController.text);
                    },
                  ),
                if (_searching)
                  ActionChip(
                    label: const Text('Clear'),
                    avatar: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _queryController.clear();
                      for (final c in _searchControllers.values) {
                        c.clear();
                      }
                      setState(_applySearch);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Collapsed by default: a one-line preview of the latest entry and a
  /// count. Tapping expands it into the familiar list.
  Widget _recentEntriesStrip() {
    final shown = _searching ? _shown : _shown.take(5).toList();
    final latest = _shown.isNotEmpty ? _shown.first : null;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadii.card),
            onTap: () => setState(() => _recentExpanded = !_recentExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Text(
                    _searching ? 'SEARCH RESULTS' : 'RECENT ENTRIES',
                    style: labelStyle(context),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  if (!_recentExpanded)
                    Expanded(
                      child: Text(
                        latest == null
                            ? (_searching
                                ? 'Nothing matches that search.'
                                : 'The book is empty - the first entry '
                                    'starts it.')
                            : '${latest.ocr['name']?.isNotEmpty == true ? latest.ocr['name'] : "(name not read)"}'
                                '  ·  ${latest.ocr['place'] ?? ''}'
                                '  ·  ${latest.ocr['date'] ?? ''}',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  else
                    const Spacer(),
                  Text(
                    '${_shown.length}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.gold),
                  ),
                  Icon(
                    _recentExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_recentExpanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: shown.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.sm,
                        0,
                        AppSpacing.sm,
                        AppSpacing.sm,
                      ),
                      child: Text(
                        _searching
                            ? 'Nothing matches that search.'
                            : 'The book is empty - the first entry starts it.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: shown
                          .map(
                            (record) => ListTile(
                              title: Text(
                                record.ocr['name']?.isNotEmpty == true
                                    ? record.ocr['name']!
                                    : '(name not read)',
                              ),
                              subtitle: Text([
                                record.ocr['date'] ?? '',
                                record.ocr['place'] ?? '',
                              ].where((s) => s.isNotEmpty).join('  ·  ')),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => RecordView(
                                    db: widget.db,
                                    record: record,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _form() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Row 1: Date, Name, Place - same height, labels on one baseline
            Expanded(
              flex: 3,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DateField(
                      value: _date,
                      onChanged: (d) => setState(() => _date = d),
                      aspectRatio: _fields['name']!,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  for (final field in ['name', 'place']) ...[
                    Expanded(
                      child: HandwritingPad(
                        label: field,
                        controller: _controllers[field]!,
                        aspectRatio: _fields[field]!,
                      ),
                    ),
                    if (field != 'place') const SizedBox(width: AppSpacing.sm),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            // Row 2: Comment - the tallest pad
            Expanded(
              flex: 5,
              child: HandwritingPad(
                label: 'comment',
                controller: _controllers['comment']!,
                aspectRatio: _fields['comment']!,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            // Row 3: Appointment, Signature, Record Entry
            Expanded(
              flex: 3,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: HandwritingPad(
                      label: 'appointment',
                      controller: _controllers['appointment']!,
                      aspectRatio: _fields['appointment']!,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: HandwritingPad(
                      label: 'signature',
                      controller: _controllers['signature']!,
                      aspectRatio: _fields['signature']!,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_status.isNotEmpty)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: Text(
                              _status,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                          ),
                          onPressed: (_saving || !_hasAnyInk) ? null : _submit,
                          child: const Text('RECORD ENTRY'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
