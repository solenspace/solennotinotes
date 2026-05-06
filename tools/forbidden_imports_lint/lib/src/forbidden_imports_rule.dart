import 'dart:io';

import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

class ForbiddenImportsRule extends DartLintRule {
  const ForbiddenImportsRule() : super(code: _code);

  static const _patternsRelativePath = 'scripts/.forbidden-imports.txt';
  static const _allowlistRelativePath = 'scripts/.offline-allowlist';

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
    final patternsFile = _findFileUp(resolver.path, _patternsRelativePath);
    if (patternsFile == null) return;
    final patterns = _loadPatternsFromFile(patternsFile);
    if (patterns.isEmpty) return;

    final repoRoot = patternsFile.parent.parent.path;
    final relativePath = _toRepoRelative(resolver.path, repoRoot);

    // Spec 15 — per-path carve-outs. When the analyzed file is on the
    // offline-allowlist, the rule short-circuits. The shell-level
    // scripts/check-offline.sh honors the same file via grep --exclude.
    final allowlist = _loadAllowlist(repoRoot);
    if (relativePath != null && allowlist.contains(relativePath)) return;

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

  static final Map<String, List<String>> _patternsCache = <String, List<String>>{};
  static final Map<String, Set<String>> _allowlistCache = <String, Set<String>>{};

  static List<String> _loadPatternsFromFile(File file) {
    return _patternsCache.putIfAbsent(file.path, () {
      return file
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList(growable: false);
    });
  }

  static Set<String> _loadAllowlist(String repoRoot) {
    return _allowlistCache.putIfAbsent(repoRoot, () {
      final file = File('$repoRoot/$_allowlistRelativePath');
      if (!file.existsSync()) return const <String>{};
      return file
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toSet();
    });
  }

  static File? _findFileUp(String startFilePath, String relativePath) {
    Directory dir = File(startFilePath).parent;
    while (true) {
      final candidate = File('${dir.path}/$relativePath');
      if (candidate.existsSync()) return candidate;
      final parent = dir.parent;
      if (parent.path == dir.path) return null;
      dir = parent;
    }
  }

  static String? _toRepoRelative(String absolutePath, String repoRoot) {
    final root = repoRoot.endsWith('/') ? repoRoot : '$repoRoot/';
    if (!absolutePath.startsWith(root)) return null;
    return absolutePath.substring(root.length);
  }
}
