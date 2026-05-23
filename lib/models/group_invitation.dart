import 'package:cloud_firestore/cloud_firestore.dart';

class GroupInvitation {
  final String id;
  final String groupId;
  final String fromEmail;
  final String toEmail; // Para invitaciones de admin a usuario. Si es join_request, puede estar vacío o ser genérico.
  final String type; // 'invitation' o 'join_request'
  final String status; // 'pending', 'accepted', 'rejected'
  final DateTime createdAt;
  final String groupName; // Guardamos el nombre del grupo para mostrarlo en la UI sin hacer joins adicionales

  GroupInvitation({
    required this.id,
    required this.groupId,
    required this.fromEmail,
    required this.toEmail,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.groupName,
  });

  factory GroupInvitation.fromMap(String id, Map<String, dynamic> map) {
    return GroupInvitation(
      id: id,
      groupId: map['groupId'] as String? ?? '',
      fromEmail: map['fromEmail'] as String? ?? '',
      toEmail: map['toEmail'] as String? ?? '',
      type: map['type'] as String? ?? 'invitation',
      status: map['status'] as String? ?? 'pending',
      createdAt: map['createdAt'] is Timestamp
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      groupName: map['groupName'] as String? ?? 'Grupo',
    );
  }

  Map<String, dynamic> toMap() => {
        'groupId': groupId,
        'fromEmail': fromEmail,
        'toEmail': toEmail,
        'type': type,
        'status': status,
        'groupName': groupName,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
