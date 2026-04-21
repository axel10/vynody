import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/audio_riverpod.dart';
import '../player/shortcut_bindings.dart';

Future<void> showShortcutSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const ShortcutSettingsDialog(),
  );
}

class ShortcutSettingsDialog extends ConsumerStatefulWidget {
  const ShortcutSettingsDialog({super.key});

  @override
  ConsumerState<ShortcutSettingsDialog> createState() =>
      _ShortcutSettingsDialogState();
}

class _ShortcutSettingsDialogState
    extends ConsumerState<ShortcutSettingsDialog> {
  late Map<AppShortcutAction, ShortcutBinding> _draftBindings;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    final settings = ref.read(settingsServiceProvider);
    _draftBindings = {
      for (final action in AppShortcutAction.values)
        action: settings.shortcutBinding(action),
    };
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _restoreDefaults() {
    setState(() {
      _draftBindings = {
        for (final action in AppShortcutAction.values)
          action: action.defaultBinding,
      };
    });
  }

  void _save() {
    final settings = ref.read(settingsServiceProvider);
    settings.setShortcutBindings({
      for (final action in AppShortcutAction.values)
        action: _draftBindings[action] ?? action.defaultBinding,
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.72;

    return AlertDialog(
      title: const Text('自定义快捷键'),
      content: SizedBox(
        width: 760,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Scrollbar(
            controller: _scrollController,
            child: ListView.separated(
              controller: _scrollController,
              shrinkWrap: true,
              itemCount: AppShortcutAction.values.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final action = AppShortcutAction.values[index];
                final binding = _draftBindings[action] ?? action.defaultBinding;
                return _ShortcutBindingRow(
                  action: action,
                  binding: binding,
                  onChanged: (nextBinding) {
                    setState(() {
                      _draftBindings[action] = nextBinding;
                    });
                  },
                  theme: theme,
                );
              },
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        OutlinedButton(onPressed: _restoreDefaults, child: const Text('恢复默认')),
        FilledButton(onPressed: _save, child: const Text('确定')),
      ],
    );
  }
}

class _ShortcutBindingRow extends StatelessWidget {
  const _ShortcutBindingRow({
    required this.action,
    required this.binding,
    required this.onChanged,
    required this.theme,
  });

  final AppShortcutAction action;
  final ShortcutBinding binding;
  final ValueChanged<ShortcutBinding> onChanged;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(action.label, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(action.description, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 260,
              child: ShortcutRecorderField(
                value: binding,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ShortcutRecorderField extends StatefulWidget {
  const ShortcutRecorderField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ShortcutBinding value;
  final ValueChanged<ShortcutBinding> onChanged;

  @override
  State<ShortcutRecorderField> createState() => _ShortcutRecorderFieldState();
}

class _ShortcutRecorderFieldState extends State<ShortcutRecorderField> {
  late final FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'shortcut-recorder');
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  void _onKeyEvent(KeyEvent event) {
    final binding = ShortcutBinding.fromKeyEvent(event);
    if (binding == null) {
      return;
    }

    widget.onChanged(binding);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveBinding = widget.value;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: false,
      onKeyEvent: _onKeyEvent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _focusNode.requestFocus(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: _isFocused
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.7)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused
                  ? theme.colorScheme.primary
                  : theme.dividerColor.withValues(alpha: 0.6),
              width: _isFocused ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isFocused ? '请按下组合键' : '点击录制',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _isFocused
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                effectiveBinding.displayLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
