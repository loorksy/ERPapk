// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../services/payroll_service.dart';
import 'erp_theme.dart';
import 'erp_widgets.dart';

/// Popup listing the agent-sheet users who are not audited yet:
/// id (column A) and name (column C), the remaining count, and copy.
Future<void> showUnauditedDialog(
  BuildContext context,
  PendingAgentMembers data,
) => showDialog<void>(
  context: context,
  builder:
      (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: _UnauditedDialog(data: data),
      ),
);

class _UnauditedDialog extends StatefulWidget {
  const _UnauditedDialog({required this.data});
  final PendingAgentMembers data;
  @override
  State<_UnauditedDialog> createState() => _UnauditedDialogState();
}

class _UnauditedDialogState extends State<_UnauditedDialog> {
  final _filter = TextEditingController();
  String _query = '';
  String? _copied;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  List<PendingMember> get _visible {
    final q = _query.trim();
    if (q.isEmpty) return widget.data.members;
    return [
      for (final m in widget.data.members)
        if (m.id.contains(q) || m.name.contains(q)) m,
    ];
  }

  Future<void> _copy({required bool idsOnly}) async {
    final list = _visible;
    final text = [
      for (final m in list) idsOnly ? m.id : '${m.id}\t${m.name}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(
      () =>
          _copied =
              idsOnly
                  ? 'تم نسخ ${list.length} رقم'
                  : 'تم نسخ ${list.length} صف (الرقم والاسم)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.data.members;
    final visible = _visible;
    final height = MediaQuery.of(context).size.height;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * 0.85, maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Tw.slate100)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Tw.amber100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const FaIcon(
                      FontAwesomeIcons.userClock,
                      size: 15,
                      color: Tw.amber700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'غير المدققين في ورقة الوكيل',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: Tw.slate900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const FaIcon(
                      FontAwesomeIcons.xmark,
                      size: 18,
                      color: Tw.slate500,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 14, color: Tw.slate700),
                      children: [
                        const TextSpan(text: 'المتبقي: '),
                        TextSpan(
                          text: '${members.length}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Tw.amber700,
                            fontSize: 16,
                          ),
                        ),
                        TextSpan(
                          text:
                              ' من ${widget.data.agentTotal} رقم في ورقة الوكيل',
                        ),
                      ],
                    ),
                  ),
                  if (members.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ErpTextField(
                      controller: _filter,
                      hint: 'بحث برقم أو اسم',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ],
                ],
              ),
            ),
            Flexible(
              child:
                  members.isEmpty
                      ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'لا يوجد أرقام غير مدققة في ورقة الوكيل.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Tw.emerald700,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                      : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: visible.length,
                        separatorBuilder:
                            (_, _) =>
                                const Divider(height: 1, color: Tw.slate100),
                        itemBuilder: (_, i) {
                          final m = visible[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 34,
                                  child: Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Tw.slate400,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 4,
                                  child: SelectableText(
                                    m.id,
                                    textDirection: TextDirection.ltr,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: Tw.slate800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 6,
                                  child: Text(
                                    m.name.isEmpty ? '—' : m.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Tw.slate600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Tw.slate100)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_copied != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '✓ $_copied',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Tw.emerald700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (members.isNotEmpty)
                    Row(
                      children: [
                        Expanded(
                          child: ErpButton(
                            label: 'نسخ الكل',
                            icon: FontAwesomeIcons.copy,
                            height: 42,
                            fontSize: 12.5,
                            onPressed: () => _copy(idsOnly: false),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ErpButton(
                            label: 'نسخ الأرقام فقط',
                            icon: FontAwesomeIcons.hashtag,
                            kind: ErpButtonKind.outline,
                            height: 42,
                            fontSize: 12.5,
                            onPressed: () => _copy(idsOnly: true),
                          ),
                        ),
                      ],
                    ),
                  if (_query.trim().isNotEmpty && members.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'النسخ يشمل ${visible.length} نتيجة البحث فقط.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Tw.slate500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
