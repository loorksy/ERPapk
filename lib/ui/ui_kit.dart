// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'erp_theme.dart';

/// Building blocks of the app's own design (owner's request, 2026-11-17):
/// panels without page headings (the top bar names the page), a small «!»
/// instead of explanations under every option, and option groups that
/// fold away.

/// A small «!»: tapping it shows the details of an option or a button.
class InfoTip extends StatelessWidget {
  const InfoTip(this.text, {super.key, this.title, this.size = 15});
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
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: FaIcon(
          FontAwesomeIcons.circleExclamation,
          size: size,
          color: Tw.slate400,
        ),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Tw.slate200,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const FaIcon(
                            FontAwesomeIcons.circleExclamation,
                            size: 15,
                            color: Tw.indigo600,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title ?? 'تفاصيل',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Tw.slate900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
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

/// The coloured square with an icon at the start of a panel header.
class IconChip extends StatelessWidget {
  const IconChip(
    this.icon, {
    super.key,
    this.color = Tw.indigo600,
    this.bg = Tw.indigo50,
    this.size = 32,
  });
  final FaIconData icon;
  final Color color;
  final Color bg;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(size * 0.32),
    ),
    alignment: Alignment.center,
    child: FaIcon(icon, size: size * 0.42, color: color),
  );
}

BoxDecoration panelDecoration({Color? border}) => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(18),
  border: Border.all(color: border ?? const Color(0xffe8ecf2)),
  boxShadow: const [
    BoxShadow(color: Color(0x0a0f172a), blurRadius: 12, offset: Offset(0, 4)),
  ],
);

/// A card with an optional header: icon, title, «!» and an action.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    this.title,
    this.icon,
    this.iconColor = Tw.indigo600,
    this.iconBg = Tw.indigo50,
    this.info,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final String? title;
  final FaIconData? icon;
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
          const SizedBox(height: 14),
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
    this.iconColor = Tw.indigo600,
    this.iconBg = Tw.indigo50,
    this.info,
    this.trailing,
    this.subtitle,
  });
  final String title;
  final FaIconData? icon;
  final Color iconColor;
  final Color iconBg;
  final String? info;
  final Widget? trailing;
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (icon != null) ...[
        IconChip(icon!, color: iconColor, bg: iconBg),
        const SizedBox(width: 10),
      ],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Tw.slate800,
              ),
            ),
            if (subtitle != null) ...[const SizedBox(height: 2), subtitle!],
          ],
        ),
      ),
      if (info != null) InfoTip(info!, title: title),
      if (trailing != null) trailing!,
    ],
  );
}

/// A panel whose content folds away; the header shows a short summary of
/// the choices while folded.
class CollapsiblePanel extends StatefulWidget {
  const CollapsiblePanel({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.iconColor = Tw.indigo600,
    this.iconBg = Tw.indigo50,
    this.summary,
    this.info,
    this.initiallyExpanded = false,
  });
  final String title;
  final Widget child;
  final FaIconData? icon;
  final Color iconColor;
  final Color iconBg;

  /// Shown under the title while folded.
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
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
            child: PanelHeader(
              title: widget.title,
              icon: widget.icon,
              iconColor: widget.iconColor,
              iconBg: widget.iconBg,
              info: widget.info,
              subtitle: _open ? null : widget.summary,
              trailing: AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: FaIcon(
                    FontAwesomeIcons.chevronDown,
                    size: 13,
                    color: Tw.slate400,
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child:
              _open
                  ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: widget.child,
                  )
                  : const SizedBox(width: double.infinity),
        ),
      ],
    ),
  );
}

/// A short grey summary line (used while a panel is folded).
class SummaryText extends StatelessWidget {
  const SummaryText(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(fontSize: 12, color: Tw.slate500),
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
        if (info != null) InfoTip(info!, title: label, size: 13),
      ],
    ),
  );
}

/// A button with its «!» beside it.
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
      const SizedBox(width: 4),
      InfoTip(info, title: title),
    ],
  );
}

/// A small coloured pill (status, counts).
class Pill extends StatelessWidget {
  const Pill(
    this.label, {
    super.key,
    this.icon,
    this.bg = Tw.slate100,
    this.fg = Tw.slate700,
  });
  final String label;
  final FaIconData? icon;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          FaIcon(icon, size: 10, color: fg),
          const SizedBox(width: 5),
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

/// A number with its label (results, totals).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.color = Tw.indigo600,
    this.bg = Tw.slate50,
  });
  final String label;
  final String value;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11.5, color: Tw.slate500),
        ),
      ],
    ),
  );
}

/// Vertical space between panels.
const gap = SizedBox(height: 12);

/// A colour dot (summary of the colour settings).
class ColorDot extends StatelessWidget {
  const ColorDot(this.color, {super.key});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    margin: const EdgeInsetsDirectional.only(start: 4),
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 1.5),
      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 1)],
    ),
  );
}
