// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../application/local_audit_service.dart';
import '../data/import_service.dart';
import '../data/local_audit_database.dart';
import '../domain/local_audit_result.dart';
import 'local_audit_file.dart';

class LocalAuditPage extends StatefulWidget {
  const LocalAuditPage({
    super.key,
    required this.db,
    required this.cycleId,
    this.memberId,
  });

  final LocalAuditDatabase db;
  final String cycleId;
  final String? memberId;

  @override
  State<LocalAuditPage> createState() => _LocalAuditPageState();
}

class _LocalAuditPageState extends State<LocalAuditPage> {
  final infoId = TextEditingController(text: 'C');
  final titleColumn = TextEditingController(text: 'D');
  final target = TextEditingController();
  final agentColor = TextEditingController(text: defaultAgentColor);
  final managementColor = TextEditingController(text: defaultManagementColor);
  CycleRecord? cycle;
  ImportedSheet? info;
  bool infoHeader = true;
  bool busy = true;
  String? error;
  String? outcome;
  LocalAuditReview? review;
  LocalAuditResult? lastResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final saved = await widget.db.getCycle(widget.cycleId);
      if (saved == null) throw StateError('الدورة غير موجودة.');
      final member = widget.memberId;
      final results =
          member == null
              ? const <LocalAuditResult>[]
              : await widget.db.listLocalAudit(saved.id, memberId: member);
      if (!mounted) return;
      final mappings = saved.columnMappings;
      final metadata = saved.snapshots['userInfoSource'];
      info =
          metadata is Map
              ? restoreAuditSheet(
                Map<String, Object?>.from(metadata),
                saved.snapshots['userInfo'],
              )
              : null;
      infoId.text = mappings['userInfoId'] as String? ?? 'C';
      titleColumn.text = mappings['userInfoTitle'] as String? ?? 'D';
      infoHeader = mappings['userInfoHeader'] as bool? ?? true;
      agentColor.text =
          mappings['localAgentColor'] as String? ?? defaultAgentColor;
      managementColor.text =
          mappings['localManagementColor'] as String? ?? defaultManagementColor;
      lastResult = results.firstOrNull;
      target.text =
          lastResult?.individual == true ? lastResult?.target ?? '' : '';
      setState(() => cycle = saved);
    } catch (e) {
      if (mounted) setState(() => error = _message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    infoId.dispose();
    titleColumn.dispose();
    target.dispose();
    agentColor.dispose();
    managementColor.dispose();
    super.dispose();
  }

  void _invalidate() {
    review = null;
    error = null;
    outcome = null;
  }

  Future<void> _pick() async {
    setState(() => busy = true);
    try {
      final sheet = await pickAuditFile(context);
      if (!mounted || sheet == null) return;
      setState(() {
        info = sheet;
        _invalidate();
      });
    } catch (e) {
      if (mounted) setState(() => error = _message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _preview() {
    try {
      final candidate = LocalAuditService(widget.db).review(
        cycle: cycle!,
        info: info,
        infoId: infoId.text,
        titleColumn: titleColumn.text,
        infoHeader: infoHeader,
        memberId: widget.memberId,
        manualTarget: target.text,
        agentColor: agentColor.text.trim(),
        managementColor: managementColor.text.trim(),
      );
      setState(() {
        _invalidate();
        review = candidate;
        if (candidate.preview.members.isEmpty) {
          error = 'لا توجد نتائج. للتدقيق الفردي يمكنك إدخال اسم وجهة يدويًا.';
        }
      });
    } catch (e) {
      setState(() {
        _invalidate();
        error = _message(e);
      });
    }
  }

  Future<void> _apply() async {
    final candidate = review!;
    setState(() => busy = true);
    try {
      final count = await LocalAuditService(widget.db).apply(candidate);
      if (!mounted) return;
      final saved = await widget.db.getCycle(widget.cycleId);
      final member = widget.memberId;
      final previous =
          member == null
              ? null
              : (await widget.db.listLocalAudit(
                widget.cycleId,
                memberId: member,
              )).firstOrNull;
      if (!mounted) return;
      setState(() {
        lastResult = previous;
        cycle = saved;
        review = null;
        error = null;
        outcome =
            count == 0
                ? 'النتائج محفوظة مسبقًا.'
                : 'حُفظت نتائج $count مستخدم على الجهاز.';
      });
    } catch (e) {
      if (mounted) setState(() => error = _message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _message(Object exception) => switch (exception) {
    FormatException(:final message) => message.toString(),
    StateError(:final message) => message,
    _ => 'تعذر إكمال العملية على الجهاز.',
  };

  Widget _field(
    TextEditingController controller,
    String label, {
    bool ltr = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      enabled: !busy,
      textDirection: ltr ? TextDirection.ltr : null,
      onChanged: (_) => setState(_invalidate),
      decoration: InputDecoration(labelText: label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final saved = cycle;
    final current = review;
    final members = current?.preview.members ?? [];
    final content = <Widget>[
      if (saved != null) ...[
        Text(saved.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (saved.auditClosed)
          const Text('الدورة مغلقة. أعد فتحها لتدقيق مستخدمين.'),
        if (lastResult case final previous?)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              previous.audited
                  ? 'آخر حالة محفوظة: مدقق'
                  : 'آخر حالة محفوظة: غير مدقق',
            ),
            subtitle: Text(previous.classification.label),
          ),
        if (!saved.auditClosed) ...[
          OutlinedButton.icon(
            onPressed: busy ? null : _pick,
            icon: const Icon(Icons.upload_file),
            label: const Text('استيراد معلومات المستخدمين'),
          ),
          if (info != null) ...[
            Text('${info!.name} · ${info!.rows.length} صف'),
            const SizedBox(height: 12),
            _field(infoId, 'عمود رقم المستخدم', ltr: true),
            _field(titleColumn, 'عمود اسم الوجهة', ltr: true),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: infoHeader,
              title: const Text('الصف الأول عناوين'),
              onChanged:
                  busy
                      ? null
                      : (value) => setState(() {
                        infoHeader = value;
                        _invalidate();
                      }),
            ),
          ],
          if (widget.memberId != null) _field(target, 'اسم الوجهة يدويًا'),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('ألوان التدقيق'),
            children: [
              _field(agentColor, 'لون سحب الوكيل', ltr: true),
              _field(managementColor, 'لون سحب الإدارة', ltr: true),
            ],
          ),
          FilledButton(
            onPressed: busy ? null : _preview,
            child: const Text('عرض المعاينة'),
          ),
        ],
      ],
      if (busy) const LinearProgressIndicator(),
      if (outcome != null) Text(outcome!),
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (current != null) ...[
        const Divider(),
        for (final conflict in current.preview.conflicts)
          Text(conflict.message),
        Text(
          'النتائج: ${members.length} · قابلة للحفظ: ${current.results.length}',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: FilledButton.icon(
            onPressed:
                busy || saved?.auditClosed != false || current.results.isEmpty
                    ? null
                    : _apply,
            icon: const Icon(Icons.check),
            label: const Text('اعتماد النتائج وحفظها'),
          ),
        ),
      ],
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.memberId == null
              ? 'التدقيق الجماعي'
              : 'تدقيق المستخدم ${widget.memberId}',
        ),
      ),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: content.length + members.length,
          itemBuilder: (context, index) {
            if (index < content.length) return content[index];
            final member = members[index - content.length];
            final notes = [
              if (member.targetTitle != null) 'الوجهة: ${member.targetTitle}',
              if (member.diagnostic != null) member.diagnostic!,
              ...member.conflicts
                  .where((c) => !current!.preview.conflicts.contains(c))
                  .map((c) => c.message),
            ];
            return ListTile(
              title: Text(
                '${member.memberId} · ${member.classification.label}',
              ),
              subtitle: notes.isEmpty ? null : Text(notes.join('\n')),
            );
          },
        ),
      ),
    );
  }
}
