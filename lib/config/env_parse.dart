/// Minimal `KEY=value` parser for `.env` files (pure Dart, no Flutter).
///
/// Shared by the app (which reads the bundled asset as a string) and
/// `tool/` scripts (which read the file via `dart:io` under plain
/// `dart run`, where Flutter asset APIs don't exist).
Map<String, String> parseEnv(String content) {
  final out = <String, String>{};
  for (final rawLine in content.split('\n')) {
    var line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('export ')) line = line.substring(7).trim();
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    var value = line.substring(eq + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    out[line.substring(0, eq).trim()] = value;
  }
  return out;
}
