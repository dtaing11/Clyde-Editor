import 'package:flutter/material.dart';

import '../../core/theme/editor_theme.dart';

/// Parses `RRGGBB` or `AARRGGBB` (optional leading #) to ARGB.
int? parseHexColor(String input) {
  final cleaned = input.trim().replaceFirst('#', '');
  if (cleaned.length != 6 && cleaned.length != 8) return null;
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return null;
  return cleaned.length == 6 ? 0xFF000000 | value : value;
}

/// Formats ARGB as `RRGGBB` (opaque) or `AARRGGBB`.
String formatHexColor(int argb) {
  final alpha = (argb >> 24) & 0xFF;
  final hex = argb.toRadixString(16).padLeft(8, '0').toUpperCase();
  return alpha == 0xFF ? hex.substring(2) : hex;
}

/// Compact colour editor: swatch + hex field. Tapping the swatch opens
/// the full [EditorColorPicker] popup. Every change reports through
/// [onChanged] as ARGB.
class ColorField extends StatefulWidget {
  const ColorField({
    super.key,
    required this.label,
    required this.color,
    required this.onChanged,
  });

  final String label;

  /// Current ARGB value.
  final int color;

  final ValueChanged<int> onChanged;

  @override
  State<ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<ColorField> {
  late final TextEditingController _hex = TextEditingController(
    text: formatHexColor(widget.color),
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commitHex();
    });
  }

  @override
  void didUpdateWidget(ColorField old) {
    super.didUpdateWidget(old);
    if (old.color != widget.color && !_focus.hasFocus) {
      _hex.text = formatHexColor(widget.color);
    }
  }

  @override
  void dispose() {
    _hex.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commitHex() {
    final parsed = parseHexColor(_hex.text);
    if (parsed != null && parsed != widget.color) {
      widget.onChanged(parsed);
    } else {
      _hex.text = formatHexColor(widget.color);
    }
  }

  Future<void> _openPicker() async {
    await showEditorColorPicker(
      context,
      initialColor: widget.color,
      onChanged: widget.onChanged,
    );
    if (mounted) _hex.text = formatHexColor(widget.color);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              widget.label,
              style: const TextStyle(
                fontSize: 11,
                color: EditorTheme.textSecondary,
              ),
            ),
          ),
          GestureDetector(
            onTap: _openPicker,
            child: Container(
              width: 24,
              height: 18,
              decoration: BoxDecoration(
                color: Color(widget.color),
                border: Border.all(color: EditorTheme.border),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SizedBox(
              height: 24,
              child: TextField(
                controller: _hex,
                focusNode: _focus,
                onSubmitted: (_) => _commitHex(),
                style: const TextStyle(fontSize: 11),
                decoration: const InputDecoration(
                  prefixText: '#',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
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

/// Shows the themed colour picker dialog. [onChanged] fires live while
/// the user adjusts, so callers can dispatch mergeable commands and see
/// the canvas update in real time.
Future<void> showEditorColorPicker(
  BuildContext context, {
  required int initialColor,
  required ValueChanged<int> onChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: EditorColorPicker(
          initialColor: initialColor,
          onChanged: onChanged,
        ),
      ),
    ),
  );
}

/// HSV colour picker: saturation/value area, hue slider, alpha slider,
/// and hex entry.
class EditorColorPicker extends StatefulWidget {
  const EditorColorPicker({
    super.key,
    required this.initialColor,
    required this.onChanged,
  });

  final int initialColor;
  final ValueChanged<int> onChanged;

  @override
  State<EditorColorPicker> createState() => _EditorColorPickerState();
}

class _EditorColorPickerState extends State<EditorColorPicker> {
  late HSVColor _hsv = HSVColor.fromColor(Color(widget.initialColor));
  late final TextEditingController _hex = TextEditingController(
    text: formatHexColor(widget.initialColor),
  );

  int get _argb => _hsv.toColor().toARGB32();

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _update(HSVColor hsv) {
    setState(() {
      _hsv = hsv;
      _hex.text = formatHexColor(_argb);
    });
    widget.onChanged(_argb);
  }

  void _commitHex(String text) {
    final parsed = parseHexColor(text);
    if (parsed == null) return;
    _update(HSVColor.fromColor(Color(parsed)));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SaturationValueArea(hsv: _hsv, onChanged: _update),
          const SizedBox(height: 10),
          _HueSlider(hsv: _hsv, onChanged: _update),
          const SizedBox(height: 8),
          _AlphaSlider(hsv: _hsv, onChanged: _update),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 28,
                height: 22,
                decoration: BoxDecoration(
                  color: _hsv.toColor(),
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
                  onSubmitted: _commitHex,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Saturation (x) / value (y) gradient square with a drag thumb.
class _SaturationValueArea extends StatelessWidget {
  const _SaturationValueArea({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  void _handle(Offset local, Size size) {
    final saturation = (local.dx / size.width).clamp(0.0, 1.0);
    final value = 1 - (local.dy / size.height).clamp(0.0, 1.0);
    onChanged(hsv.withSaturation(saturation).withValue(value));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return GestureDetector(
            onPanDown: (d) => _handle(d.localPosition, size),
            onPanUpdate: (d) => _handle(d.localPosition, size),
            child: CustomPaint(
              painter: _SaturationValuePainter(hsv),
              size: size,
            ),
          );
        },
      ),
    );
  }
}

class _SaturationValuePainter extends CustomPainter {
  _SaturationValuePainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hueColor = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, hueColor],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );

    final thumb = Offset(
      hsv.saturation * size.width,
      (1 - hsv.value) * size.height,
    );
    canvas.drawCircle(
      thumb,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_SaturationValuePainter old) => old.hsv != hsv;
}

/// Horizontal hue slider (0-360).
class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  void _handle(Offset local, Size size) {
    final hue = (local.dx / size.width).clamp(0.0, 1.0) * 360;
    onChanged(hsv.withHue(hue.clamp(0, 359.99)));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 14,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return GestureDetector(
            onPanDown: (d) => _handle(d.localPosition, size),
            onPanUpdate: (d) => _handle(d.localPosition, size),
            child: CustomPaint(painter: _HuePainter(hsv.hue), size: size),
          );
        },
      ),
    );
  }
}

class _HuePainter extends CustomPainter {
  _HuePainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()
        ..shader = LinearGradient(
          colors: [
            for (var h = 0; h <= 360; h += 60)
              HSVColor.fromAHSV(
                1,
                h.toDouble().clamp(0, 359.99),
                1,
                1,
              ).toColor(),
          ],
        ).createShader(rect),
    );
    _paintSliderThumb(canvas, size, hue / 360);
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}

/// Horizontal alpha slider over a checkerboard.
class _AlphaSlider extends StatelessWidget {
  const _AlphaSlider({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  void _handle(Offset local, Size size) {
    onChanged(hsv.withAlpha((local.dx / size.width).clamp(0.0, 1.0)));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 14,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return GestureDetector(
            onPanDown: (d) => _handle(d.localPosition, size),
            onPanUpdate: (d) => _handle(d.localPosition, size),
            child: CustomPaint(painter: _AlphaPainter(hsv), size: size),
          );
        },
      ),
    );
  }
}

class _AlphaPainter extends CustomPainter {
  _AlphaPainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.save();
    canvas.clipRRect(rrect);
    _paintCheckerboard(canvas, size);
    canvas.restore();

    final opaque = hsv.withAlpha(1).toColor();
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          colors: [opaque.withValues(alpha: 0), opaque],
        ).createShader(rect),
    );
    _paintSliderThumb(canvas, size, hsv.alpha);
  }

  static void _paintCheckerboard(Canvas canvas, Size size) {
    const cell = 5.0;
    final light = Paint()..color = const Color(0xFFCCCCCC);
    final dark = Paint()..color = const Color(0xFF888888);
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = 0; x * cell < size.width; x++) {
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell, cell),
          (x + y).isEven ? light : dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_AlphaPainter old) => old.hsv != hsv;
}

void _paintSliderThumb(Canvas canvas, Size size, double fraction) {
  final x = fraction * size.width;
  canvas.drawCircle(
    Offset(x.clamp(4, size.width - 4), size.height / 2),
    5,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white,
  );
}
