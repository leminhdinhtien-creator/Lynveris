/// Finds candidate spans locally; Uri parses candidates. Only the selected URL is sent.
List<String> extractUrls(String text) {
  final candidates = <String>{};
  for (final match in RegExp(
    r'https?://[^\s<>"“”]+',
    caseSensitive: false,
  ).allMatches(text)) {
    // Punctuation can be meaningful in a path/query. Keep the original span;
    // never silently turn a pasted URL into a different address.
    final value = match.group(0)!;
    final uri = Uri.tryParse(value);
    if (uri != null &&
        uri.hasAuthority &&
        uri.host.isNotEmpty &&
        ['https', 'http'].contains(uri.scheme.toLowerCase())) {
      candidates.add(value);
    }
  }
  return candidates.take(30).toList();
}
