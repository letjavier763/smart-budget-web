import 'package:cloud_firestore/cloud_firestore.dart';

class Comment {
  final String id;
  final String text;
  final String userEmail;
  final DateTime createdAt;

  Comment({
    required this.id,
    required this.text,
    required this.userEmail,
    required this.createdAt,
  });

  factory Comment.fromMap(String id, Map<String, dynamic> data) {
    return Comment(
      id: id,
      text: data['text'] as String? ?? '',
      userEmail: data['userEmail'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'userEmail': userEmail,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
