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
      late String html;

      setUpAll(() {
        source = File('${root.path}/$relativePath').readAsStringSync();
        final htmlPath = relativePath.startsWith('docs/')
            ? 'docs/index.html'
            : 'landing/index.html';
        html = File('${root.path}/$htmlPath').readAsStringSync();
      });

      test('release notes have no landing DOM insertion path', () {
        expect(source, isNot(contains('simpleMarkdown')));
        expect(source, isNot(contains('escapeHtml')));
        expect(source, isNot(contains('innerHTML')));
        expect(source, isNot(contains('changelog')));
        expect(html, isNot(contains('data-role="changelog-body"')));
        expect(html, isNot(contains('class="changelog"')));
      });

      test('published metadata leaves canonical Android and iOS links unchanged', () {
        expect(source, contains("asset.name === 'Tabby.apk'"));
        expect(source, contains("asset.name === 'Tabby.ipa'"));
        expect(source, isNot(contains('localStorage')));
        expect(source, isNot(contains("setAttribute('href'")));
        expect(source, isNot(contains("setAttribute('download'")));
        expect(html, contains('href="https://github.com/Zalweb/Tabby/releases/latest/download/Tabby.apk"'));
        expect(html, contains('href="https://github.com/Zalweb/Tabby/releases/latest/download/Tabby.ipa"'));
        expect(html, contains('download="Tabby.apk"'));
      });
    });
  }
}
