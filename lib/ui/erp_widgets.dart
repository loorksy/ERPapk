// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'erp_theme.dart';

// ------------------------------------------------------------------ toast

enum ToastType { success, error, warning, info }

/// ERP `showToast(message, type)`.
void showToast(
  BuildContext context,
  String message, [
  ToastType type = ToastType.info,
]) {
  final (bg, fg, icon) = switch (type) {
    ToastType.success => (
      Tw.emerald600,
      Colors.white,
      FontAwesomeIcons.circleCheck,
    ),
    ToastType.error => (
      Tw.red600,
      Colors.white,
      FontAwesomeIcons.circleExclamation,
    ),
    ToastType.warning => (
      Tw.amber500,
      Colors.white,
      FontAwesomeIcons.triangleExclamation,
    ),
    ToastType.info => (Tw.slate800, Colors.white, FontAwesomeIcons.circleInfo),
  };
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: bg,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 76),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: Duration(seconds: type == ToastType.error ? 6 : 4),
        content: Row(
          children: [
            FaIcon(icon, color: fg, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: fg,
                  fontFamily: erpFont,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
}

// ------------------------------------------------------------------ cards

class ErpCard extends StatelessWidget {
  const ErpCard({
    super.key,
    required this.child,
    this.padding,
    this.clip = true,
  });
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool clip;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: clip ? Clip.antiAlias : Clip.none,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Tw.slate200),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0f0f172a),
          blurRadius: 3,
          offset: Offset(0, 1),
        ),
      ],
    ),
    padding: padding,
    child: child,
  );
}

/// A section inside a card, separated by a top border (`border-t`).
class CardSection extends StatelessWidget {
  const CardSection({
    super.key,
    required this.child,
    this.top = true,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final bool top;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      border: top ? const Border(top: BorderSide(color: Tw.slate200)) : null,
    ),
    padding: padding,
    child: child,
  );
}

/// The gradient icon tile + title used at the top of ERP pages.
class PageHeading extends StatelessWidget {
  const PageHeading({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });
  final FaIconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final heading = Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Tw.indigo600, Tw.indigo500],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x404f46e5),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: FaIcon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Tw.slate900,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: const TextStyle(fontSize: 12, color: Tw.slate500),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    if (trailing == null) return heading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [heading, const SizedBox(height: 14), trailing!],
    );
  }
}

// ----------------------------------------------------------------- labels

class FieldLabel extends StatelessWidget {
  const FieldLabel(
    this.text, {
    super.key,
    this.small = false,
    this.bold = false,
  });
  final String text;
  final bool small;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: small ? 12 : 14,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        color: small && !bold ? Tw.slate600 : Tw.slate700,
      ),
    ),
  );
}

class SectionCaption extends StatelessWidget {
  const SectionCaption(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: Tw.slate500,
      ),
    ),
  );
}

// ----------------------------------------------------------------- select

class SelectOption<T> {
  const SelectOption(this.value, this.label);
  final T value;
  final String label;
}

/// A `<select>` styled like ERP (`min-h-[44px] rounded-lg border-slate-300`).
class ErpSelect<T> extends StatelessWidget {
  const ErpSelect({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.muted = false,
    this.enabled = true,
    this.thick = false,
  });

  final List<SelectOption<T>> options;
  final T value;
  final ValueChanged<T>? onChanged;
  final bool muted;
  final bool enabled;

  /// `border-2 rounded-xl` variant used in the Sheet / search pages.
  final bool thick;

  @override
  Widget build(BuildContext context) {
    final has = options.any((o) => o.value == value);
    final effective =
        has ? value : (options.isEmpty ? null : options.first.value);
    final radius = BorderRadius.circular(thick ? 12 : 8);
    final side = BorderSide(
      color: thick ? Tw.slate200 : Tw.slate300,
      width: thick ? 2 : 1,
    );
    return DropdownButtonFormField<T>(
      value: effective,
      isExpanded: true,
      menuMaxHeight: 420,
      icon: const FaIcon(
        FontAwesomeIcons.chevronDown,
        size: 12,
        color: Tw.slate500,
      ),
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(12),
      style: const TextStyle(
        fontFamily: erpFont,
        fontSize: 14,
        color: Tw.slate900,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: muted ? Tw.slate50 : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(borderRadius: radius, borderSide: side),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: side,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: Tw.indigo500, width: 2),
        ),
      ),
      items: [
        for (final o in options)
          DropdownMenuItem<T>(
            value: o.value,
            child: Text(o.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged:
          !enabled || onChanged == null
              ? null
              : (v) {
                if (v != null || null is T) onChanged!(v as T);
              },
    );
  }
}

// ---------------------------------------------------------------- buttons

enum ErpButtonKind {
  indigo,
  emerald,
  outline,
  amber,
  slate,
  danger,
  soft,
  indigoSoft,
}

class ErpButton extends StatelessWidget {
  const ErpButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = ErpButtonKind.indigo,
    this.loading = false,
    this.loadingLabel,
    this.height = 44,
    this.expand = true,
    this.fontSize = 14,
  });

  final String label;
  final VoidCallback? onPressed;
  final FaIconData? icon;
  final ErpButtonKind kind;
  final bool loading;
  final String? loadingLabel;
  final double height;
  final bool expand;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (kind) {
      ErpButtonKind.indigo => (Tw.indigo600, Colors.white, null),
      ErpButtonKind.emerald => (Tw.emerald600, Colors.white, null),
      ErpButtonKind.amber => (Tw.amber600, Colors.white, null),
      ErpButtonKind.slate => (Tw.slate700, Colors.white, null),
      ErpButtonKind.danger => (Tw.red600, Colors.white, null),
      ErpButtonKind.outline => (Colors.white, Tw.slate800, Tw.slate300),
      ErpButtonKind.soft => (Tw.slate100, Tw.slate700, null),
      ErpButtonKind.indigoSoft => (Tw.indigo50, Tw.indigo800, Tw.indigo200),
    };
    final disabled = onPressed == null || loading;
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (icon != null)
          FaIcon(
            icon,
            size: 13,
            color:
                kind == ErpButtonKind.outline
                    ? Tw.slate500
                    : fg.withValues(alpha: 0.9),
          ),
        if (loading || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            loading ? (loadingLabel ?? label) : label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: erpFont,
              fontWeight: FontWeight.w700,
              fontSize: fontSize,
              color: fg,
            ),
          ),
        ),
      ],
    );
    return Opacity(
      opacity: disabled && !loading ? 0.6 : 1,
      child: SizedBox(
        height: height,
        width: expand ? double.infinity : null,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: disabled ? null : onPressed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: border == null ? null : Border.all(color: border),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- inputs

class ErpTextField extends StatelessWidget {
  const ErpTextField({
    super.key,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.ltr = false,
    this.onChanged,
    this.thick = false,
    this.maxLength,
    this.mono = false,
  });
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final bool ltr;
  final ValueChanged<String>? onChanged;
  final bool thick;
  final int? maxLength;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(thick ? 12 : 8);
    final side = BorderSide(
      color: thick ? Tw.slate200 : Tw.slate300,
      width: thick ? 2 : 1,
    );
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textDirection: ltr ? TextDirection.ltr : null,
      onChanged: onChanged,
      maxLength: maxLength,
      style: TextStyle(
        fontSize: 14,
        color: Tw.slate900,
        fontFamily: mono ? 'monospace' : erpFont,
      ),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        border: OutlineInputBorder(borderRadius: radius, borderSide: side),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: side,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: Tw.indigo500, width: 2),
        ),
      ),
    );
  }
}

/// `<input type=color>` + hex text field, like the ERP color pickers.
class ColorField extends StatefulWidget {
  const ColorField({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<ColorField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(covariant ColorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _text.text) _text.text = widget.value;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _ColorPickerDialog(initial: widget.value),
    );
    if (picked != null) widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      InkWell(
        onTap: _pick,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Tw.slate300),
            color: Colors.white,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: hexColor(widget.value),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: ErpTextField(
          controller: _text,
          ltr: true,
          mono: true,
          maxLength: 7,
          onChanged: (v) {
            if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v)) {
              widget.onChanged(v.toLowerCase());
            }
          },
        ),
      ),
    ],
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial});
  final String initial;
  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late String _value = widget.initial;
  static const _palette = <String>[
    '#8b5cf6',
    '#facc15',
    '#3b82f6',
    '#10b981',
    '#ef4444',
    '#f97316',
    '#f59e0b',
    '#84cc16',
    '#22c55e',
    '#14b8a6',
    '#06b6d4',
    '#0ea5e9',
    '#6366f1',
    '#a855f7',
    '#d946ef',
    '#ec4899',
    '#f43f5e',
    '#64748b',
    '#c4b5fd',
    '#fde68a',
    '#bfdbfe',
    '#a7f3d0',
    '#fecaca',
    '#fed7aa',
  ];

  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: const Text(
      'اختر اللون',
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
    content: SizedBox(
      width: 300,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in _palette)
            InkWell(
              onTap: () => setState(() => _value = c),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: hexColor(c),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _value == c ? Tw.slate900 : Tw.slate200,
                    width: _value == c ? 3 : 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: Tw.indigo600),
        onPressed: () => Navigator.pop(context, _value),
        child: const Text('اختيار'),
      ),
    ],
  );
}

// ----------------------------------------------------------------- badges

class ErpBadge extends StatelessWidget {
  const ErpBadge({
    super.key,
    required this.label,
    required this.icon,
    required this.bg,
    required this.fg,
    required this.border,
  });
  final String label;
  final FaIconData icon;
  final Color bg;
  final Color fg;
  final Color border;

  factory ErpBadge.google() => const ErpBadge(
    label: 'مرتبطة بـ Google',
    icon: FontAwesomeIcons.link,
    bg: Tw.emerald50,
    fg: Tw.emerald800,
    border: Tw.emerald200,
  );

  factory ErpBadge.local() => const ErpBadge(
    label: 'ملفات محلية',
    icon: FontAwesomeIcons.file,
    bg: Tw.amber50,
    fg: Tw.amber900,
    border: Tw.amber200,
  );

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FaIcon(icon, size: 10, color: fg),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      ],
    ),
  );
}

Future<String?> pasteText() async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  return data?.text?.trim();
}

/// `rounded-xl border bg-… p-3` notice boxes.
class NoticeBox extends StatelessWidget {
  const NoticeBox({
    super.key,
    required this.child,
    this.bg = Tw.slate50,
    this.border = Tw.slate200,
    this.padding = const EdgeInsets.all(12),
  });
  final Widget child;
  final Color bg;
  final Color border;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: border),
    ),
    child: child,
  );
}
