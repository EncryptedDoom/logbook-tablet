/// One look for every box in the app: writing pads, the date, the record
/// view, and the text fields. Off-white with rounded corners, dark ink.
///
/// Text fields carry their label above the box, as the writing pads do, not
/// inside its border: a floating label would sit half on the dark page and
/// half on the off-white fill, and be unreadable in one or the other.
library;

import 'package:flutter/material.dart';

/// Off-white, a touch warm so it sits with the brass accents.
const boxFill = Color(0xFFF8F6F0);

/// Text and icons inside a box.
const boxInk = Color(0xFF1D1B20);

/// Placeholder text and other quiet text inside a box.
const boxHint = Color(0xFF77726A);

const boxEdge = Color(0xFFC9C3B8);
const boxRadius = BorderRadius.all(Radius.circular(12));

/// Fill, corners and edge for a box that is not a text field.
const boxDecoration = BoxDecoration(
  color: boxFill,
  borderRadius: boxRadius,
  border: Border.fromBorderSide(BorderSide(color: boxEdge)),
);

/// Text typed into a box.
const boxText = TextStyle(color: boxInk, fontSize: 16);

/// The decoration for a text field or dropdown.
InputDecoration boxInput(BuildContext context, {String? hint, String? suffix}) {
  OutlineInputBorder edge(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: boxRadius,
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    filled: true,
    fillColor: boxFill,
    hintText: hint,
    hintStyle: const TextStyle(color: boxHint),
    suffixText: suffix,
    suffixStyle: const TextStyle(color: boxHint),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: edge(boxEdge),
    enabledBorder: edge(boxEdge),
    disabledBorder: edge(boxEdge.withValues(alpha: 0.5)),
    focusedBorder: edge(Theme.of(context).colorScheme.primary, 2),
  );
}

/// A small caps label above a box, matching the writing pads' labels.
class BoxLabel extends StatelessWidget {
  const BoxLabel(this.text, {super.key, required this.child});

  final String text;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
