import 'package:flutter/material.dart';

/// Styled text widget — wraps a single label with optional primary/secondary
/// sizing. Replaces the old bilingual widget; now just renders one string.
class BilingualText extends StatelessWidget {
  const BilingualText(
    this.text, {
    super.key,
    this.primaryStyle,
    this.secondaryStyle,
    this.textAlign,
    this.maxLines,
  });

  final String text;
  final TextStyle? primaryStyle;
  final TextStyle? secondaryStyle;
  final TextAlign? textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: primaryStyle ?? Theme.of(context).textTheme.titleMedium,
    );
  }
}
