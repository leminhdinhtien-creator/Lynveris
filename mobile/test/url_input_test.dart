import 'package:flutter_test/flutter_test.dart';
import 'package:lynveris/url_input.dart';

void main() {
  test('extracts locally and preserves encoding and URL punctuation', () {
    final urls = extractUrls(
      'Xem https://example.com/a_(b)?x=%252f và https://bücher.de.',
    );
    expect(urls, ['https://example.com/a_(b)?x=%252f', 'https://bücher.de.']);
  });
  test('does not silently rewrite terminal punctuation in an entered URL', () {
    const original = 'https://example.org/path)?token=abc!';
    expect(extractUrls(original), [original]);
  });
  test('deduplicates and rejects message without links', () {
    expect(extractUrls('chào cả nhà'), isEmpty);
    expect(extractUrls('https://example.com https://example.com').length, 1);
  });
  test('keeps userinfo for API host analysis', () {
    expect(
      extractUrls('https://google.com@evil.example/login').single,
      'https://google.com@evil.example/login',
    );
  });
}
