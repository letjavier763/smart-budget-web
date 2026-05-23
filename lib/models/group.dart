import 'package:cloud_firestore/cloud_firestore.dart';

class GroupModel {
  final String id;
  final String name;
  final String code;
  final List<String> members;
  final String createdBy;
  final List<String> admins;
  final DateTime createdAt;
  final String? imageUrl;

  GroupModel({
    required this.id,
    required this.name,
    required this.code,
    required this.members,
    required this.createdBy,
    required this.admins,
    required this.createdAt,
    this.imageUrl,
  });

  static String buildInviteCode(String groupId) {
    return groupId.substring(0, 8).toUpperCase();
  }

  factory GroupModel.fromMap(String id, Map<String, dynamic> data) {
    final code = data['code'] as String? ?? buildInviteCode(id);
    final createdBy = data['createdBy'] as String? ?? '';
    final rawAdmins = data['admins'] as List<dynamic>?;
    final admins = rawAdmins != null ? List<String>.from(rawAdmins) : [createdBy];

    return GroupModel(
      id: id,
      name: data['name'] as String? ?? 'Grupo sin nombre',
      code: code,
      members: List<String>.from(data['members'] ?? []),
      createdBy: createdBy,
      admins: admins,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      imageUrl: data['imageUrl'] as String?,
    );
  }
}
