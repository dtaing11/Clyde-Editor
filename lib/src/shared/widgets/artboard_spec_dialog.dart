import 'package:flutter/material.dart';

import '../../core/theme/editor_theme.dart';
import 'color_picker.dart';

/// Result of the new-artboard dialog.
final class ArtboardSpec {
  const ArtboardSpec({
    required this.name,
    required this.width,
    required this.height,
    required this.backgroundColor,
  });

  final String name;
  final double width;
  final double height;

  /// ARGB fill; `null` means transparent.
  final int? backgroundColor;
}

/// Themed dialog collecting artboard name, size in px, and background
/// (transparent or a hex colour). Returns `null` on cancel.
Future<ArtboardSpec?> showArtboardSpecDialog(
  BuildContext context, {
  String title = 'New Artboard',
  String initialName = 'Artboard',
}) {
  return showDialog<ArtboardSpec>(
    context: context,
    builder: (context) =>
        _ArtboardSpecDialog(title: title, initialName: initialName),
  );
}

class _ArtboardSpecDialog extends StatefulWidget {
  const _ArtboardSpecDialog({required this.title, required this.initialName});

  final String title;
  final String initialName;

  @override
  State<_ArtboardSpecDialog> createState() => _ArtboardSpecDialogState();
}

class _ArtboardSpecDialogState extends State<_ArtboardSpecDialog> {
  static const double _defaultSize = 500;

  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  final TextEditingController _width = TextEditingController(text: '500');
  final TextEditingController _height = TextEditingController(text: '500');
  final TextEditingController _hex = TextEditingController(text: 'FFFFFF');
  bool _transparent = true;

  @override
  void dispose() {
    _name.dispose();
    _width.dispose();
    _height.dispose();
    _hex.dispose();
    super.dispose();
  }

  void _submit() {
    final width = double.tryParse(_width.text) ?? _defaultSize;
    final height = double.tryParse(_height.text) ?? _defaultSize;
    final color = _transparent ? null : parseHexColor(_hex.text);
    if (!_transparent && color == null) return; // Invalid hex: stay open.
    Navigator.of(context).pop(
      ArtboardSpec(
        name: _name.text.trim().isEmpty
            ? widget.initialName
            : _name.text.trim(),
        width: width.clamp(1, 100000),
        height: height.clamp(1, 100000),
        backgroundColor: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _transparent ? null : parseHexColor(_hex.text);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LabeledField(
              label: 'Name',
              child: TextField(controller: _name),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _LabeledField(
                    label: 'Width (px)',
                    child: TextField(
                      controller: _width,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _LabeledField(
                    label: 'Height (px)',
                    child: TextField(
                      controller: _height,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: _transparent,
                  onChanged: (value) =>
                      setState(() => _transparent = value ?? true),
                ),
                const Text(
                  'Transparent background',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            if (!_transparent) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: preview != null ? Color(preview) : null,
                      border: Border.all(color: EditorTheme.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('#', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _hex,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'RRGGBB or AARRGGBB',
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: EditorTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}
