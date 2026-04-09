import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import '../../theme/app_tokens.dart';
import 'editor_block.dart';

class _NewlineInterceptor extends TextInputFormatter {
  final VoidCallback onEnterOnEmpty;
  final ValueChanged<String> onEnterWithText;

  _NewlineInterceptor({
    required this.onEnterOnEmpty,
    required this.onEnterWithText,
  });

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // If the user typed a newline (\n)
    if (newValue.text.contains('\n')) {
      // If the block is completely empty and they press Enter,
      // it should exit the checklist format.
      if (oldValue.text.isEmpty && newValue.text == '\n') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onEnterOnEmpty();
        });
        return oldValue;
      }

      // Split at the insertion point of the newline
      final newlineIndex = newValue.text.indexOf('\n');
      final textBefore = newValue.text.substring(0, newlineIndex);
      final textAfter = newValue.text.substring(newlineIndex + 1);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        onEnterWithText(textAfter);
      });

      return TextEditingValue(
        text: textBefore,
        selection: TextSelection.collapsed(offset: textBefore.length),
      );
    }
    return newValue;
  }
}

/// A checkbox + text field row. Pressing Enter adds a sibling checklist
/// block via [onInsertBelow]. Pressing Backspace at position 0 of empty
/// text converts the block back to a text block via [onConvertToText].
class ChecklistBlockWidget extends StatefulWidget {
  final ChecklistBlock block;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool> onCheckedChanged;
  final ValueChanged<String> onInsertBelow;
  final VoidCallback onConvertToText;
  final Color? textColor;

  const ChecklistBlockWidget({
    super.key,
    required this.block,
    required this.focusNode,
    required this.onChanged,
    required this.onCheckedChanged,
    required this.onInsertBelow,
    required this.onConvertToText,
    this.textColor,
  });

  @override
  State<ChecklistBlockWidget> createState() => _ChecklistBlockWidgetState();
}

class _ChecklistBlockWidgetState extends State<ChecklistBlockWidget> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.block.text);
  }

  @override
  void didUpdateWidget(covariant ChecklistBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.block.text != _controller.text) {
      _controller.text = widget.block.text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _controller.text.isEmpty) {
      widget.onConvertToText();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.textColor ?? scheme.onSurface;
    final mutedColor = color.withValues(alpha: widget.block.checked ? 0.4 : 0.9);
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: mutedColor,
          decoration: widget.block.checked ? TextDecoration.lineThrough : null,
          decorationColor: mutedColor,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => widget.onCheckedChanged(!widget.block.checked),
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: AnimatedContainer(
                duration: AppDurations.xs,
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: widget.block.checked ? color : Colors.transparent,
                  border: Border.all(color: color.withValues(alpha: 0.6), width: 1.0),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: widget.block.checked
                    ? Icon(
                        Icons.check,
                        size: 16,
                        color: scheme.surface,
                      )
                    : null,
              ),
            ),
          ),
          const Gap(AppSpacing.md),
          Expanded(
            child: Focus(
              onKeyEvent: _handleKey,
              child: TextField(
                controller: _controller,
                focusNode: widget.focusNode,
                onChanged: (value) {
                  widget.block.text = value;
                  widget.onChanged(value);
                },
                inputFormatters: [
                  _NewlineInterceptor(
                    onEnterOnEmpty: widget.onConvertToText,
                    onEnterWithText: (textAfter) {
                      widget.block.text = _controller.text;
                      widget.onChanged(_controller.text);
                      widget.onInsertBelow(textAfter);
                    },
                  ),
                ],
            textInputAction: TextInputAction.newline,
                keyboardType: TextInputType.multiline,
                maxLines: null,
                minLines: 1,
                style: style,
                cursorColor: color,
                decoration: InputDecoration(
                  isCollapsed: true,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'List item',
                  hintStyle: style?.copyWith(
                    color: color.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
