import 'dart:io';

import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

class ForbiddenImportsRule extends DartLintRule {
  const ForbiddenImportsRule() : super(code: _code);

  static const _patternsRelativePath = 'scripts/.forbidden-imports.txt';

  static const _code = LintCode(
    name: 'forbidden_import',
    problemMessage: 'Forbidden import: violates the offline invariant (architecture.md #1).',
    correctionMessage:
        'Remove the import or add the file path to scripts/.offline-allowlist with the authorizing spec number.',
    errorSeverity: ErrorSeverity.ERROR,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    final patterns = _loadPatterns(resolver.path);
    if (patterns.isEmpty) return;

    context.registry.addImportDirective((node) {
      final uri = node.uri.stringValue;
      if (uri == null) return;
      for (final pattern in patterns) {
        if (uri.startsWith(pattern) || uri == pattern) {
          reporter.atNode(node, _code);
          return;
        }
      }
    });
  }

  static final Map<String, List<String>> _cache = <String, List<String>>{};

  static List<String> _loadPatterns(String analyzedFilePath) {
    final patternsFile = _findPatternsFile(analyzedFilePath);
    if (patternsFile == null) return const [];
    return _cache.putIfAbsent(patternsFile.path, () {
      return patternsFile
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList(growable: false);
    });
  }

  static File? _findPatternsFile(String startFilePath) {
    Directory dir = File(startFilePath).parent;
    while (true) {
      final candidate = File('${dir.path}/$_patternsRelativePath');
      if (candidate.existsSync()) return candidate;
      final parent = dir.parent;
      if (parent.path == dir.path) return null;
      dir = parent;
    }
  }
}
