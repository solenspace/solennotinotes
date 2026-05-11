import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Fires on `Color(...)`, `Color.fromARGB(...)`, and `Color.fromRGBO(...)`
/// instantiations outside the token system. The token-system layer
/// (`lib/theme/tokens/`) and the curated palette data file
/// (`lib/theme/curated_palettes.dart`) are exempt — they own the raw
/// values; everywhere else should consume them via `context.tokens.colors.*`
/// or via a primitives import.
///
/// Ships at WARNING severity until Spec 11 retires the remaining legacy
/// color-picker UI; promotion to ERROR is a follow-up.
class NoHardcodedColorRule extends DartLintRule {
  const NoHardcodedColorRule() : super(code: _code);

  static const _code = LintCode(
    name: 'no_hardcoded_color',
    problemMessage: 'Hardcoded Color literal. Use context.tokens.colors.* '
        'or import primitives via lib/theme/tokens/.',
    correctionMessage: 'Move the literal to lib/theme/tokens/primitives.dart '
        '(if it is a primitive token) or to lib/theme/curated_palettes.dart '
        '(if it is curated palette data), then read it through tokens.',
    errorSeverity: ErrorSeverity.WARNING,
  );

  static const _exemptFragments = <String>[
    '/lib/theme/tokens/',
    '/lib/theme/curated_palettes.dart',
    // Test files legitimately construct Color fixtures as input data; the
    // rule applies to production code only.
    '/test/',
    '/integration_test/',
    // Model deserialization needs to construct Color from persisted ARGB
    // ints; these are not hardcoded literals.
    '/lib/models/',
    // Spec 23 share codec deserializes Color from peer-supplied signed
    // manifest ARGB ints; same rationale as /lib/models/.
    '/lib/services/share/',
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
      if (typeName != 'Color') return;
      reporter.atNode(node, _code);
    });
  }

  static bool _isExempt(String filePath) {
    for (final fragment in _exemptFragments) {
      if (filePath.contains(fragment)) return true;
    }
    return false;
  }
}
