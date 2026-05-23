import 'package:cloud_firestore/cloud_firestore.dart';

class FriendRequest {
  final String id;
  final String fromEmail;
  final String toEmail;
  final String status; // 'pending', 'accepted', 'rejected'
  final DateTime createdAt;

  const FriendRequest({
    required this.id,
    required this.fromEmail,
    required this.toEmail,
    required this.status,
    required this.createdAt,
  });

  factory FriendRequest.fromMap(String id, Map<String, dynamic> map) {
    return FriendRequest(
      id: id,
      fromEmail: map['fromEmail'] as String? ?? '',
      toEmail: map['toEmail'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
      createdAt: map['createdAt'] is Timestamp
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'fromEmail': fromEmail,
        'toEmail': toEmail,
        'status': status,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
