// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'erp_theme.dart';

/// «Compact Fluid UI» — the design system of «المدقق» (3.0).
///
/// Light surfaces with hairline borders, no gradients or heavy shadows,
/// one accent colour for interaction and selection, compact controls that
/// keep 44 px touch targets, and details behind a small «!» (owner's
/// request) instead of text under every control.
abstract final class Ds {
  static const pagePadding = EdgeInsets.fromLTRB(14, 12, 14, 28);
  static const gapS = 6.0;
  static const gapM = 10.0;
  static const radius = 14.0;
  static const radiusS = 10.0;
  static const touch = 44.0;

  static const title = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: Tw.slate900,
  );
  static const body = TextStyle(fontSize: 14, color: Tw.slate900);
  static const secondary = TextStyle(fontSize: 12.5, color: Tw.slate500);
  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: Tw.slate500,
    letterSpacing: 0.2,
  );
}

/// Vertical space between blocks.
const gap = SizedBox(height: Ds.gapM);

// ---------------------------------------------------------------- help

/// A small «!»: tapping it shows the details of an option or an action.
class InfoTip extends StatelessWidget {
  const InfoTip(this.text, {super.key, this.title, this.size = 17});
  final String text;
  final String? title;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'تفاصيل',
    child: InkResponse(
      radius: 20,
      onTap: () => showInfo(context, text, title: title),
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(Icons.error_outline, size: size, color: Tw.slate400),
      ),
    ),
  );
}

Future<void> showInfo(BuildContext context, String text, {String? title}) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder:
          (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.7,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SheetHandle(),
                      const SizedBox(height: 12),
                      Text(title ?? 'تفاصيل', style: Ds.title),
                      const SizedBox(height: 8),
                      Text(
                        text,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: Tw.slate600,
                          height: 1.75,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 32,
      height: 4,
      decoration: BoxDecoration(
        color: Tw.slate200,
        borderRadius: BorderRadius.circular(99),
      ),
    ),
  );
}

// ------------------------------------------------------------ surfaces

BoxDecoration panelDecoration({Color? border, Color? color}) => BoxDecoration(
  color: color ?? Colors.white,
  borderRadius: BorderRadius.circular(Ds.radius),
  border: Border.all(color: border ?? Tw.slate200),
);

/// A small neutral square with an icon (leading element of rows).
class IconChip extends StatelessWidget {
  const IconChip(
    this.icon, {
    super.key,
    this.color = Tw.slate600,
    this.bg = Tw.slate100,
    this.size = 32,
  });
  final IconData icon;
  final Color color;
  final Color bg;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(size * 0.3),
    ),
    alignment: Alignment.center,
    child: Icon(icon, size: size * 0.56, color: color),
  );
}

/// A white surface with an optional header (title, «!», action).
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    this.title,
    this.icon,
    this.iconColor = Tw.slate600,
    this.iconBg = Tw.slate100,
    this.info,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });
  final String? title;
  final IconData? icon;
  final Color iconColor;
  final Color iconBg;
  final String? info;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    decoration: panelDecoration(),
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          PanelHeader(
            title: title!,
            icon: icon,
            iconColor: iconColor,
            iconBg: iconBg,
            info: info,
            trailing: trailing,
          ),
          const SizedBox(height: 10),
        ],
        child,
      ],
    ),
  );
}

class PanelHeader extends StatelessWidget {
  const PanelHeader({
    super.key,
    required this.title,
    this.icon,
    this.iconColor = Tw.slate600,
    this.iconBg = Tw.slate100,
    this.info,
    this.trailing,
    this.subtitle,
  });
  final String title;
  final IconData? icon;
  final Color iconColor;
  final Color iconBg;
  final String? info;
  final Widget? trailing;
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (icon != null) ...[
        IconChip(icon!, color: iconColor, bg: iconBg, size: 30),
        const SizedBox(width: 10),
      ],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Ds.title),
            if (subtitle != null) ...[const SizedBox(height: 2), subtitle!],
          ],
        ),
      ),
      if (info != null) InfoTip(info!, title: title),
      if (trailing != null) trailing!,
    ],
  );
}

/// A surface whose content folds away; the header summarises the choices
/// while folded (progressive disclosure).
class CollapsiblePanel extends StatefulWidget {
  const CollapsiblePanel({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.iconColor = Tw.slate600,
    this.iconBg = Tw.slate100,
    this.summary,
    this.info,
    this.initiallyExpanded = false,
  });
  final String title;
  final Widget child;
  final IconData? icon;
  final Color iconColor;
  final Color iconBg;
  final Widget? summary;
  final String? info;
  final bool initiallyExpanded;

  @override
  State<CollapsiblePanel> createState() => _CollapsiblePanelState();
}

class _CollapsiblePanelState extends State<CollapsiblePanel> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) => Container(
    decoration: panelDecoration(),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
            child: PanelHeader(
              title: widget.title,
              icon: widget.icon,
              iconColor: widget.iconColor,
              iconBg: widget.iconBg,
              info: widget.info,
              subtitle: _open ? null : widget.summary,
              trailing: AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: const SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(Icons.expand_more, size: 20, color: Tw.slate400),
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child:
              _open
                  ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
                    child: widget.child,
                  )
                  : const SizedBox(width: double.infinity),
        ),
      ],
    ),
  );
}

// -------------------------------------------------------- grouped rows

/// The small grey title above a group of rows.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.icon});
  final String text;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: Tw.slate500),
          const SizedBox(width: 6),
        ],
        Expanded(child: Text(text, style: Ds.caption)),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

/// Rows in one surface, separated by inset hairlines.
class GroupList extends StatelessWidget {
  const GroupList({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: panelDecoration(),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14),
          children[i],
        ],
      ],
    ),
  );
}

/// One compact row: leading, title, subtitle, trailing.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.titleColor,
  });
  final String title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? Tw.indigo50 : Colors.white,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: titleColor ?? Tw.slate900,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      DefaultTextStyle.merge(
                        style: Ds.secondary,
                        child: subtitle!,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    ),
  );
}

/// The chevron at the end of a navigable row (points left in RTL).
class RowChevron extends StatelessWidget {
  const RowChevron({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsetsDirectional.only(start: 4, end: 6),
    child: Icon(Icons.chevron_left, size: 20, color: Tw.slate400),
  );
}

// ------------------------------------------------------------- statuses

enum Tone { neutral, accent, success, warning, danger }

(Color bg, Color fg) toneColors(Tone t) => switch (t) {
  Tone.neutral => (Tw.slate100, Tw.slate600),
  Tone.accent => (Tw.indigo50, Tw.indigo700),
  Tone.success => (Tw.emerald50, Tw.emerald700),
  Tone.warning => (Tw.amber50, Tw.amber800),
  Tone.danger => (Tw.red50, Tw.red700),
};

/// A small status label: «مكتمل»، «قيد التنفيذ»…
class StatusBadge extends StatelessWidget {
  const StatusBadge(
    this.label, {
    super.key,
    this.tone = Tone.neutral,
    this.icon,
  });
  final String label;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = toneColors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kept for older call sites: a neutral or coloured status label.
class Pill extends StatelessWidget {
  const Pill(
    this.label, {
    super.key,
    this.icon,
    this.bg = Tw.slate100,
    this.fg = Tw.slate600,
  });
  final String label;
  final IconData? icon;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A small coloured dot (connection state, colour settings).
class ColorDot extends StatelessWidget {
  const ColorDot(this.color, {super.key, this.size = 10});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    margin: const EdgeInsetsDirectional.only(start: 4),
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 1.5),
      boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 1)],
    ),
  );
}

// ---------------------------------------------------------- numbers

/// A number with its label (period summary, audit results).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.color = Tw.slate900,
    this.bg = Colors.white,
    this.icon,
    this.selected = false,
  });
  final String label;
  final String value;
  final Color color;
  final Color bg;
  final IconData? icon;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    decoration: BoxDecoration(
      color: selected ? Tw.indigo50 : bg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: selected ? Tw.indigo200 : Tw.slate200),
    ),
    child: Column(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
        ],
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5, color: Tw.slate500),
        ),
      ],
    ),
  );
}

/// A result line: icon, label, value (with a tone) and an optional action.
class MetricRow extends StatelessWidget {
  const MetricRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.tone = Tone.neutral,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final Tone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = toneColors(tone);
    return ListRow(
      title: label,
      leading: IconChip(icon, color: fg, bg: bg, size: 30),
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: tone == Tone.neutral ? Tw.slate900 : fg,
            ),
          ),
          if (onTap != null) const RowChevron() else const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// A circular progress with the percentage in the middle.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 64,
    this.color = Tw.indigo600,
  });

  /// 0..1, or null while the total is not known yet.
  final double? value;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: value,
            strokeWidth: 5,
            strokeCap: StrokeCap.round,
            backgroundColor: Tw.slate100,
            color: color,
          ),
        ),
        if (value != null)
          Text(
            '${(math.max(0, math.min(1, value!)) * 100).round()}%',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: size * 0.24,
              fontWeight: FontWeight.w800,
              color: Tw.slate900,
            ),
          ),
      ],
    ),
  );
}

// ---------------------------------------------------------- workflow

/// One step of [StepIndicator].
class StepItem {
  const StepItem(this.label, {this.done = false});
  final String label;
  final bool done;
}

/// A compact horizontal sequence of steps; the current one is outlined in
/// the accent colour, finished ones carry a check. Tapping a step calls
/// [onTap] with its index.
class StepIndicator extends StatelessWidget {
  const StepIndicator({
    super.key,
    required this.steps,
    required this.current,
    this.onTap,
  });
  final List<StepItem> steps;
  final int current;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < steps.length; i++)
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap == null ? null : () => onTap!(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 2,
                          color:
                              i == 0
                                  ? Colors.transparent
                                  : (steps[i - 1].done
                                      ? Tw.indigo600
                                      : Tw.slate200),
                        ),
                      ),
                      _dot(i),
                      Expanded(
                        child: Container(
                          height: 2,
                          color:
                              i == steps.length - 1
                                  ? Colors.transparent
                                  : (steps[i].done
                                      ? Tw.indigo600
                                      : Tw.slate200),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    steps[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight:
                          i == current ? FontWeight.w700 : FontWeight.w500,
                      color:
                          i == current
                              ? Tw.indigo700
                              : (steps[i].done ? Tw.slate700 : Tw.slate400),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  Widget _dot(int i) {
    final s = steps[i];
    final isCurrent = i == current;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: s.done && !isCurrent ? Tw.indigo600 : Colors.white,
        border: Border.all(
          color: isCurrent || s.done ? Tw.indigo600 : Tw.slate300,
          width: isCurrent ? 2 : 1.5,
        ),
      ),
      alignment: Alignment.center,
      child:
          s.done && !isCurrent
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : Text(
                '${i + 1}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isCurrent ? Tw.indigo700 : Tw.slate400,
                ),
              ),
    );
  }
}

// --------------------------------------------------------------- misc

/// A short grey summary line (folded panels, step summaries).
class SummaryText extends StatelessWidget {
  const SummaryText(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: Ds.secondary,
  );
}

/// A field label with an optional «!».
class FieldHeader extends StatelessWidget {
  const FieldHeader(this.label, {super.key, this.info});
  final String label;
  final String? info;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: info == null ? 6 : 0),
    child: Row(
      children: [
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Tw.slate600,
            ),
          ),
        ),
        if (info != null) InfoTip(info!, title: label, size: 15),
      ],
    ),
  );
}

/// An action with its «!» beside it.
class ActionWithInfo extends StatelessWidget {
  const ActionWithInfo({
    super.key,
    required this.button,
    required this.info,
    this.title,
  });
  final Widget button;
  final String info;
  final String? title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: button),
      const SizedBox(width: 2),
      InfoTip(info, title: title),
    ],
  );
}

/// A friendly empty state with an optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.leading,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  /// Replaces the icon (e.g. the app logo on the welcome state).
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Container(
    decoration: panelDecoration(),
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
    child: Column(
      children: [
        leading ??
            IconChip(icon, size: 48, color: Tw.indigo600, bg: Tw.indigo50),
        const SizedBox(height: 12),
        Text(title, style: Ds.title, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Tw.slate500, height: 1.6),
        ),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}
