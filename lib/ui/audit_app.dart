// Flutter's newer material_ui package is not available on older supported SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../application/local_audit_service.dart';
import '../data/local_audit_database.dart';
import '../data/local_audit_export.dart';
import '../domain/audit_engine.dart';
import '../domain/local_audit_result.dart';
import 'local_audit_page.dart';
import 'local_audit_results_page.dart';
import 'cycle_editor.dart';

class AuditHome extends StatefulWidget {
  const AuditHome({super.key});
  @override
  State<AuditHome> createState() => _AuditHomeState();
}

class _AuditHomeState extends State<AuditHome> {
  LocalAuditDatabase? db;
  List<CycleRecord> cycles = [];
  String? currentId;
  int page = 0;
  String? loadError;
  bool exporting = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final database = await LocalAuditDatabase.open();
      if (!mounted) {
        await database.close();
        return;
      }
      db = database;
      await _refresh();
    } catch (_) {
      if (mounted) {
        setState(() => loadError = 'تعذر فتح البيانات المحفوظة على الجهاز.');
      }
    }
  }

  Future<void> _refresh() async {
    final data = await db!.listCycles();
    if (!mounted) return;
    setState(() {
      cycles = data;
      if (currentId != null && !cycles.any((c) => c.id == currentId)) {
        currentId = null;
      }
      currentId ??= cycles.isEmpty ? null : cycles.first.id;
    });
  }

  Future<void> _edit([CycleRecord? cycle]) async {
    final saved = cycle == null ? null : await db!.getCycle(cycle.id);
    if (cycle != null && saved == null) return;
    if (saved?.auditClosed == true) {
      _message('أعد فتح الدورة قبل تعديلها.');
      return;
    }
    if (!mounted) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CycleEditor(db: db!, cycle: saved)),
    );
    if (changed == true) await _refresh();
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _export(CycleRecord cycle) async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      final history = await db!.listLocalAudit(cycle.id, history: true);
      final bytes = LocalAuditExport.encode(cycle, history);
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ نتائج التدقيق',
        fileName:
            'audit-${cycle.createdAt.toLocal().toIso8601String().split('T').first}.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        bytes: bytes,
      );
      if (saved != null) _message('تم حفظ ملف Excel.');
    } catch (_) {
      _message('تعذر تصدير نتائج الدورة.');
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> _openPreview(CycleRecord cycle) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalAuditPage(db: db!, cycleId: cycle.id),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _openResults(CycleRecord cycle) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LocalAuditResultsPage(db: db!, cycle: cycle),
    ),
  );

  Future<void> _changeClosed(CycleRecord cycle) async {
    try {
      if (cycle.auditClosed) {
        await db!.reopenCycle(cycle.id);
      } else {
        await db!.closeCycle(cycle.id, localOnly: true);
      }
      await _refresh();
      _message(cycle.auditClosed ? 'أُعيد فتح الدورة.' : 'أُغلقت الدورة.');
    } catch (_) {
      _message('تعذر تغيير حالة الدورة.');
    }
  }

  Future<void> _delete(CycleRecord cycle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('حذف الدورة من الجهاز؟'),
            content: const Text('ستُحذف بيانات الدورة وسجلها من هذا الجهاز.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حذف'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await db!.deleteCycle(cycle.id, localOnly: true);
      await _refresh();
    } catch (_) {
      _message('تعذر حذف الدورة.');
    }
  }

  @override
  void dispose() {
    db?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final database = db;
    if (database == null) {
      return Scaffold(
        body: Center(
          child:
              loadError == null
                  ? const CircularProgressIndicator()
                  : Text(loadError!),
        ),
      );
    }
    final selected = cycles.where((c) => c.id == currentId).firstOrNull;
    final views = <Widget>[
      _CyclesPage(
        cycles: cycles,
        onCreate: () => _edit(),
        onEdit: _edit,
        onDelete: _delete,
        onToggle: _changeClosed,
        onExport: _export,
        onSelect:
            (c) => setState(() {
              currentId = c.id;
              page = 1;
            }),
      ),
      _AuditPage(
        cycles: cycles,
        selected: selected,
        onExport: exporting ? null : _export,
        onSelect: (id) => setState(() => currentId = id),
        onPreview: _openPreview,
        onResults: _openResults,
      ),
      _SearchPage(cycles: cycles, db: database, onChanged: _refresh),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(['الدورات', 'التدقيق', 'البحث'][page])),
      body: SafeArea(child: views[page]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: page,
        onDestinationSelected: (v) => setState(() => page = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'الدورات',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check),
            label: 'التدقيق',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: 'البحث'),
        ],
      ),
    );
  }
}

class _CyclesPage extends StatelessWidget {
  const _CyclesPage({
    required this.cycles,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onSelect,
    required this.onExport,
  });
  final List<CycleRecord> cycles;
  final VoidCallback onCreate;
  final ValueChanged<CycleRecord> onEdit,
      onDelete,
      onToggle,
      onSelect,
      onExport;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      FilledButton.icon(
        onPressed: onCreate,
        icon: const Icon(Icons.add),
        label: const Text('إنشاء دورة'),
      ),
      const SizedBox(height: 16),
      if (cycles.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: Text('لا توجد دورات محفوظة بعد.')),
        ),
      for (final cycle in cycles)
        Card(
          child: ListTile(
            onTap: () => onSelect(cycle),
            title: Text(cycle.name),
            subtitle: Text(
              '${cycle.createdAt.toLocal().toIso8601String().split('T').first}'
              ' · ${cycle.auditClosed ? 'مغلقة' : 'مفتوحة'}',
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (choice) {
                switch (choice) {
                  case 'edit':
                    onEdit(cycle);
                  case 'toggle':
                    onToggle(cycle);
                  case 'export':
                    onExport(cycle);
                  case 'delete':
                    onDelete(cycle);
                }
              },
              itemBuilder:
                  (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('تعديل الدورة'),
                    ),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(
                        cycle.auditClosed ? 'إعادة الفتح' : 'إغلاق الدورة',
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'export',
                      child: Text('تصدير Excel'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('حذف من الجهاز'),
                    ),
                  ],
            ),
          ),
        ),
    ],
  );
}

class _AuditPage extends StatelessWidget {
  const _AuditPage({
    required this.cycles,
    required this.selected,
    required this.onExport,
    required this.onSelect,
    required this.onPreview,
    required this.onResults,
  });
  final List<CycleRecord> cycles;
  final CycleRecord? selected;
  final ValueChanged<CycleRecord>? onExport;
  final ValueChanged<String?> onSelect;
  final ValueChanged<CycleRecord> onPreview, onResults;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      if (cycles.isEmpty)
        const Text('أنشئ دورة أولًا من قسم الدورات.')
      else ...[
        DropdownButtonFormField<String>(
          // Keep compatibility with Flutter releases before initialValue.
          // ignore: deprecated_member_use
          value: selected?.id,
          decoration: const InputDecoration(labelText: 'الدورة'),
          items:
              cycles
                  .map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                  )
                  .toList(),
          onChanged: onSelect,
        ),
        const SizedBox(height: 20),
        if (selected case final cycle?) ...[
          Text(cycle.auditClosed ? 'الدورة مغلقة' : 'الدورة مفتوحة'),
          FilledButton(
            onPressed: cycle.auditClosed ? null : () => onPreview(cycle),
            child: const Text('إعداد التدقيق الجماعي'),
          ),
          OutlinedButton.icon(
            onPressed: () => onResults(cycle),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('عرض النتائج والسجل'),
          ),
          OutlinedButton.icon(
            onPressed: onExport == null ? null : () => onExport!(cycle),
            icon: const Icon(Icons.download),
            label: const Text('تصدير النتائج إلى Excel'),
          ),
        ],
      ],
    ],
  );
}

class _SearchResult {
  const _SearchResult(this.cycle, this.member, this.saved);
  final CycleRecord cycle;
  final MemberPreview member;
  final LocalAuditResult? saved;
}

class _SearchPage extends StatefulWidget {
  const _SearchPage({
    required this.cycles,
    required this.db,
    required this.onChanged,
  });
  final List<CycleRecord> cycles;
  final LocalAuditDatabase db;
  final Future<void> Function() onChanged;
  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  final controller = TextEditingController();
  String? cycleId;
  List<_SearchResult>? results;
  String? error;
  bool busy = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> search() async {
    if (busy) return;
    final id = normalizeMemberId(controller.text);
    if (id.isEmpty) {
      setState(() => error = 'أدخل رقم المستخدم أولًا.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      results = null;
    });
    final found = <_SearchResult>[];
    try {
      for (final cycle in widget.cycles.where(
        (c) => cycleId == null || c.id == cycleId,
      )) {
        final management = cycleRows(cycle.snapshots['management']);
        final agent = cycleRows(cycle.snapshots['agent']);
        final result = const AuditEngine().preview(
          AuditInput(
            management: AuditTable(
              rows: management,
              idColumn: cycle.columnMappings['managementId'] as String? ?? 'A',
              hasHeader:
                  cycle.columnMappings['managementHeader'] as bool? ?? true,
              identifiersAreTextVerified:
                  cycle.columnMappings['managementVerifiedTextColumn'] !=
                      null &&
                  cycle.columnMappings['managementVerifiedTextColumn'] ==
                      cycle.columnMappings['managementId'] &&
                  cycle.columnMappings['managementVerifiedTextHeader'] ==
                      cycle.columnMappings['managementHeader'],
            ),
            agent: AuditTable(
              rows: agent,
              idColumn: cycle.columnMappings['agentId'] as String? ?? 'A',
              hasHeader: cycle.columnMappings['agentHeader'] as bool? ?? true,
              identifiersAreTextVerified:
                  cycle.columnMappings['agentVerifiedTextColumn'] != null &&
                  cycle.columnMappings['agentVerifiedTextColumn'] ==
                      cycle.columnMappings['agentId'] &&
                  cycle.columnMappings['agentVerifiedTextHeader'] ==
                      cycle.columnMappings['agentHeader'],
            ),
            userInfo: AuditTable(
              rows: [
                [id, 'بحث محلي'],
              ],
              idColumn: 'A',
              hasHeader: false,
              identifiersAreTextVerified: true,
            ),
            titleColumn: 'B',
            targetSpreadsheetId: '',
            localDestination: true,
            agentColor: '#6252bd',
            managementColor: '#278164',
          ),
        );
        final member = result.members.single;
        final saved =
            (await widget.db.listLocalAudit(
              cycle.id,
              memberId: id,
            )).firstOrNull;
        if (saved != null ||
            member.managementRow != null ||
            member.agentRows.isNotEmpty ||
            member.conflicts.any(
              (c) => c.code == AuditConflictCode.duplicateManagement,
            )) {
          found.add(_SearchResult(cycle, member, saved));
        }
      }
      if (mounted) {
        setState(() {
          results = found;
          busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'تعذر البحث في البيانات المحفوظة. تحقق من إعدادات الدورة.';
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      DropdownButtonFormField<String>(
        // ignore: deprecated_member_use
        value: widget.cycles.any((c) => c.id == cycleId) ? cycleId : null,
        decoration: const InputDecoration(labelText: 'نطاق البحث'),
        items: [
          const DropdownMenuItem<String>(
            value: null,
            child: Text('كل الدورات'),
          ),
          ...widget.cycles.map(
            (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
          ),
        ],
        onChanged: (v) => setState(() => cycleId = v),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: controller,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: 'رقم المستخدم',
          suffixIcon: IconButton(
            tooltip: 'لصق',
            icon: const Icon(Icons.content_paste),
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data?.text != null) controller.text = data!.text!;
            },
          ),
        ),
        onSubmitted: (_) => search(),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: busy ? null : search,
        icon: const Icon(Icons.search),
        label: const Text('بحث'),
      ),
      if (busy)
        const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (error != null)
        Padding(padding: const EdgeInsets.only(top: 16), child: Text(error!)),
      if (results != null && results!.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 24),
          child: Text('لم يُعثر على المستخدم في الدورات المحددة.'),
        ),
      if (results != null)
        for (final result in results!)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.cycle.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(result.member.classification.label),
                  Text(
                    'الإدارة: ${result.member.managementRow != null ? 'موجود' : 'غير مؤكد أو غير موجود'} · الوكيل: ${result.member.agentRows.length} صف',
                  ),
                  if (result.member.diagnostic != null)
                    Text(result.member.diagnostic!),
                  for (final conflict in result.member.conflicts.where(
                    (c) => c.code == AuditConflictCode.duplicateManagement,
                  ))
                    Text(conflict.message),
                  Text(
                    result.saved?.audited == true
                        ? 'آخر حالة محفوظة: مدقق'
                        : 'غير مدقق',
                  ),
                  if (result.saved?.target case final destination?)
                    Text('الوجهة: $destination'),
                  OutlinedButton.icon(
                    onPressed:
                        result.cycle.auditClosed
                            ? null
                            : () async {
                              await Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  builder:
                                      (_) => LocalAuditPage(
                                        db: widget.db,
                                        cycleId: result.cycle.id,
                                        memberId: result.member.memberId,
                                      ),
                                ),
                              );
                              if (mounted) await widget.onChanged();
                              if (mounted) await search();
                            },
                    icon: const Icon(Icons.person_search_outlined),
                    label: const Text('مراجعة أو إعادة تدقيق هذا المستخدم'),
                  ),
                ],
              ),
            ),
          ),
    ],
  );
}
