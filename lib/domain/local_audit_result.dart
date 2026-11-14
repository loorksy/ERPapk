import 'audit_engine.dart';

/// Frozen audit evidence. Source row numbers refer to the audited snapshot.
class LocalAuditResult {
  const LocalAuditResult({
    required this.memberId,
    required this.classification,
    required this.fingerprint,
    required this.auditedAt,
    required this.individual,
    this.target,
    this.managementRow,
    this.agentRows = const [],
    this.color,
  });

  final String memberId;
  final AuditClassification classification;
  final String fingerprint;
  final DateTime auditedAt;
  final bool individual;
  final String? target;
  final SourceRow? managementRow;
  final List<SourceRow> agentRows;
  final String? color;

  bool get audited => classification != AuditClassification.notFound;

  Map<String, Object?> toJson() => {
    'memberId': memberId,
    'classification': classification.name,
    'fingerprint': fingerprint,
    'auditedAt': auditedAt.toUtc().toIso8601String(),
    'individual': individual,
    'target': target,
    'managementRow': managementRow == null ? null : _encodeRow(managementRow!),
    'agentRows': agentRows.map(_encodeRow).toList(),
    'color': color,
  };

  factory LocalAuditResult.fromJson(Map<String, Object?> json) =>
      LocalAuditResult(
        memberId: json['memberId'] as String,
        classification: AuditClassification.values.byName(
          json['classification'] as String,
        ),
        fingerprint: json['fingerprint'] as String,
        auditedAt: DateTime.parse(json['auditedAt'] as String),
        individual: json['individual'] as bool,
        target: json['target'] as String?,
        managementRow: json['managementRow'] == null
            ? null
            : _decodeRow(json['managementRow'] as List),
        agentRows: (json['agentRows'] as List)
            .map((value) => _decodeRow(value as List))
            .toList(),
        color: json['color'] as String?,
      );

  static List<Object?> _encodeRow(SourceRow row) => [row.rowNumber, row.values];

  static SourceRow _decodeRow(List row) =>
      SourceRow(row.first as int, List<String>.from(row.last as List));
}
