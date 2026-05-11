import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'src/forbidden_imports_rule.dart';
import 'src/hardcoded_text_in_widget_rule.dart';
import 'src/no_hardcoded_color_rule.dart';

PluginBase createPlugin() => _Plugin();

class _Plugin extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => const [
        ForbiddenImportsRule(),
        NoHardcodedColorRule(),
        HardcodedTextInWidgetRule(),
      ];
}
