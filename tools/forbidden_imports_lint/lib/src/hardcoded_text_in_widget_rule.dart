import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Fires on `Text('literal')` (or `Text("literal")`) instantiations outside
/// the localization scaffold. Spec 26 requires every user-visible widget
/// string to flow through `context.l10n.<key>` backed by `lib/l10n/en.arb`.
///
/// Exempt paths own non-chrome string usage:
///   - `lib/l10n/` — the localization extension itself
///   - `lib/generated/` — gen_l10n output
///   - `lib/models/` / `lib/services/` / `lib/repositories/` — no widget
///     chrome lives here; any `Text(...)` would be inside debug-only widget
///     scaffolding which is outside the spec's scope
///   - `lib/theme/` — token definitions may carry display glyphs
///   - `test/` — golden fixtures and rendering harnesses
///
/// The rule allows two narrow shapes of literal arg that are not chrome:
///   1. A single-character glyph (length 1, e.g. `'+'`, `'☼'`) — these are
///      icon-equivalent decorations, not English copy
///   2. An empty string `''` — placeholder padding
class HardcodedTextInWidgetRule extends DartLintRule {
  const HardcodedTextInWidgetRule() : super(code: _code);

  static const _code = LintCode(
    name: 'hardcoded_text_in_widget',
    problemMessage: 'Hardcoded English literal in Text(...). Localize via '
        'context.l10n.<key> with the key declared in lib/l10n/en.arb.',
    correctionMessage: 'Add a key to lib/l10n/en.arb and read it as '
        'Text(context.l10n.<key>). Single-character glyphs are exempt.',
    errorSeverity: ErrorSeverity.WARNING,
  );

  static const _exemptFragments = <String>[
    '/lib/l10n/',
    '/lib/generated/',
    '/lib/models/',
    '/lib/services/',
    '/lib/repositories/',
    '/lib/theme/',
    '/test/',
  ];

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    final filePath = resolver.path;
    if (_isExempt(filePath)) return;

    context.registry.addInstanceCreationExpression((node) {
      final typeName = node.constructorName.type.name2.lexeme;
      if (typeName != 'Text') return;

      final args = node.argumentList.arguments;
      if (args.isEmpty) return;

      // The first positional argument is the data string.
      final first = args.first;
      if (first is! StringLiteral) return;
      if (first is AdjacentStrings) {
        // Multi-line `'foo' 'bar'` literal — flag if any segment contains
        // chrome-like content. The simplest signal: it's not a glyph.
        final combined = first.stringValue ?? '';
        if (_isExemptLiteral(combined)) return;
        reporter.atNode(first, _code);
        return;
      }
      if (first is SimpleStringLiteral) {
        final value = first.value;
        if (_isExemptLiteral(value)) return;
        reporter.atNode(first, _code);
        return;
      }
      if (first is StringInterpolation) {
        // Interpolated strings still encode English between the variables.
        reporter.atNode(first, _code);
        return;
      }
    });
  }

  static bool _isExempt(String filePath) {
    for (final fragment in _exemptFragments) {
      if (filePath.contains(fragment)) return true;
    }
    return false;
  }

  /// Single-character glyphs and empty strings are not chrome.
  static bool _isExemptLiteral(String value) {
    if (value.isEmpty) return true;
    // Use rune length so that multi-code-unit glyphs like emoji still count
    // as a single visible character.
    if (value.runes.length == 1) return true;
    return false;
  }
}
