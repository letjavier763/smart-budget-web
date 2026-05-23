import 'package:cloud_firestore/cloud_firestore.dart';

class Expense {
  final String id;
  final String title;
  final double amount;
  final String paidBy;
  final DateTime createdAt;
  final List<String> involvedMembers;
  final String type; // 'expense' o 'payment'
  final String? paidTo;
  final String category; // 'Bien', 'Servicio', 'Actividad', etc.
  final DateTime? dueDate;
  final String? imageUrl;

  Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.paidBy,
    required this.createdAt,
    required this.involvedMembers,
    this.type = 'expense',
    this.paidTo,
    this.category = 'Bien',
    this.dueDate,
    this.imageUrl,
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

  factory Expense.fromMap(String id, Map<String, dynamic> data) {
    return Expense(
      id: id,
      title: data['title']?.toString() ?? 'Sin descripción',
      amount: _parseDouble(data['amount']),
      paidBy: data['paidBy']?.toString() ?? 'Desconocido',
      createdAt: _parseDateTime(data['createdAt']),
      involvedMembers: data['involvedMembers'] is List
          ? List<String>.from((data['involvedMembers'] as List).map((e) => e.toString()))
          : [],
      type: data['type']?.toString() ?? 'expense',
      paidTo: data['paidTo']?.toString(),
      category: data['category']?.toString() ?? 'Bien',
      dueDate: _parseDateTimeNullable(data['dueDate']),
      imageUrl: data['imageUrl']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'amount': amount,
      'paidBy': paidBy,
      'createdAt': FieldValue.serverTimestamp(),
      'involvedMembers': involvedMembers,
      'type': type,
      'category': category,
      if (paidTo != null) 'paidTo': paidTo,
      if (dueDate != null) 'dueDate': dueDate,
      if (imageUrl != null) 'imageUrl': imageUrl,
    };
  }
}
