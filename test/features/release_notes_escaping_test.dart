import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Directory _projectRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync() &&
      dir.path != dir.parent.path) {
    dir = dir.parent;
  }
  return dir;
}

void main() {
  final root = _projectRoot();

  for (final relativePath in ['docs/app.js', 'landing/app.js']) {
    group(relativePath, () {
      late String source;

      setUpAll(() {
        source = File('${root.path}/$relativePath').readAsStringSync();
      });

      test('release notes are escaped before markdown markup is added', () {
        final start = source.indexOf('function simpleMarkdown(');
        expect(start, greaterThan(-1), reason: 'simpleMarkdown missing');

        final body = source.substring(start);

        expect(body, contains('return escapeHtml(text)'));
        expect(source, contains('function escapeHtml('));
        expect(source, contains(".replace(/</g, '&lt;')"));
        expect(source, contains(".replace(/>/g, '&gt;')"));
      });
    });
  }
}
