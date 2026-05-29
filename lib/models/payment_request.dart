import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentRequest {
  final String id;
  final String groupId;
  final String fromEmail;
  final String toEmail;
  final double amount;
  final String method; // 'Efectivo', 'Transferencia', 'Tigo Money', 'Otro'
  final String? reference;
  final String status; // 'pendiente', 'confirmado', 'rechazado'
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String rubro;
  final DateTime date;
  final String? imageUrl;
  final String? expenseId;

  PaymentRequest({
    required this.id,
    required this.groupId,
    required this.fromEmail,
    required this.toEmail,
    required this.amount,
    required this.method,
    this.reference,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
    required this.rubro,
    required this.date,
    this.imageUrl,
    this.expenseId,
  });

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now();
  }

  static DateTime? _parseDateTimeNullable(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  factory PaymentRequest.fromMap(String id, Map<String, dynamic> map) {
    final created = _parseDateTime(map['createdAt']);
    return PaymentRequest(
      id: id,
      groupId: map['groupId']?.toString() ?? '',
      fromEmail: map['fromEmail']?.toString() ?? '',
      toEmail: map['toEmail']?.toString() ?? '',
      amount: _parseDouble(map['amount']),
      method: map['method']?.toString() ?? 'Efectivo',
      reference: map['reference']?.toString(),
      status: map['status']?.toString() ?? 'pendiente',
      createdAt: created,
      resolvedAt: _parseDateTimeNullable(map['resolvedAt']),
      rubro: map['rubro']?.toString() ?? 'Otros',
      date: map['date'] != null ? _parseDateTime(map['date']) : created,
      imageUrl: map['imageUrl']?.toString(),
      expenseId: map['expenseId']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'groupId': groupId,
      'fromEmail': fromEmail,
      'toEmail': toEmail,
      'amount': amount,
      'method': method,
      'reference': reference,
      'status': status,
      'createdAt': createdAt,
      'resolvedAt': resolvedAt,
      'rubro': rubro,
      'date': Timestamp.fromDate(date),
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (expenseId != null) 'expenseId': expenseId,
    };
  }
}
