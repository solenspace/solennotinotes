import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'src/forbidden_imports_rule.dart';

PluginBase createPlugin() => _Plugin();

class _Plugin extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => [const ForbiddenImportsRule()];
}
