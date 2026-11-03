/// The date is picked, not written.
///
/// It was the one field where handwriting cost something and bought nothing.
/// Measured on this tablet, recognition read 6 of 10 dates exactly and only
/// 7 of 10 were findable by search - "2026" came back as "2028" twice, and a
/// digit was dropped once. A wrong digit in a date is a wrong date, not a
/// mangled one, so search treats dates exactly and those records were simply
/// lost. Picking removes the problem: names and places stay handwritten.
library;

import 'package:flutter/material.dart';

import 'box_style.dart';

class DateField extends StatelessWidget {
  const DateField({super.key, required this.value, required this.onChanged});

  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  /// Same shape the search layer canonicalises to.
  static String format(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value,
      // a visitors book records visits, so the useful range is around today
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('DATE', style: Theme.of(context).textTheme.labelMedium),
            TextButton(
              onPressed: () => onChanged(DateTime.now()),
              style: TextButton.styleFrom(
                minimumSize: const Size(64, 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Today'),
            ),
          ],
        ),
        OutlinedButton.icon(
          onPressed: () => _pick(context),
          icon: const Icon(Icons.calendar_today),
          label: Text(format(value), style: const TextStyle(fontSize: 18)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            alignment: Alignment.centerLeft,
            backgroundColor: boxFill,
            foregroundColor: boxInk,
            iconColor: boxInk,
            side: const BorderSide(color: boxEdge),
            shape: const RoundedRectangleBorder(borderRadius: boxRadius),
          ),
        ),
      ],
    );
  }
}
