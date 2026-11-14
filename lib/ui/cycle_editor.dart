// Flutter's newer material_ui package is not available on older supported SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../application/local_audit_service.dart';
import '../data/import_service.dart';
import '../data/local_audit_database.dart';
import '../domain/audit_engine.dart';
import 'local_audit_file.dart';

class CycleEditor extends StatefulWidget {
  const CycleEditor({super.key, required this.db, this.cycle});
  final LocalAuditDatabase db;
  final CycleRecord? cycle;
  @override
  State<CycleEditor> createState() => _CycleEditorState();
}

class _Source {
  _Source(this.label, this.sheet, this.metadata);
  final String label;
  final ImportedSheet sheet;
  final Map<String, Object?> metadata;
}

class _CycleEditorState extends State<CycleEditor> {
  final name = TextEditingController();
  final managementColumn = TextEditingController(text: 'A');
  final agentColumn = TextEditingController(text: 'A');
  _Source? management, agent;
  bool? managementHeader, agentHeader;
  int step = 0;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final c = widget.cycle;
    if (c != null) {
      name.text = c.name;
      managementColumn.text =
          c.columnMappings['managementId'] as String? ?? 'A';
      agentColumn.text = c.columnMappings['agentId'] as String? ?? 'A';
      managementHeader = c.columnMappings['managementHeader'] as bool?;
      agentHeader = c.columnMappings['agentHeader'] as bool?;
      management = _restore(c.managementSource, c.snapshots['management']);
      agent = _restore(c.agentSource, c.snapshots['agent']);
    }
  }

  _Source? _restore(Map<String, Object?> metadata, Object? data) {
    final sheet = restoreAuditSheet(metadata, data);
    return sheet == null ? null : _Source(sheet.name, sheet, metadata);
  }

  @override
  void dispose() {
    name.dispose();
    managementColumn.dispose();
    agentColumn.dispose();
    super.dispose();
  }

  void _setSource(bool isManagement, _Source source) => setState(() {
    if (isManagement) {
      management = source;
      managementHeader = true;
    } else {
      agent = source;
      agentHeader = true;
    }
    error = null;
  });

  Future<void> _file(bool isManagement) async {
    try {
      final sheet = await pickAuditFile(context);
      if (!mounted || sheet == null) return;
      _setSource(
        isManagement,
        _Source(sheet.name, sheet, {
          'kind': 'file',
          'label': sheet.name,
          'nonTextCells': sheet.nonTextCells.map((p) => [p.$1, p.$2]).toList(),
        }),
      );
    } catch (e) {
      if (mounted) setState(() => error = 'تعذر استيراد الملف: ${_error(e)}');
    }
  }

  void _validate(
    _Source source,
    String column,
    bool? header, {
    bool allowEmpty = false,
  }) {
    if (header == null) {
      throw const FormatException('حدد وجود صف العناوين لكل مصدر.');
    }
    final index = columnIndex(column);
    source.sheet.validateIdentifierColumn(index, firstDataRow: header ? 1 : 0);
    final rows = source.sheet.rows.skip(header ? 1 : 0);
    if (!rows.any(
      (r) => r.length > index && normalizeMemberId(r[index]).isNotEmpty,
    )) {
      if (allowEmpty &&
          rows.every((r) => r.every((cell) => cell.trim().isEmpty))) {
        return;
      }
      throw const FormatException(
        'عمود رقم المستخدم لا يحتوي بيانات. اختر العمود الصحيح.',
      );
    }
  }

  Future<void> _save() async {
    try {
      if (management == null || agent == null) {
        throw const FormatException('اختر مصدري الإدارة والوكيل.');
      }
      _validate(management!, managementColumn.text, managementHeader);
      _validate(agent!, agentColumn.text, agentHeader, allowEmpty: true);
      if (name.text.trim().isEmpty) {
        throw const FormatException('أدخل اسم الدورة.');
      }
      setState(() {
        busy = true;
        error = null;
      });
      final existing = widget.cycle;
      await widget.db.saveCycle(
        CycleRecord(
          id: existing?.id ?? const Uuid().v4(),
          name: name.text.trim(),
          createdAt: existing?.createdAt ?? DateTime.now(),
          updatedAt: existing?.updatedAt,
          managementSource: management!.metadata,
          agentSource: agent!.metadata,
          columnMappings: {
            ...?existing?.columnMappings,
            'managementId': managementColumn.text.trim().toUpperCase(),
            'agentId': agentColumn.text.trim().toUpperCase(),
            'managementHeader': managementHeader,
            'agentHeader': agentHeader,
            'managementVerifiedTextColumn':
                managementColumn.text.trim().toUpperCase(),
            'agentVerifiedTextColumn': agentColumn.text.trim().toUpperCase(),
            'managementVerifiedTextHeader': managementHeader,
            'agentVerifiedTextHeader': agentHeader,
          },
          snapshots: {
            ...?existing?.snapshots,
            'management': management!.sheet.rows,
            'agent': agent!.sheet.rows,
          },
        ),
        localOnly: true,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = _error(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _source(bool isManagement) {
    final source = isManagement ? management : agent;
    final title = isManagement ? 'بيانات الإدارة' : 'بيانات الوكيل';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(source?.label ?? 'لم يتم اختيار مصدر بعد'),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : () => _file(isManagement),
              icon: const Icon(Icons.upload_file),
              label: const Text('ملف من الجهاز'),
            ),
            if (!isManagement)
              TextButton(
                onPressed:
                    busy
                        ? null
                        : () => _setSource(
                          false,
                          _Source(
                            'بدون بيانات وكيل',
                            const ImportedSheet('بدون بيانات وكيل', [], {}),
                            {
                              'kind': 'file',
                              'label': 'بدون بيانات وكيل',
                              'nonTextCells': [],
                            },
                          ),
                        ),
                child: const Text('بدون بيانات وكيل'),
              ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _mapping(bool isManagement) {
    final source = (isManagement ? management : agent)!;
    final controller = isManagement ? managementColumn : agentColumn;
    final header = isManagement ? managementHeader : agentHeader;
    final preview = _previewColumn(source, controller.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isManagement ? 'الإدارة' : 'الوكيل',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          '${source.label} · ${source.sheet.rows.length} صف',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<bool>(
          // ignore: deprecated_member_use
          value: header,
          decoration: const InputDecoration(labelText: 'هل الصف الأول عناوين؟'),
          items: const [
            DropdownMenuItem(
              value: true,
              child: Text('نعم، الصف الأول عناوين'),
            ),
            DropdownMenuItem(
              value: false,
              child: Text('لا، البيانات تبدأ من الصف الأول'),
            ),
          ],
          onChanged:
              (value) => setState(() {
                if (isManagement) {
                  managementHeader = value;
                } else {
                  agentHeader = value;
                }
              }),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          textDirection: TextDirection.ltr,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'عمود رقم المستخدم',
            helperText: 'مثال: A أو AA',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'معاينة عمود رقم المستخدم:',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        if (preview.isEmpty)
          Text(
            'أدخل حرف العمود لعرض العينة.',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (var index = 0; index < preview.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                preview[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style:
                    index == 0 && header == true
                        ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )
                        : Theme.of(context).textTheme.bodyLarge,
              ),
            ),
        const SizedBox(height: 24),
      ],
    );
  }

  List<String> _previewColumn(_Source source, String column) {
    try {
      final index = columnIndex(column);
      return source.sheet.rows
          .take(3)
          .map(
            (row) =>
                row.length > index && row[index].isNotEmpty ? row[index] : '—',
          )
          .toList();
    } on FormatException {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.cycle == null ? 'إنشاء دورة' : 'تعديل الدورة'),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'الخطوة ${step + 1} من 3',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 16),
          if (step == 0) ...[_source(true), _source(false)],
          if (step == 1 && management != null && agent != null) ...[
            const Text('تحقق من صف العناوين وعمود رقم المستخدم في كل مصدر.'),
            const SizedBox(height: 16),
            _mapping(true),
            const SizedBox(height: 12),
            _mapping(false),
            const SizedBox(height: 4),
            Text(
              'يجب أن تكون أرقام المستخدمين في Excel محفوظة كنص حتى لا تضيع الأصفار أو الدقة.',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          if (step == 2)
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'اسم الدورة'),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(shape: const StadiumBorder()),
              onPressed:
                  busy
                      ? null
                      : () {
                        if (step == 0) {
                          if (management == null || agent == null) {
                            setState(
                              () => error = 'اختر مصدري الإدارة والوكيل أولًا.',
                            );
                            return;
                          }
                          setState(() {
                            step++;
                            error = null;
                          });
                        } else if (step == 1) {
                          try {
                            _validate(
                              management!,
                              managementColumn.text,
                              managementHeader,
                            );
                            _validate(
                              agent!,
                              agentColumn.text,
                              agentHeader,
                              allowEmpty: true,
                            );
                            setState(() {
                              step++;
                              error = null;
                            });
                          } catch (e) {
                            setState(() => error = _error(e));
                          }
                        } else {
                          _save();
                        }
                      },
              child: Text(step == 2 ? 'حفظ الدورة' : 'التالي'),
            ),
          ),
          if (step > 0)
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed:
                    busy
                        ? null
                        : () => setState(() {
                          step--;
                          error = null;
                        }),
                child: const Text('السابق'),
              ),
            ),
        ],
      ),
    ),
  );
}

String _error(Object exception) => switch (exception) {
  FormatException(:final message) => message.toString(),
  StateError(:final message) => message,
  _ => 'تعذر حفظ بيانات الدورة.',
};
