// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../data/local_audit_database.dart';
import '../domain/local_audit_result.dart';

class LocalAuditResultsPage extends StatelessWidget {
  const LocalAuditResultsPage({
    super.key,
    required this.db,
    required this.cycle,
  });

  final LocalAuditDatabase db;
  final CycleRecord cycle;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: Text(cycle.name),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'الحالات'),
            Tab(text: 'الوجهات'),
            Tab(text: 'السجل'),
          ],
        ),
      ),
      body: SafeArea(
        child: FutureBuilder(
          future: db.listLocalAudit(cycle.id, history: true),
          builder: (context, snapshot) {
            final history = snapshot.data;
            if (snapshot.hasError) {
              return const Center(child: Text('تعذر قراءة نتائج الدورة.'));
            }
            if (history == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (history.isEmpty) {
              return const Center(
                child: Text('لا توجد نتائج معتمدة لهذه الدورة.'),
              );
            }
            final current = <String, LocalAuditResult>{};
            for (final result in history) {
              current.putIfAbsent(result.memberId, () => result);
            }
            final byTarget = <String, List<LocalAuditResult>>{};
            for (final result in current.values) {
              final target = result.target;
              if (target != null) {
                byTarget.putIfAbsent(target, () => []).add(result);
              }
            }
            final targets = byTarget.keys.toList()..sort();
            return TabBarView(
              children: [
                _ResultList(current.values.toList()),
                if (targets.isEmpty)
                  const Center(child: Text('لا توجد صفوف منسوخة إلى وجهات.'))
                else
                  ListView.builder(
                    itemCount: targets.length,
                    itemBuilder: (context, index) {
                      final target = targets[index];
                      final rows = byTarget[target]!;
                      return ListTile(
                        title: Text(target),
                        subtitle: Text('${rows.length} صف'),
                        trailing: const Icon(Icons.chevron_left),
                        onTap:
                            () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder:
                                    (_) => Scaffold(
                                      appBar: AppBar(title: Text(target)),
                                      body: SafeArea(
                                        child: _ResultList(
                                          rows,
                                          showRows: true,
                                        ),
                                      ),
                                    ),
                              ),
                            ),
                      );
                    },
                  ),
                _ResultList(history, showHistory: true),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _ResultList extends StatelessWidget {
  const _ResultList(
    this.results, {
    this.showRows = false,
    this.showHistory = false,
  });

  final List<LocalAuditResult> results;
  final bool showRows;
  final bool showHistory;

  @override
  Widget build(BuildContext context) => ListView.builder(
    itemCount: results.length,
    itemBuilder: (context, index) {
      final result = results[index];
      final color = result.color;
      final date = result.auditedAt.toLocal().toString().split('.').first;
      return ListTile(
        leading: Icon(
          result.audited ? Icons.check_circle_outline : Icons.help_outline,
          color:
              color == null
                  ? null
                  : Color(
                    0xff000000 | int.parse(color.substring(1), radix: 16),
                  ),
        ),
        title: Text('${result.memberId} · ${result.classification.label}'),
        subtitle: Text(
          [
            result.audited ? 'مدقق' : 'غير مدقق',
            if (!showRows && result.target != null) result.target!,
            if (showRows && result.managementRow != null)
              result.managementRow!.values.join(' | '),
            if (showHistory) '$date · ${result.individual ? 'فردي' : 'جماعي'}',
          ].join('\n'),
        ),
      );
    },
  );
}
