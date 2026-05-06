import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:noti_notes_app/models/editor_block.dart';
import 'package:noti_notes_app/theme/tokens/primitives.dart';

class _NewlineInterceptor extends TextInputFormatter {
  final ValueChanged<String> onEnter;

  _NewlineInterceptor({required this.onEnter});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.contains('\n')) {
      final newlineIndex = newValue.text.indexOf('\n');
      final textBefore = newValue.text.substring(0, newlineIndex);
      final textAfter = newValue.text.substring(newlineIndex + 1);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        onEnter(textAfter);
      });

      return TextEditingValue(
        text: textBefore,
        selection: TextSelection.collapsed(offset: textBefore.length),
      );
    }
    return newValue;
  }
}

/// A multi-line text block. Pressing Enter on an empty line at the end
/// inserts a sibling text block via [onInsertBelow]. Pressing Backspace at
/// position 0 of an empty block triggers [onDeleteBlock].
class TextBlockWidget extends StatefulWidget {
  final TextBlock block;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onInsertBelow;
  final VoidCallback onDeleteBlock;
  final VoidCallback? onConvertToChecklist;
  final Color? textColor;

  const TextBlockWidget({
    super.key,
    required this.block,
    required this.focusNode,
    required this.onChanged,
    required this.onInsertBelow,
    required this.onDeleteBlock,
    this.onConvertToChecklist,
    this.textColor,
  });

  @override
  State<TextBlockWidget> createState() => _TextBlockWidgetState();
}

class _TextBlockWidgetState extends State<TextBlockWidget> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.block.text);
  }

  @override
  void didUpdateWidget(covariant TextBlockWidget oldWidget) {
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
    if (event.logicalKey == LogicalKeyboardKey.backspace && _controller.text.isEmpty) {
      widget.onDeleteBlock();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: widget.textColor,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingPrimitives.xs),
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
              onEnter: (textAfter) {
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
          cursorColor: widget.textColor ?? Theme.of(context).colorScheme.primary,
          decoration: InputDecoration(
            isCollapsed: true,
            isDense: true,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.zero,
            hintText: 'Start typing…',
            hintStyle: style?.copyWith(
              color: (widget.textColor ?? style.color)?.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}
