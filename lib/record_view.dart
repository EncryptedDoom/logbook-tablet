/// One record in full: the handwriting as it was written, with what the
/// recogniser made of the searchable fields underneath.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'database.dart';
import 'record.dart';
import 'theme.dart';

/// Same ratios as the entry form, so a field is the size it was written at.
const _ratios = <String, double>{
  'name': 3.8,
  'place': 3.8,
  'comment': 4.6,
  'appointment': 10.5,
  'signature': 2.6,
};

class RecordView extends StatefulWidget {
  const RecordView({super.key, required this.db, required this.record});

  final LogbookDatabase db;
  final LogRecord record;

  @override
  State<RecordView> createState() => _RecordViewState();
}

class _RecordViewState extends State<RecordView> {
  Map<String, Uint8List?> _images = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final images = await widget.db.imagesFor(widget.record.rawId);
    if (!mounted) return;
    setState(() {
      _images = images;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    return Scaffold(
      appBar: AppBar(title: const Text('Entry')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Recorded ${record.createdAt.toLocal()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _pickedDate()),
                    const SizedBox(width: 16),
                    Expanded(child: _field('name')),
                    const SizedBox(width: 16),
                    Expanded(child: _field('place')),
                  ],
                ),
                const SizedBox(height: 16),
                _field('comment'),
                const SizedBox(height: 16),
                _field('appointment'),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: 0.4,
                    child: _field('signature'),
                  ),
                ),
              ],
            ),
    );
  }

  /// The date was picked rather than written, so there is no handwriting to
  /// show - just the value.
  Widget _pickedDate() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('DATE', style: labelStyle(context)),
        const SizedBox(height: 4),
        Container(
          height: 56,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.paper,
            border: Border.all(color: AppColors.ink.withValues(alpha: 0.15)),
            borderRadius: BorderRadius.circular(AppRadii.pad),
          ),
          child: Text(
            widget.record.ocr['date'] ?? '-',
            style: const TextStyle(fontSize: 18, color: AppColors.ink),
          ),
        ),
      ],
    );
  }

  Widget _field(String name) {
    final png = _images[name];
    final read = widget.record.ocr[name];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name.toUpperCase(), style: labelStyle(context)),
        const SizedBox(height: 4),
        AspectRatio(
          aspectRatio: _ratios[name]!,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.paper,
              border: Border.all(color: AppColors.ink.withValues(alpha: 0.15)),
              borderRadius: BorderRadius.circular(AppRadii.pad),
            ),
            child: png == null
                ? const Center(child: Text('-'))
                : ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.pad),
                    child: Image.memory(png, fit: BoxFit.contain),
                  ),
          ),
        ),
        if (read != null && read.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              read,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.gold),
            ),
          ),
      ],
    );
  }
}
