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

      test('published assets still update the Android and iOS download links', () {
        expect(source, contains("document.querySelectorAll('[data-role=\"apk-download-btn\"]')"));
        expect(source, contains("document.querySelectorAll('[data-role=\"ipa-download-btn\"]')"));
        expect(source, contains("button.setAttribute('href', apkUrl)"));
        expect(source, contains("button.setAttribute('href', ipaUrl)"));
        expect(source, contains("button.setAttribute('download', apkFilenameText)"));
        expect(source, contains('releases/latest/download/Tabby.apk'));
        expect(source, contains('releases/latest/download/Tabby.ipa'));
      });
    });
  }
}
