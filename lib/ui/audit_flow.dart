import 'dart:convert';

// Flutter's newer material_ui package is not available on older supported SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../application/audit_plan_review_service.dart';
import '../application/audit_planner.dart';
import '../data/local_audit_database.dart';
import '../domain/audit_engine.dart';
import '../google/google_sheets_gateway.dart';
import '../sync/audit_sync_engine.dart';

/// Configures and previews an audit using persisted snapshots. Google writes
/// remain behind the sync engine's explicit safety gate.
class AuditFlowPage extends StatefulWidget {
  const AuditFlowPage({
    super.key,
    required this.db,
    required this.session,
    required this.cycle,
    this.memberId,
    this.initialManualTarget = '',
  });
  final LocalAuditDatabase db;
  final GoogleSession session;
  final CycleRecord cycle;
  final String? memberId;
  final String initialManualTarget;

  @override
  State<AuditFlowPage> createState() => _AuditFlowPageState();
}

class _AuditFlowPageState extends State<AuditFlowPage> {
  final infoId = TextEditingController(text: 'A');
  final infoTitle = TextEditingController(text: 'B');
  final infoStatus = TextEditingController();
  final manualTarget = TextEditingController();
  late CycleRecord cycle;
  List<List<String>>? infoRows;
  Map<String, Object?>? infoSource;
  Map<String, Object?>? target;
  bool? infoHeader;
  bool statusConfirmed = false;
  bool busy = false;
  String? error;
  AuditPreview? preview;
  AuditPlanPreview? googleReview;
  bool planSaved = false;
  List<OperationRecord> savedOperations = [];
  List<Map<String, Object?>> operationEvents = [];
  bool get hasIncompleteOperations => savedOperations.any(
    (operation) => !isOperationComplete(operation.status),
  );
  bool get canCancelUnstartedPlan =>
      hasIncompleteOperations &&
      savedOperations.every(
        (operation) =>
            operation.attempts == 0 &&
            {
              OperationStatus.planned,
              OperationStatus.pending,
              OperationStatus.failed,
              OperationStatus.verified,
            }.contains(operation.status),
      );

  GoogleSheetsGateway get gateway => GoogleSheetsGateway(widget.session);

  @override
  void initState() {
    super.initState();
    cycle = widget.cycle;
    manualTarget.text = widget.initialManualTarget;
    final mappings = cycle.columnMappings;
    infoId.text = mappings['userInfoId'] as String? ?? 'A';
    infoTitle.text = mappings['userInfoTitle'] as String? ?? 'B';
    infoStatus.text = mappings['userInfoStatus'] as String? ?? '';
    infoHeader = mappings['userInfoHeader'] as bool?;
    statusConfirmed = mappings['userInfoStatusConfirmed'] == true;
    final rows = cycle.snapshots['userInfo'];
    if (rows is List) infoRows = _rows(rows);
    final source = cycle.snapshots['userInfoSource'];
    if (source is Map) infoSource = Map<String, Object?>.from(source);
    final savedTarget = cycle.snapshots['auditTarget'];
    if (savedTarget is Map) {
      target = Map<String, Object?>.from(savedTarget);
    }
    _loadSavedOperations();
  }

  @override
  void dispose() {
    infoId.dispose();
    infoTitle.dispose();
    infoStatus.dispose();
    manualTarget.dispose();
    super.dispose();
  }

  static List<List<String>> _rows(List rows) =>
      rows
          .whereType<List>()
          .map((row) => row.map((value) => value?.toString() ?? '').toList())
          .toList();

  Future<T?> _select<T>(String title, List<T> items, String Function(T) label) {
    var query = '';
    return showDialog<T>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, updateDialog) {
              final visible =
                  items
                      .where(
                        (item) => label(item).toLowerCase().contains(query),
                      )
                      .toList();
              return SimpleDialog(
                title: Text(title),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'بحث بالاسم',
                      ),
                      onChanged:
                          (value) => updateDialog(
                            () => query = value.trim().toLowerCase(),
                          ),
                    ),
                  ),
                  if (visible.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('لا توجد نتائج مطابقة.'),
                    ),
                  if (visible.isNotEmpty)
                    SizedBox(
                      width: double.maxFinite,
                      height: 340,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: visible.length,
                        itemBuilder:
                            (context, index) => SimpleDialogOption(
                              onPressed:
                                  () => Navigator.pop(context, visible[index]),
                              child: Text(label(visible[index])),
                            ),
                      ),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إلغاء'),
                  ),
                ],
              );
            },
          ),
    );
  }

  Future<String?> _account() async {
    final account = widget.session.accountId ?? await widget.session.connect();
    return account;
  }

  String _message(Object e) {
    if (e is GoogleFailure) return e.message;
    if (e is FormatException) return e.message;
    if (e is StateError) {
      final message = e.message.toString();
      return RegExp(r'[\u0600-\u06ff]').hasMatch(message)
          ? message
          : 'تعذر حفظ الإعدادات. تحقق من أن الدورة مفتوحة ولا توجد عمليات غير مكتملة.';
    }
    return 'تعذر إكمال العملية. تحقق من الاتصال والبيانات وحاول مجددًا.';
  }

  Future<void> _chooseInfo() async {
    try {
      final account = await _account();
      if (account == null || !mounted) return;
      setState(() {
        busy = true;
        error = null;
      });
      final spreadsheets = await gateway.listSpreadsheets(account);
      if (!mounted) return;
      setState(() => busy = false);
      final book = await _select<SpreadsheetRef>(
        'اختر جدول معلومات المستخدمين',
        spreadsheets,
        (item) => item.name,
      );
      if (book == null || !mounted) return;
      setState(() => busy = true);
      final sheets = await gateway.listSheets(account, book.id);
      if (!mounted) return;
      setState(() => busy = false);
      final sheet = await _select<SheetRef>(
        'اختر ورقة معلومات المستخدمين',
        sheets,
        (item) => item.title,
      );
      if (sheet == null || !mounted) return;
      setState(() => busy = true);
      final data = await gateway.readSheet(account, book.id, sheet.id);
      if (!mounted) return;
      final rows = <List<String>>[];
      final nonText = <List<int>>[];
      for (final row in data.rows) {
        while (rows.length <= row.index) {
          rows.add([]);
        }
        final cells = <String>[];
        for (final cell in row.cells) {
          if (cell.entered.isNotEmpty &&
              !cell.entered.containsKey('stringValue')) {
            nonText.add([row.index, cells.length]);
          }
          cells.add(cell.entered['stringValue']?.toString() ?? cell.formatted);
        }
        rows[row.index] = cells;
      }
      setState(() {
        infoRows = rows;
        infoSource = {
          'kind': 'google',
          'label': '${book.name} · ${sheet.title}',
          'accountId': account,
          'spreadsheetId': book.id,
          'sheetId': sheet.id,
          'sheetTitle': sheet.title,
          'nonTextCells': nonText,
          'googleReviewProof': AuditPlanReviewService.captureProof(data),
        };
        infoHeader = null;
        preview = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = _message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _chooseTarget() async {
    try {
      final account = await _account();
      if (account == null || !mounted) return;
      setState(() {
        busy = true;
        error = null;
      });
      final spreadsheets = await gateway.listSpreadsheets(account);
      if (!mounted) return;
      setState(() => busy = false);
      final book = await _select<SpreadsheetRef>(
        'اختر جدول وجهة التدقيق',
        spreadsheets,
        (item) => item.name,
      );
      if (book == null || !mounted) return;
      setState(() {
        target = {'id': book.id, 'name': book.name, 'accountId': account};
        preview = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = _message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool _isVerified(Map<String, Object?>? source, String column, bool header) {
    if (source == null || source['nonTextCells'] is! List) return false;
    final idx = columnIndex(column);
    for (final position in source['nonTextCells'] as List) {
      if (position is! List ||
          position.length != 2 ||
          position[0] is! int ||
          position[1] is! int) {
        return false;
      }
      if ((position[0] as int) >= (header ? 1 : 0) && position[1] == idx) {
        return false;
      }
    }
    return true;
  }

  AuditTable _sourceTable(
    Map<String, Object?> source,
    Object? snapshot,
    String column,
    bool header,
  ) {
    if (snapshot is! List) {
      throw const FormatException(
        'لقطة مصدر الدورة غير متاحة. أعد استيراد بيانات الدورة.',
      );
    }
    return AuditTable(
      rows: _rows(snapshot),
      idColumn: column,
      hasHeader: header,
      spreadsheetId: source['spreadsheetId'] as String?,
      sheetTitle: source['sheetTitle'] as String?,
      sourceId: source['label'] as String?,
      identifiersAreTextVerified: _isVerified(source, column, header),
    );
  }

  Map<String, String> _manualTargets() {
    final id = widget.memberId;
    final title = manualTarget.text.trim();
    if (id == null || title.isEmpty) return const {};
    return {normalizeMemberId(id): title};
  }

  Future<void> _preview() async {
    try {
      if (infoRows == null || infoSource == null) {
        throw const FormatException('اختر معلومات المستخدمين أولًا.');
      }
      if (infoHeader == null) {
        throw const FormatException('حدد ما إذا كان الصف الأول عناوين.');
      }
      final mappings = cycle.columnMappings;
      final mgmtColumn = mappings['managementId'] as String?;
      final agentColumn = mappings['agentId'] as String?;
      final mgmtHeader = mappings['managementHeader'] as bool?;
      final agentHeader = mappings['agentHeader'] as bool?;
      if (mgmtColumn == null ||
          agentColumn == null ||
          mgmtHeader == null ||
          agentHeader == null) {
        throw const FormatException('إعدادات مصادر الدورة غير مكتملة.');
      }
      // Validate column letters before deciding if the status column is safe.
      columnIndex(infoId.text);
      columnIndex(infoTitle.text);
      final status = infoStatus.text.trim();
      final statusSafe =
          status.isEmpty ||
          (statusConfirmed && _isVerified(infoSource, status, infoHeader!));
      final input = AuditInput(
        management: _sourceTable(
          cycle.managementSource,
          cycle.snapshots['management'],
          mgmtColumn,
          mgmtHeader,
        ),
        agent: _sourceTable(
          cycle.agentSource,
          cycle.snapshots['agent'],
          agentColumn,
          agentHeader,
        ),
        userInfo: _sourceTable(infoSource!, infoRows, infoId.text, infoHeader!),
        titleColumn: infoTitle.text,
        targetSpreadsheetId: target?['id'] as String? ?? '',
        agentColor: '#6252bd',
        managementColor: '#278164',
        onlyMemberIds:
            widget.memberId == null
                ? null
                : {normalizeMemberId(widget.memberId)},
        manualTargets: _manualTargets(),
        statusColumn: status.isEmpty ? null : status,
        statusColumnIsVerifiedNonFinancial: statusSafe,
      );
      final result = const AuditEngine().preview(input);
      if (!cycle.auditClosed) {
        final existingOperations = await widget.db.listOperations(cycle.id);
        final hasPendingPlan = existingOperations.any(
          (operation) => !isOperationComplete(operation.status),
        );
        // Persist snapshots and settings before showing the preview so it can
        // be repeated offline after app restart. No operation is created here.
        final updated = CycleRecord(
          id: cycle.id,
          name: cycle.name,
          createdAt: cycle.createdAt,
          managementSource: cycle.managementSource,
          agentSource: cycle.agentSource,
          columnMappings: {
            ...cycle.columnMappings,
            'userInfoId': infoId.text.trim().toUpperCase(),
            'userInfoTitle': infoTitle.text.trim().toUpperCase(),
            'userInfoStatus': status.toUpperCase(),
            'userInfoHeader': infoHeader,
            'userInfoStatusConfirmed': statusConfirmed,
          },
          snapshots: {
            ...cycle.snapshots,
            'userInfo': infoRows,
            'userInfoSource': infoSource,
            'auditTarget': target,
          },
        );
        if (hasPendingPlan) {
          final unchanged =
              cycle.name == updated.name &&
              jsonEncode(cycle.managementSource) ==
                  jsonEncode(updated.managementSource) &&
              jsonEncode(cycle.agentSource) ==
                  jsonEncode(updated.agentSource) &&
              jsonEncode(cycle.columnMappings) ==
                  jsonEncode(updated.columnMappings) &&
              jsonEncode(cycle.snapshots) == jsonEncode(updated.snapshots);
          if (!unchanged) {
            throw StateError(
              'استأنف الخطة المحفوظة قبل تغيير مصادر الدورة أو أعمدتها.',
            );
          }
        } else {
          await widget.db.saveCycle(updated);
          cycle = updated;
        }
      }
      if (mounted) {
        setState(() {
          preview = result;
          googleReview = null;
          planSaved = false;
          savedOperations = [];
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          preview = null;
          error = _message(e);
        });
      }
    }
  }

  /// Reads current Google sources and displays a plan without saving or
  /// executing any of its operations.
  Future<void> _reviewGoogle() async {
    final visiblePreview = preview;
    final account = widget.session.accountId;
    if (visiblePreview == null || account == null) {
      setState(() => error = 'اربط حساب Google واعرض المعاينة أولًا.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      googleReview = null;
    });
    try {
      final result = await AuditPlanReviewService(widget.db, gateway).prepare(
        cycleId: cycle.id,
        accountId: account,
        agentColor: '#6252bd',
        managementColor: '#278164',
        onlyMemberIds:
            widget.memberId == null
                ? null
                : {normalizeMemberId(widget.memberId)},
        manualTargets: _manualTargets(),
      );
      if (mounted && identical(preview, visiblePreview)) {
        setState(() {
          googleReview = result;
          planSaved = false;
        });
      }
    } catch (e) {
      if (mounted && identical(preview, visiblePreview)) {
        setState(() => error = _message(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _loadSavedOperations() async {
    final operations = await widget.db.listOperations(cycle.id);
    final events = await widget.db.listOperationEvents(cycle.id);
    if (mounted) {
      setState(() {
        savedOperations = operations;
        operationEvents = events;
      });
    }
  }

  Future<void> _savePlan() async {
    final plan = googleReview;
    if (plan == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await AuditPlanner(widget.db).saveApproved(plan);
      if (mounted) setState(() => planSaved = true);
      await _loadSavedOperations();
    } catch (e) {
      if (mounted) setState(() => error = _message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _resumePlan() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final operations = await widget.db.listOperations(cycle.id);
      if (operations.isEmpty) {
        throw StateError('لا توجد خطة محفوظة لاستئنافها.');
      }
      for (final operation in operations) {
        if (isOperationComplete(operation.status)) continue;
        final result = await AuditSyncEngine(
          widget.db,
          gateway,
        ).execute(operation.id);
        if (mounted) await _loadSavedOperations();
        if (result.status != OperationStatus.verified) break;
      }
      if (mounted) await _loadSavedOperations();
    } catch (e) {
      if (mounted) setState(() => error = _message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _cancelUnstartedPlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('إلغاء خطة لم تبدأ؟'),
            content: const Text(
              'سيُسجَّل إلغاء الخطة محليًا. لن يُسمح به إلا إذا لم تبدأ أي خطوة كتابة ولم توجد نتيجة غير مؤكدة؛ لن يتغير شيء على Google.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('العودة'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('إلغاء الخطة المحلية'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.db.cancelUnstartedPlan(cycle.id);
      await _loadSavedOperations();
      if (mounted) {
        setState(() {
          googleReview = null;
          planSaved = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = _message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _operationStatus(OperationStatus status) => switch (status) {
    OperationStatus.planned => 'مخطط محليًا',
    OperationStatus.pending => 'بانتظار الاستئناف',
    OperationStatus.executing => 'بدأت؛ النتيجة غير مؤكدة',
    OperationStatus.verificationRequired => 'تحتاج تحققًا قبل الإعادة',
    OperationStatus.verified => 'متحقق من النتيجة',
    OperationStatus.conflict => 'تعارض — مراجعة مطلوبة',
    OperationStatus.failed => 'فشل قبل إثبات الأثر',
    OperationStatus.cancelled => 'أُلغيت محليًا قبل الكتابة',
  };

  String _classification(AuditClassification value) => switch (value) {
    AuditClassification.agent => 'سحب وكيل',
    AuditClassification.agentMultiple => 'سحب وكيل راتبين',
    AuditClassification.management => 'سحب إدارة',
    AuditClassification.notFound => 'غير موجود',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إعداد ومعاينة التدقيق')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(cycle.name, style: Theme.of(context).textTheme.titleLarge),
          if (cycle.auditClosed)
            const Text(
              'الدورة مغلقة؛ تُعرض المعاينة دون تغيير البيانات المحفوظة.',
            ),
          const SizedBox(height: 16),
          Text(
            infoSource?['label'] as String? ??
                'لم تختر معلومات المستخدمين بعد.',
          ),
          if (infoRows != null) Text('${infoRows!.length} صف محفوظ'),
          if (infoSource?['accountId'] != null &&
              widget.session.accountId != null &&
              infoSource!['accountId'] != widget.session.accountId)
            const Text(
              'المعلومات المحفوظة من حساب Google مختلف؛ راجع الحساب والملفات قبل المزامنة.',
            ),
          OutlinedButton.icon(
            onPressed:
                busy || cycle.auditClosed || hasIncompleteOperations
                    ? null
                    : _chooseInfo,
            icon: const Icon(Icons.cloud_outlined),
            label: const Text('اختيار معلومات المستخدمين'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<bool>(
            // ignore: deprecated_member_use
            value: infoHeader,
            decoration: const InputDecoration(
              labelText: 'هل الصف الأول عناوين؟',
            ),
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
                  infoHeader = value;
                  preview = null;
                }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: infoId,
            onChanged: (_) => setState(() => preview = null),
            textDirection: TextDirection.ltr,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'عمود رقم المستخدم',
              helperText: 'مثال: A أو AA',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: infoTitle,
            onChanged: (_) => setState(() => preview = null),
            textDirection: TextDirection.ltr,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'عمود اسم الورقة الهدف',
            ),
          ),
          if (widget.memberId != null) ...[
            const SizedBox(height: 12),
            Text('تدقيق فردي للمستخدم ${widget.memberId}'),
            TextField(
              controller: manualTarget,
              onChanged:
                  (_) => setState(() {
                    preview = null;
                    googleReview = null;
                    planSaved = false;
                  }),
              decoration: const InputDecoration(
                labelText: 'اسم ورقة الوجهة اليدوي (اختياري)',
                helperText:
                    'يُستخدم بدل اسم الورقة من جدول المعلومات لهذا المستخدم فقط.',
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: infoStatus,
            onChanged: (_) => setState(() => preview = null),
            textDirection: TextDirection.ltr,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'عمود حالة التدقيق (اختياري)',
            ),
          ),
          if (infoStatus.text.trim().isNotEmpty)
            CheckboxListTile(
              value: statusConfirmed,
              onChanged:
                  (value) => setState(() {
                    statusConfirmed = value ?? false;
                    preview = null;
                  }),
              title: const Text(
                'أكدت أن العمود مخصص لحالة التدقيق ولا يحتوي بيانات مالية',
              ),
            ),
          const SizedBox(height: 16),
          Text(
            target?['name'] as String? ??
                'لم تُحدد وجهة Google بعد. يمكنك المعاينة دون اختيارها.',
          ),
          OutlinedButton.icon(
            onPressed:
                busy || cycle.auditClosed || hasIncompleteOperations
                    ? null
                    : _chooseTarget,
            icon: const Icon(Icons.folder_open),
            label: const Text('اختيار جدول الوجهة'),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (savedOperations.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('سجل العمليات المحفوظة (${savedOperations.length})'),
            for (final operation in savedOperations.where(
              (op) => widget.memberId == null || op.memberId == widget.memberId,
            ))
              ListTile(
                dense: true,
                title: Text('${operation.memberId ?? '—'} · ${operation.type}'),
                subtitle: Text(
                  '${_operationStatus(operation.status)}${operation.lastError == null ? '' : '\n${operation.lastError}'}',
                ),
              ),
            if (operationEvents.isNotEmpty) ...[
              const Text('آخر أحداث المزامنة'),
              for (final event in operationEvents.take(8).toList().reversed)
                Text(
                  '${event['created_at']} · ${event['status']}${event['message'] == null ? '' : ' · ${event['message']}'}',
                ),
            ],
            OutlinedButton.icon(
              onPressed: busy || cycle.auditClosed ? null : _resumePlan,
              icon: const Icon(Icons.sync),
              label: const Text('التحقق أو استئناف العمليات المحفوظة'),
            ),
            if (canCancelUnstartedPlan)
              OutlinedButton.icon(
                onPressed:
                    busy || cycle.auditClosed ? null : _cancelUnstartedPlan,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('إلغاء الخطة كاملة قبل الكتابة'),
              ),
            const Text(
              'قد تُكتشف آثار سابقة بالقراءة، لكن كتابة Google ما زالت مقفلة حتى إتمام اختبارات السلامة الحقيقية.',
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : _preview,
            child: const Text('عرض المعاينة'),
          ),
          if (preview != null) ...[
            const SizedBox(height: 24),
            Text(
              'النتائج: ${preview!.members.length}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'هذه معاينة محلية فقط. كتابة Google مقفلة حتى اجتياز اختبارات السلامة.',
            ),
            OutlinedButton.icon(
              onPressed: busy || cycle.auditClosed ? null : _reviewGoogle,
              icon: const Icon(Icons.cloud_sync_outlined),
              label: const Text('التحقق من جداول Google'),
            ),
            if (googleReview != null) ...[
              Text(
                'مستخدمون قابلون للمراجعة: ${googleReview!.plannedMemberCount}',
              ),
              Text('خطوات مقترحة: ${googleReview!.operationCount}'),
              Text(
                planSaved
                    ? 'حُفظت الخطة محليًا بعد مراجعتها؛ كتابة Google ما زالت مقفلة.'
                    : 'هذه مراجعة فقط؛ لم تُحفظ خطة ولم تُرسل أي كتابة.',
              ),
              for (final issue in googleReview!.issues)
                Text('${issue.memberId}: ${issue.message}'),
              for (final member in googleReview!.audit.members)
                Text(
                  '${member.memberId}: ${_classification(member.classification)}',
                ),
              if (googleReview!.operationCount > 0 &&
                  !planSaved &&
                  !hasIncompleteOperations)
                FilledButton.icon(
                  onPressed: busy || cycle.auditClosed ? null : _savePlan,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('حفظ الخطة على الجهاز بعد مراجعتها'),
                ),
            ],
            for (final conflict in preview!.conflicts)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(conflict.message),
              ),
            for (final member in preview!.members)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.memberId.isEmpty
                            ? 'رقم مستخدم فارغ'
                            : member.memberId,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(_classification(member.classification)),
                      if (member.targetTitle != null)
                        Text('الوجهة: ${member.targetTitle}'),
                      if (member.diagnostic != null) Text(member.diagnostic!),
                      for (final issue in member.conflicts.where(
                        (issue) =>
                            !preview!.conflicts.any(
                              (common) => common.code == issue.code,
                            ),
                      ))
                        Text(
                          issue.message,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    ),
  );
}
