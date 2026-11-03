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

import 'theme.dart';

class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.aspectRatio = 3.8,
  });

  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  /// Matches the handwriting pads beside it, so Date/Name/Place share one
  /// row height.
  final double aspectRatio;

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
            Text('DATE', style: labelStyle(context)),
            IconButton(
              onPressed: () => onChanged(DateTime.now()),
              tooltip: 'Today',
              icon: const Icon(Icons.today_outlined, size: 20),
              iconSize: 20,
              color: AppColors.textMuted,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ],
        ),
        AspectRatio(
          aspectRatio: aspectRatio,
          child: Material(
            color: AppColors.paper,
            borderRadius: BorderRadius.circular(AppRadii.pad),
            child: InkWell(
              onTap: () => _pick(context),
              borderRadius: BorderRadius.circular(AppRadii.pad),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AppColors.ink.withValues(alpha: 0.15),
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.pad),
                ),
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 20, color: AppColors.ink),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      format(value),
                      style: const TextStyle(
                        fontSize: 18,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
