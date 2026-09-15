import 'dart:async';

import 'package:flutter/material.dart';

/// Small progress dialog shown while verifying/decrypting after a scan.
Future<T> showDecryptingDialog<T>(BuildContext context, Future<T> work,
    {String label = 'Decrypting…'}) async {
  unawaited(showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Text(label),
        ],
      ),
    ),
  ));
  try {
    return await work;
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}
