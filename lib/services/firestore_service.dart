import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/expense.dart';
import 'dart:math';
import '../models/friend_request.dart';
import '../models/group.dart';
import '../models/group_invitation.dart';
import '../models/payment_request.dart';
import 'email_service.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ─── Groups ───────────────────────────────────────────────────────────────

  Stream<List<GroupModel>> groupsForUser(String userEmail) {
    final cleanEmail = userEmail.trim().toLowerCase();
    final rawEmail = userEmail.trim();
    if (cleanEmail.isEmpty) {
      return const Stream<List<GroupModel>>.empty();
    }

    if (cleanEmail == rawEmail) {
      return _firestore
          .collection('groups')
          .where('members', arrayContains: cleanEmail)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => GroupModel.fromMap(doc.id, doc.data()))
                .toList(),
          );
    }

    final stream1 = _firestore
        .collection('groups')
        .where('members', arrayContains: cleanEmail)
        .snapshots();
    final stream2 = _firestore
        .collection('groups')
        .where('members', arrayContains: rawEmail)
        .snapshots();

    final controller = StreamController<List<GroupModel>>.broadcast();
    List<GroupModel> list1 = [];
    List<GroupModel> list2 = [];
    StreamSubscription? sub1;
    StreamSubscription? sub2;
    List<GroupModel>? lastEmitted;
    bool hasEmitted = false;

    void emitCombined() {
      final Map<String, GroupModel> combined = {};
      for (final g in list1) {
        combined[g.id] = g;
      }
      for (final g in list2) {
        combined[g.id] = g;
      }
      final result = combined.values.toList();
      lastEmitted = result;
      hasEmitted = true;
      if (!controller.isClosed) {
        controller.add(result);
      }
    }

    controller.onListen = () {
      sub1 = stream1.listen((snapshot) {
        list1 = snapshot.docs
            .map((doc) => GroupModel.fromMap(doc.id, doc.data()))
            .toList();
        emitCombined();
      }, onError: controller.addError);

      sub2 = stream2.listen((snapshot) {
        list2 = snapshot.docs
            .map((doc) => GroupModel.fromMap(doc.id, doc.data()))
            .toList();
        emitCombined();
      }, onError: controller.addError);
    };

    controller.onCancel = () {
      sub1?.cancel();
      sub2?.cancel();
    };

    return Stream<List<GroupModel>>.multi((multiController) {
      if (hasEmitted && lastEmitted != null) {
        multiController.add(lastEmitted!);
      }
      final sub = controller.stream.listen(
        multiController.add,
        onError: multiController.addError,
        onDone: multiController.close,
      );
      multiController.onCancel = () => sub.cancel();
    });
  }

  // ---------------------------------------------------------------------
  // Friend code utilities
  // ---------------------------------------------------------------------
  /// Generates a random alphanumeric code of length 8.
  String _generateRandomCode([int length = 8]) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  /// Ensures the user has a fresh friend code for the current session.
  /// Overwrites any existing code.
  Future<String> regenerateFriendCode(String uid) async {
    String newCode;
    // Loop until we find a code that is not used by another user.
    do {
      newCode = _generateRandomCode();
      final existing = await _firestore
          .collection('users')
          .where('friendCode', isEqualTo: newCode)
          .limit(1)
          .get();
      if (existing.docs.isEmpty) break;
    } while (true);
    // Update the user's document with the new code.
    await _firestore.collection('users').doc(uid).set({
      'friendCode': newCode,
    }, SetOptions(merge: true));
    return newCode;
  }

  /// Retrieves the UID associated with a given friend code.
  Future<String?> getUidByFriendCode(String code) async {
    final query = await _firestore
        .collection('users')
        .where('friendCode', isEqualTo: code)
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;
    return query.docs.first.id;
  }

  /// Retrieves the email of a user given their UID.
  Future<String?> getEmailByUid(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    final data = doc.data();
    return data?['email'] as String?;
  }

  /// Retrieves the friend code associated with a UID.
  Future<String?> getFriendCodeByUid(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    final data = doc.data();
    return data?['friendCode'] as String?;
  }

  /// One-shot fetch of groups with timeout + cache fallback.
  /// Use this instead of [groupsForUser] when you need a guaranteed
  /// result even on flaky / offline connections.
  Future<List<GroupModel>> getGroupsForUser(String userEmail) async {
    // Existing group fetching logic unchanged (kept for context)
    final cleanEmail = userEmail.trim().toLowerCase();
    final rawEmail = userEmail.trim();
    if (cleanEmail.isEmpty) return [];

    final cleanQuery = _firestore
        .collection('groups')
        .where('members', arrayContains: cleanEmail);
    final rawQuery = rawEmail == cleanEmail
        ? null
        : _firestore
            .collection('groups')
            .where('members', arrayContains: rawEmail);

    try {
      final cleanSnap = await cleanQuery.get().timeout(const Duration(seconds: 5));
      final rawSnap = rawQuery != null
          ? await rawQuery.get().timeout(const Duration(seconds: 5))
          : null;

      final Map<String, GroupModel> groupMap = {};
      for (final doc in cleanSnap.docs) {
        groupMap[doc.id] = GroupModel.fromMap(doc.id, doc.data());
      }
      if (rawSnap != null) {
        for (final doc in rawSnap.docs) {
          groupMap[doc.id] = GroupModel.fromMap(doc.id, doc.data());
        }
      }
      return groupMap.values.toList();
    } catch (_) {
      try {
        final cleanSnap = await cleanQuery.get(const GetOptions(source: Source.cache));
        final rawSnap = rawQuery != null
            ? await rawQuery.get(const GetOptions(source: Source.cache))
            : null;

        final Map<String, GroupModel> groupMap = {};
        for (final doc in cleanSnap.docs) {
          groupMap[doc.id] = GroupModel.fromMap(doc.id, doc.data());
        }
        if (rawSnap != null) {
          for (final doc in rawSnap.docs) {
            groupMap[doc.id] = GroupModel.fromMap(doc.id, doc.data());
          }
        }
        return groupMap.values.toList();
      } catch (_) {
        return [];
      }
    }
  }

  Future<void> createSharedGroup({
    required String name,
    required List<String> members,
    required String createdBy,
    int? maxMembers,
    double? initialBudget,
    DateTime? activeUntil,
  }) async {
    // Solo el creador entra directo al grupo inicialmente.
    final groupRef = await _firestore.collection('groups').add({
      'name': name.trim(),
      'members': [createdBy],
      'createdBy': createdBy,
      'admins': [createdBy],
      'createdAt': FieldValue.serverTimestamp(),
      'maxMembers': maxMembers,
      'initialBudget': initialBudget,
      'activeUntil': activeUntil,
    });

    final code = GroupModel.buildInviteCode(groupRef.id);
    await groupRef.update({'code': code});

    // Enviar invitaciones a los demás amigos seleccionados
    final otherMembers = members
        .map((email) => email.trim())
        .where((email) => email.isNotEmpty && email != createdBy)
        .toSet()
        .toList();

    for (final member in otherMembers) {
      await sendGroupInvitation(
        groupId: groupRef.id,
        fromEmail: createdBy,
        toEmail: member,
        groupName: name.trim(),
      );
    }
  }

  Future<GroupModel?> getGroupByCode(String code) async {
    final query = await _firestore
        .collection('groups')
        .where('code', isEqualTo: code.trim().toUpperCase())
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      return null;
    }
    final doc = query.docs.first;
    return GroupModel.fromMap(doc.id, doc.data());
  }

  Future<void> joinGroupByCode({
    required String groupCode,
    required String userEmail,
  }) async {
    final group = await getGroupByCode(groupCode);
    if (group == null) {
      throw Exception('No se encontró un grupo con ese código.');
    }

    if (group.members.any((m) => m.trim().toLowerCase() == userEmail.trim().toLowerCase())) {
      throw Exception('Ya perteneces a este grupo.');
    }

    if (group.maxMembers != null && group.members.length >= group.maxMembers!) {
      throw Exception('El grupo ha alcanzado su capacidad máxima de miembros.');
    }

    await sendJoinRequest(
      groupId: group.id,
      userEmail: userEmail,
      groupName: group.name,
    );
  }

  Stream<GroupModel?> groupStream(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .snapshots()
        .map(
          (doc) =>
              doc.exists ? GroupModel.fromMap(doc.id, doc.data() ?? {}) : null,
        );
  }

  // ─── Group Invitations & Join Requests ────────────────────────────────────

  Future<void> sendGroupInvitation({
    required String groupId,
    required String fromEmail,
    required String toEmail,
    required String groupName,
  }) async {
    final from = fromEmail.trim().toLowerCase();
    final to = toEmail.trim().toLowerCase();

    if (from == to) throw Exception('No puedes invitarte a ti mismo.');

    // Verificar si ya está en el grupo
    int memberCount = 0;
    double? initialBudget;
    final groupDoc = await _firestore.collection('groups').doc(groupId).get();
    String groupCode = '';
    if (groupDoc.exists) {
      final data = groupDoc.data() ?? {};
      groupCode = data['code'] as String? ?? '';
      final members = List<String>.from(data['members'] ?? []);
      memberCount = members.length;
      initialBudget = (data['initialBudget'] as num?)?.toDouble();
      if (members.any((m) => m.trim().toLowerCase() == to.trim().toLowerCase())) {
        throw Exception('El usuario ya pertenece al grupo.');
      }
    }

    // Verificar si ya existe una invitación pendiente
    final existing = await _firestore
        .collection('group_invitations')
        .where('groupId', isEqualTo: groupId)
        .where('toEmail', isEqualTo: to)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      throw Exception('Ya existe una invitación pendiente para este usuario.');
    }

    await _firestore.collection('group_invitations').add({
      'groupId': groupId,
      'fromEmail': from,
      'toEmail': to,
      'type': 'invitation',
      'status': 'pending',
      'groupName': groupName,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Obtener detalles de gastos para agregarlos a la invitación
    final expensesSnap = await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .get();
    final expenseCount = expensesSnap.docs.length;
    final totalExpenses = expensesSnap.docs.fold<double>(
      0.0,
      (sum, doc) => sum + (doc.data()['amount'] as num? ?? 0.0).toDouble(),
    );

    // Enviar correo de invitación de forma asíncrona
    final fromName = from.split('@')[0];
    final String webAppBaseUrl;
    if (kIsWeb) {
      webAppBaseUrl = Uri.base.replace(queryParameters: {}, fragment: '').toString();
    } else {
      webAppBaseUrl = 'https://smartbudget-88efb.web.app';
    }
    
    EmailService.sendGroupInvitation(
      toEmail: to,
      groupName: groupName,
      fromName: fromName,
      groupCode: groupCode,
      webAppBaseUrl: webAppBaseUrl,
      memberCount: memberCount,
      initialBudget: initialBudget,
      expenseCount: expenseCount,
      totalExpenses: totalExpenses,
    ).catchError((e) {
      debugPrint('Error al enviar correo de invitación: $e');
    });
  }

  Future<void> sendJoinRequest({
    required String groupId,
    required String userEmail,
    required String groupName,
  }) async {
    final from = userEmail.trim().toLowerCase();

    final existing = await _firestore
        .collection('group_invitations')
        .where('groupId', isEqualTo: groupId)
        .where('fromEmail', isEqualTo: from)
        .where('type', isEqualTo: 'join_request')
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      throw Exception('Ya has enviado una solicitud para unirte a este grupo.');
    }

    await _firestore.collection('group_invitations').add({
      'groupId': groupId,
      'fromEmail': from,
      'toEmail':
          '', // Las solicitudes de unión pueden ser aprobadas por cualquier admin
      'type': 'join_request',
      'status': 'pending',
      'groupName': groupName,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> respondGroupInvitation({
    required String invitationId,
    required bool accept,
    required String groupId,
    required String targetEmail,
  }) async {
    if (accept) {
      final doc = await _firestore.collection('groups').doc(groupId).get();
      if (!doc.exists) {
        throw Exception('El grupo no existe.');
      }
      final data = doc.data() ?? {};
      final members = List<String>.from(data['members'] ?? []);
      final maxMembers = data['maxMembers'] as int?;
      if (maxMembers != null && members.length >= maxMembers) {
        throw Exception('El grupo ha alcanzado su capacidad máxima de miembros.');
      }

      await _firestore.collection('groups').doc(groupId).update({
        'members': FieldValue.arrayUnion([targetEmail]),
      });
    }

    await _firestore.collection('group_invitations').doc(invitationId).update({
      'status': accept ? 'accepted' : 'rejected',
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<GroupInvitation>> pendingGroupInvitationsStream(
    String userEmail,
  ) {
    return _firestore
        .collection('group_invitations')
        .where('toEmail', isEqualTo: userEmail.trim().toLowerCase())
        .where('type', isEqualTo: 'invitation')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) {
          final list = s.docs
              .map((d) => GroupInvitation.fromMap(d.id, d.data()))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  Stream<List<GroupInvitation>> pendingJoinRequestsStream(String groupId) {
    return _firestore
        .collection('group_invitations')
        .where('groupId', isEqualTo: groupId)
        .where('type', isEqualTo: 'join_request')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) {
          final list = s.docs
              .map((d) => GroupInvitation.fromMap(d.id, d.data()))
              .toList();
          list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return list;
        });
  }

  Stream<int> totalPendingGroupActionsStream(String userEmail) {
    final email = userEmail.trim().toLowerCase();
    final controller = StreamController<int>.broadcast();

    StreamSubscription? invitationsSubscription;
    StreamSubscription? groupsSubscription;
    final Map<String, StreamSubscription> joinRequestSubscriptions = {};
    final Map<String, int> joinRequestCounts = {};
    int invitationsCount = 0;

    void emitTotal() {
      if (controller.isClosed) return;
      int totalJoinRequests = 0;
      for (final count in joinRequestCounts.values) {
        totalJoinRequests += count;
      }
      controller.add(invitationsCount + totalJoinRequests);
    }

    controller.onListen = () {
      invitationsSubscription = pendingGroupInvitationsStream(email).listen((invitations) {
        invitationsCount = invitations.length;
        emitTotal();
      }, onError: controller.addError);

      groupsSubscription = groupsForUser(email).listen((groups) {
        final adminGroupIds = groups
            .where((g) => g.createdBy.trim().toLowerCase() == email)
            .map((g) => g.id)
            .toSet();

        final removedGroupIds = joinRequestSubscriptions.keys.where((id) => !adminGroupIds.contains(id)).toList();
        for (final id in removedGroupIds) {
          joinRequestSubscriptions.remove(id)?.cancel();
          joinRequestCounts.remove(id);
        }

        for (final groupId in adminGroupIds) {
          if (!joinRequestSubscriptions.containsKey(groupId)) {
            joinRequestSubscriptions[groupId] = pendingJoinRequestsStream(groupId).listen((requests) {
              joinRequestCounts[groupId] = requests.length;
              emitTotal();
            }, onError: (err) {
              debugPrint('Error loading join requests for group $groupId: $err');
            });
          }
        }
        if (adminGroupIds.isEmpty) {
          emitTotal();
        }
      }, onError: controller.addError);
    };

    controller.onCancel = () {
      invitationsSubscription?.cancel();
      groupsSubscription?.cancel();
      for (final sub in joinRequestSubscriptions.values) {
        sub.cancel();
      }
      joinRequestSubscriptions.clear();
      joinRequestCounts.clear();
    };

    return controller.stream;
  }

  Future<void> removeMemberFromGroup({
    required String groupId,
    required String memberEmail,
  }) async {
    final email = memberEmail.trim();
    if (email.isEmpty) {
      throw Exception('Correo inválido.');
    }

    await _firestore.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayRemove([email]),
      'admins': FieldValue.arrayRemove([email]),
    });
  }

  Future<void> toggleAdminStatus({
    required String groupId,
    required String memberEmail,
    required bool makeAdmin,
  }) async {
    final docRef = _firestore.collection('groups').doc(groupId);
    if (makeAdmin) {
      await docRef.update({
        'admins': FieldValue.arrayUnion([memberEmail]),
      });
    } else {
      await docRef.update({
        'admins': FieldValue.arrayRemove([memberEmail]),
      });
    }
  }

  // ─── Expenses ─────────────────────────────────────────────────────────────

  Stream<List<Expense>> expensesForGroup(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Expense.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<List<Expense>> getExpensesForGroup(String groupId) async {
    final query = _firestore
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .orderBy('createdAt', descending: true);

    try {
      final snapshot = await query.get().timeout(const Duration(seconds: 4));
      return snapshot.docs
          .map((doc) => Expense.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      // Fallback to cache if request times out or fails (e.g., offline)
      try {
        final snapshot = await query.get(const GetOptions(source: Source.cache));
        return snapshot.docs
            .map((doc) => Expense.fromMap(doc.id, doc.data()))
            .toList();
      } catch (_) {
        rethrow;
      }
    }
  }

  Future<void> createExpense({
    required String groupId,
    required String title,
    required double amount,
    required String paidBy,
    required List<String> involvedMembers,
    String type = 'expense',
    String? paidTo,
    String category = 'Bien',
    DateTime? dueDate,
    String? imageUrl,
    DateTime? createdAt,
  }) async {
    final cleanPaidBy = paidBy.trim().toLowerCase();
    final cleanPaidTo = paidTo?.trim().toLowerCase();
    final cleanInvolvedMembers = involvedMembers.map((m) => m.trim().toLowerCase()).toList();

    final docRef = await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .add({
          'title': title.trim(),
          'amount': amount,
          'paidBy': cleanPaidBy,
          'createdAt': createdAt != null ? Timestamp.fromDate(createdAt) : FieldValue.serverTimestamp(),
          'involvedMembers': cleanInvolvedMembers,
          'type': type,
          'category': category,
          'paidTo': cleanPaidTo,
          'dueDate': dueDate,
          'imageUrl': imageUrl,
        });

    if (type == 'expense') {
      try {
        final groupDoc = await _firestore.collection('groups').doc(groupId).get();
        if (groupDoc.exists) {
          final groupData = groupDoc.data() ?? {};
          final groupName = groupData['name'] as String? ?? 'Grupo';
          final admins = List<String>.from(groupData['admins'] ?? []).map((a) => a.trim().toLowerCase()).toList();
          if (admins.contains(cleanPaidBy)) {
            final members = List<String>.from(groupData['members'] ?? []).map((m) => m.trim().toLowerCase()).toList();
            final targets = cleanInvolvedMembers.isNotEmpty ? cleanInvolvedMembers : members;
            final splitMembers = targets.where((m) => m != cleanPaidBy).toList();
            if (splitMembers.isNotEmpty && targets.isNotEmpty) {
              final share = amount / targets.length;
              final fromName = cleanPaidBy.split('@')[0];
              for (final debtor in splitMembers) {
                final reqRef = await _firestore
                    .collection('groups')
                    .doc(groupId)
                    .collection('payment_requests')
                    .add({
                      'groupId': groupId,
                      'fromEmail': debtor,
                      'toEmail': cleanPaidBy,
                      'amount': share,
                      'method': 'Boleta',
                      'rubro': category,
                      'date': Timestamp.fromDate(dueDate ?? createdAt ?? DateTime.now()),
                      'imageUrl': null,
                      'reference': 'Gasto: ${title.trim()}',
                      'status': 'pendiente_boleta',
                      'createdAt': FieldValue.serverTimestamp(),
                      'resolvedAt': null,
                      'expenseId': docRef.id,
                    });

                String bodyText = '$fromName añadió el gasto "$title" en "$groupName". Tu parte es Q${share.toStringAsFixed(2)}.';
                if (dueDate != null) {
                  bodyText += ' Debes pagarlo a más tardar el ${dueDate.day}/${dueDate.month}/${dueDate.year}.';
                } else {
                  bodyText += ' Sube tu boleta de pago.';
                }

                await createNotification(
                  userEmail: debtor,
                  title: 'Nuevo gasto a pagar',
                  body: bodyText,
                  extraData: {'requestId': reqRef.id, 'groupId': groupId},
                );
              }
            }
          }
        }
      } catch (e) {
        // Log the error but don't crash the expense creation
        debugPrint('Error creating automatic payment requests: $e');
      }
    }
  }

  Future<void> updateExpense({
    required String groupId,
    required String expenseId,
    required String title,
    required double amount,
    required String category,
  }) async {
    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .doc(expenseId)
        .update({
          'title': title.trim(),
          'amount': amount,
          'category': category,
        });

    final query = await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('payment_requests')
        .where('expenseId', isEqualTo: expenseId)
        .get();

    // Filtrar en memoria para evitar errores de índice faltante en Firestore
    final docsToUpdate = query.docs.where((doc) {
      final status = doc.data()['status'] as String?;
      return status == 'pendiente' || status == 'pendiente_boleta';
    }).toList();

    final expenseDoc = await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .doc(expenseId)
        .get();

    if (expenseDoc.exists) {
      final expenseData = expenseDoc.data() ?? {};
      final involvedMembers = List<String>.from(expenseData['involvedMembers'] ?? []);
      
      final groupDoc = await _firestore.collection('groups').doc(groupId).get();
      final groupMembers = groupDoc.exists
          ? List<String>.from(groupDoc.data()?['members'] ?? [])
          : <String>[];

      final targets = involvedMembers.isNotEmpty ? involvedMembers : groupMembers;
      if (targets.isNotEmpty) {
        final share = amount / targets.length;
        for (final doc in docsToUpdate) {
          await doc.reference.update({
            'amount': share,
            'reference': 'Gasto: ${title.trim()}',
            'rubro': category,
          });
        }
      }
    }
  }

  Future<void> updateGroup({
    required String groupId,
    required String name,
    String? imageUrl,
    int? maxMembers,
    double? initialBudget,
    DateTime? activeUntil,
  }) async {
    await _firestore.collection('groups').doc(groupId).update({
      'name': name.trim(),
      'imageUrl': imageUrl,
      'maxMembers': maxMembers,
      'initialBudget': initialBudget,
      'activeUntil': activeUntil,
    });
  }

  /// Elimina un grupo completo: primero borra las subcolecciones y luego el documento.
  /// ⚠️ Solo debe llamarse si el usuario actual es el creador del grupo.
  Future<void> deleteGroup({required String groupId}) async {
    final groupRef = _firestore.collection('groups').doc(groupId);

    // 1. Borrar subcolección 'expenses' (y sus comentarios anidados)
    final expensesSnap = await groupRef.collection('expenses').get();
    for (final expDoc in expensesSnap.docs) {
      // Borrar comentarios dentro de cada expense
      final commentsSnap = await expDoc.reference.collection('comments').get();
      for (final c in commentsSnap.docs) {
        await c.reference.delete();
      }
      await expDoc.reference.delete();
    }

    // 2. Borrar subcolección 'payment_requests'
    final reqsSnap = await groupRef.collection('payment_requests').get();
    for (final reqDoc in reqsSnap.docs) {
      await reqDoc.reference.delete();
    }

    // 3. Borrar el documento del grupo
    await groupRef.delete();
  }

  Future<void> deleteExpense({
    required String groupId,
    required String expenseId,
  }) async {
    final expenseDoc = await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .doc(expenseId)
        .get();

    String expenseTitle = 'Gasto eliminado';
    String expenseCategory = 'Otros';
    if (expenseDoc.exists) {
      final expenseData = expenseDoc.data() ?? {};
      expenseTitle = expenseData['title'] as String? ?? 'Gasto eliminado';
      expenseCategory = expenseData['category'] as String? ?? 'Otros';
    }

    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .doc(expenseId)
        .delete();

    final query = await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('payment_requests')
        .where('expenseId', isEqualTo: expenseId)
        .get();

    for (final doc in query.docs) {
      final status = doc.data()['status'] as String?;
      if (status == 'pendiente' || status == 'pendiente_boleta') {
        await doc.reference.delete();
      } else if (status == 'confirmado') {
        final fromEmail = doc.data()['fromEmail'] as String?;
        final toEmail = doc.data()['toEmail'] as String?;
        final amount = (doc.data()['amount'] as num? ?? 0.0).toDouble();

        if (fromEmail != null && toEmail != null && amount > 0) {
          await createExpense(
            groupId: groupId,
            title: 'Devolución: Gasto eliminado ($expenseTitle)',
            amount: amount,
            paidBy: toEmail,
            involvedMembers: [fromEmail],
            type: 'payment',
            paidTo: fromEmail,
            category: expenseCategory,
          );
        }
        await doc.reference.update({'status': 'reembolsado'});
      }
    }
  }

  // ─── Comments ──────────────────────────────────────────────────────────────

  Future<void> addComment({
    required String groupId,
    required String expenseId,
    required String text,
    required String userEmail,
  }) async {
    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .doc(expenseId)
        .collection('comments')
        .add({
          'text': text.trim(),
          'userEmail': userEmail,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  Stream<List<Map<String, dynamic>>> commentsStream(
    String groupId,
    String expenseId,
  ) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .doc(expenseId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList(),
        );
  }

  // ─── Payment Requests (Sistema de 2 pasos) ────────────────────────────────

  Future<void> sendPaymentReminder({
    required String groupId,
    required String fromEmail,
    required String toEmail,
    required double amount,
  }) async {
    // Simularemos el envío del recordatorio ya que no tenemos Cloud Functions para Push Notifications.
    // Podríamos guardar un doc en una colección de "notificaciones", pero por ahora solo lo simulamos.
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Crea una solicitud de pago pendiente de confirmación.
  Future<void> createPaymentRequest({
    required String groupId,
    required String fromEmail,
    required String toEmail,
    required double amount,
    required String method,
    required String rubro,
    required DateTime date,
    String? imageUrl,
    String? reference,
  }) async {
    final cleanFromEmail = fromEmail.trim().toLowerCase();
    final cleanToEmail = toEmail.trim().toLowerCase();
    final docRef = await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('payment_requests')
        .add({
          'groupId': groupId,
          'fromEmail': cleanFromEmail,
          'toEmail': cleanToEmail,
          'amount': amount,
          'method': method,
          'rubro': rubro,
          'date': Timestamp.fromDate(date),
          'imageUrl': imageUrl,
          'reference': reference?.trim(),
          'status': 'pendiente',
          'createdAt': FieldValue.serverTimestamp(),
          'resolvedAt': null,
        });

    final fromName = cleanFromEmail.split('@')[0];
    await createNotification(
      userEmail: cleanToEmail,
      title: 'Solicitud de pago',
      body:
          '$fromName quiere pagarte Q${amount.toStringAsFixed(2)} via $method. Toca para confirmar o rechazar.',
      extraData: {'requestId': docRef.id, 'groupId': groupId},
    );
  }

  /// Confirma una solicitud: actualiza el balance del grupo y notifica al deudor.
  Future<void> confirmPaymentRequest({
    required String groupId,
    required String requestId,
    required PaymentRequest request,
  }) async {
    // 1. Actualizar estado de la solicitud
    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('payment_requests')
        .doc(requestId)
        .update({
          'status': 'confirmado',
          'resolvedAt': FieldValue.serverTimestamp(),
        });

    // 2. Registrar el pago real en el historial de gastos (actualiza balances)
    await createExpense(
      groupId: groupId,
      title: 'Pago confirmado (${request.method})',
      amount: request.amount,
      paidBy: request.fromEmail,
      involvedMembers: [request.toEmail],
      type: 'payment',
      paidTo: request.toEmail,
      category: request.rubro,
      createdAt: request.date,
      imageUrl: request.imageUrl,
    );

    // 3. Notificar al deudor
    final toName = request.toEmail.split('@')[0];
    await createNotification(
      userEmail: request.fromEmail,
      title: 'Pago confirmado',
      body:
          '$toName confirmó tu pago de Q${request.amount.toStringAsFixed(2)}. Tu balance ha sido actualizado.',
    );
  }

  /// Rechaza una solicitud y notifica al deudor.
  Future<void> rejectPaymentRequest({
    required String groupId,
    required String requestId,
    required PaymentRequest request,
  }) async {
    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('payment_requests')
        .doc(requestId)
        .update({
          'status': 'rechazado',
          'resolvedAt': FieldValue.serverTimestamp(),
        });

    final toName = request.toEmail.split('@')[0];
    await createNotification(
      userEmail: request.fromEmail,
      title: 'Pago rechazado',
      body:
          '$toName rechazó tu solicitud de Q${request.amount.toStringAsFixed(2)}. Puedes volver a intentarlo.',
    );
  }

  /// Sube la boleta de pago para una solicitud y cambia su estado a pendiente de revisión.
  Future<void> submitBoletaForPaymentRequest({
    required String groupId,
    required String requestId,
    required String imageUrl,
    required PaymentRequest request,
    String? method,
    String? reference,
    double? amount,
    String? rubro,
    DateTime? date,
  }) async {
    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('payment_requests')
        .doc(requestId)
        .update({
          'imageUrl': imageUrl,
          'status': 'pendiente',
          'date': Timestamp.fromDate(date ?? DateTime.now()),
          'method': ?method,
          'reference': ?reference,
          'amount': ?amount,
          'rubro': ?rubro,
        });

    final fromName = request.fromEmail.split('@')[0];
    await createNotification(
      userEmail: request.toEmail,
      title: 'Boleta de pago subida',
      body: '$fromName subió la boleta para el pago de Q${(amount ?? request.amount).toStringAsFixed(2)}. Toca para verificar.',
      extraData: {'requestId': requestId, 'groupId': groupId},
    );
  }


  /// Stream de solicitudes de pago de un grupo (todas).
  Stream<List<PaymentRequest>> paymentRequestsForGroup(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('payment_requests')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => PaymentRequest.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<List<PaymentRequest>> getPaymentRequestsForGroup(
    String groupId,
  ) async {
    final query = _firestore
        .collection('groups')
        .doc(groupId)
        .collection('payment_requests');

    try {
      final snap = await query.get().timeout(const Duration(seconds: 4));
      return snap.docs
          .map((doc) => PaymentRequest.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      // Fallback to cache if request times out or fails (e.g., offline)
      try {
        final snap = await query.get(const GetOptions(source: Source.cache));
        return snap.docs
            .map((doc) => PaymentRequest.fromMap(doc.id, doc.data()))
            .toList();
      } catch (_) {
        rethrow;
      }
    }
  }

  /// Stream de solicitudes pendientes de un grupo (status='pendiente' o 'pendiente_boleta').
  Stream<List<PaymentRequest>> pendingRequestsForGroup(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('payment_requests')
        .where('status', whereIn: const ['pendiente', 'pendiente_boleta'])
        .snapshots()
        .map((snap) {
          final reqs = snap.docs
              .map((doc) => PaymentRequest.fromMap(doc.id, doc.data()))
              .toList();
          reqs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return reqs;
        });
  }

  /// Stream de todas las solicitudes donde el usuario es involucrado (enviadas o recibidas).
  Stream<List<PaymentRequest>> paymentRequestsForUser(String userEmail) {
    // Firestore no permite OR queries directamente, usamos dos streams y los combinamos.
    // Para simplificar, traemos todas las de los grupos del usuario desde el client.
    // Se resuelve en la UI combinando los resultados.
    return _firestore
        .collectionGroup('payment_requests')
        .where('fromEmail', isEqualTo: userEmail)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => PaymentRequest.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Stream<List<PaymentRequest>> incomingPaymentRequestsForUser(
    String userEmail,
  ) {
    return _firestore
        .collectionGroup('payment_requests')
        .where('toEmail', isEqualTo: userEmail)
        .where('status', isEqualTo: 'pendiente')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => PaymentRequest.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Stream<List<MapEntry<GroupModel, Expense>>> userExpensesStream(String userEmail) {
    final email = userEmail.trim().toLowerCase();
    final controller = StreamController<List<MapEntry<GroupModel, Expense>>>.broadcast();

    StreamSubscription? groupsSubscription;
    final Map<String, StreamSubscription> groupSubscriptions = {};
    final Map<String, List<Expense>> groupExpenses = {};
    final Map<String, GroupModel> groupModels = {};

    void emitCombined() {
      if (controller.isClosed) return;
      final allExpenses = <MapEntry<GroupModel, Expense>>[];
      for (final entry in groupExpenses.entries) {
        final groupId = entry.key;
        final expenses = entry.value;
        final group = groupModels[groupId];
        if (group != null) {
          for (final exp in expenses) {
            allExpenses.add(MapEntry(group, exp));
          }
        }
      }
      
      final mine = allExpenses.where((entry) {
        final e = entry.value;
        return e.paidBy.trim().toLowerCase() == email ||
            (e.type == 'payment' && e.paidTo?.trim().toLowerCase() == email);
      }).toList();
      
      mine.sort((a, b) => b.value.createdAt.compareTo(a.value.createdAt));
      controller.add(mine);
    }

    controller.onListen = () {
      groupsSubscription = groupsForUser(email).listen((groups) {
        final groupIds = groups.map((g) => g.id).toSet();
        final removedGroupIds = groupSubscriptions.keys.where((id) => !groupIds.contains(id)).toList();
        for (final id in removedGroupIds) {
          groupSubscriptions.remove(id)?.cancel();
          groupExpenses.remove(id);
          groupModels.remove(id);
        }

        for (final group in groups) {
          groupModels[group.id] = group;
          if (!groupSubscriptions.containsKey(group.id)) {
            final groupStream = expensesForGroup(group.id);

            groupSubscriptions[group.id] = groupStream.listen((expenses) {
              groupExpenses[group.id] = expenses;
              emitCombined();
            }, onError: (err) {
              debugPrint('Error loading expenses for group ${group.id}: $err');
            });
          }
        }
        if (groups.isEmpty) {
          emitCombined();
        }
      }, onError: controller.addError);
    };

    controller.onCancel = () {
      groupsSubscription?.cancel();
      for (final sub in groupSubscriptions.values) {
        sub.cancel();
      }
      groupSubscriptions.clear();
      groupExpenses.clear();
      groupModels.clear();
    };

    return controller.stream;
  }

  Stream<List<PaymentRequest>> activePaymentRequestsForUser(String userEmail) {
    final email = userEmail.trim().toLowerCase();
    final controller = StreamController<List<PaymentRequest>>.broadcast();

    StreamSubscription? groupsSubscription;
    final Map<String, StreamSubscription> groupSubscriptions = {};
    final Map<String, List<PaymentRequest>> groupRequests = {};

    void emitCombined() {
      if (controller.isClosed) return;
      final allRequests = <PaymentRequest>[];
      for (final reqs in groupRequests.values) {
        allRequests.addAll(reqs);
      }
      final active = allRequests.where((r) {
        final isUserInvolved = r.fromEmail.trim().toLowerCase() == email ||
            r.toEmail.trim().toLowerCase() == email;
        return isUserInvolved && r.status != 'confirmado';
      }).toList();
      active.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      controller.add(active);
    }

    controller.onListen = () {
      groupsSubscription = groupsForUser(email).listen((groups) {
        final groupIds = groups.map((g) => g.id).toSet();
        final removedGroupIds = groupSubscriptions.keys.where((id) => !groupIds.contains(id)).toList();
        for (final id in removedGroupIds) {
          groupSubscriptions.remove(id)?.cancel();
          groupRequests.remove(id);
        }

        for (final group in groups) {
          if (!groupSubscriptions.containsKey(group.id)) {
            final groupStream = _firestore
                .collection('groups')
                .doc(group.id)
                .collection('payment_requests')
                .snapshots();

            groupSubscriptions[group.id] = groupStream.listen((snap) {
              final reqs = snap.docs
                  .map((doc) => PaymentRequest.fromMap(doc.id, doc.data()))
                  .toList();
              groupRequests[group.id] = reqs;
              emitCombined();
            }, onError: (err) {
              debugPrint('Error loading requests for group ${group.id}: $err');
            });
          }
        }
        if (groups.isEmpty) {
          emitCombined();
        }
      }, onError: controller.addError);
    };

    controller.onCancel = () {
      groupsSubscription?.cancel();
      for (final sub in groupSubscriptions.values) {
        sub.cancel();
      }
      groupSubscriptions.clear();
      groupRequests.clear();
    };

    return controller.stream;
  }

  // ─── Notifications ────────────────────────────────────────────────────────

  Future<void> createNotification({
    required String userEmail,
    required String title,
    required String body,
    Map<String, dynamic>? extraData,
  }) async {
    await _firestore
        .collection('notifications')
        .doc(userEmail)
        .collection('userNotifications')
        .add({
          'title': title,
          'body': body,
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
          if (extraData != null) ...extraData,
        });
  }

  Stream<QuerySnapshot> notificationsForUser(String userEmail) {
    return _firestore
        .collection('notifications')
        .doc(userEmail)
        .collection('userNotifications')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> markNotificationAsRead(String userEmail, String notifId) async {
    await _firestore
        .collection('notifications')
        .doc(userEmail)
        .collection('userNotifications')
        .doc(notifId)
        .update({'isRead': true});
  }

  // ─── Users ────────────────────────────────────────────────────────────────

  Future<void> updateUserProfile({
    required String uid,
    required String email,
    required String displayName,
    String? photoUrl,
    String? role,
  }) async {
    final docRef = _firestore.collection('users').doc(uid);
    final docSnap = await docRef.get();
    
    final Map<String, dynamic> data = {
      'email': email.trim().toLowerCase(),
      'displayName': displayName.trim(),
      'photoUrl': photoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (!docSnap.exists) {
      final cleanEmail = email.trim().toLowerCase();
      // Auto-assign admin if email matches admin rules
      data['role'] = (cleanEmail.startsWith('admin@') || cleanEmail.endsWith('admin@proyecto.com')) ? 'admin' : 'user';
    } else if (role != null) {
      data['role'] = role;
    }

    await docRef.set(data, SetOptions(merge: true));
  }

  Future<DocumentSnapshot> getUserProfile(String uid) {
    return _firestore.collection('users').doc(uid).get();
  }

  Stream<DocumentSnapshot> userProfileStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots();
  }

  Stream<List<Map<String, dynamic>>> getAllUsersStream() {
    return _firestore.collection('users').snapshots().map((snap) {
      return snap.docs.map((doc) {
        final data = doc.data();
        data['uid'] = doc.id;
        return data;
      }).toList();
    });
  }

  Stream<List<GroupModel>> getAllGroupsStream() {
    return _firestore.collection('groups').snapshots().map((snap) {
      return snap.docs.map((doc) => GroupModel.fromMap(doc.id, doc.data())).toList();
    });
  }

  Future<void> updateUserRole(String uid, String role) async {
    await _firestore.collection('users').doc(uid).update({'role': role});
  }

  Future<void> deleteUser(String uid) async {
    await _firestore.collection('users').doc(uid).delete();
  }

  Future<DocumentSnapshot?> getUserProfileByEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    final rawEmail = email.trim();

    var query = await _firestore
        .collection('users')
        .where('email', isEqualTo: cleanEmail)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return query.docs.first;
    }

    if (cleanEmail != rawEmail) {
      query = await _firestore
          .collection('users')
          .where('email', isEqualTo: rawEmail)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        return query.docs.first;
      }
    }

    return null;
  }

  // --- Friends -----------------------------------------------------------

  /// Envia una solicitud de amistad. Lanza excepcion si ya existe una relacion.
  Future<void> sendFriendRequest({
    required String fromEmail,
    required String toEmail,
  }) async {
    final from = fromEmail.trim().toLowerCase();
    final to = toEmail.trim().toLowerCase();

    if (from == to) throw Exception('No puedes agregarte a ti mismo.');

    // Verificar si ya existe solicitud o amistad en cualquier direccion
    final existing = await _firestore
        .collection('friend_requests')
        .where('fromEmail', isEqualTo: from)
        .where('toEmail', isEqualTo: to)
        .limit(1)
        .get();

    final existingReverse = await _firestore
        .collection('friend_requests')
        .where('fromEmail', isEqualTo: to)
        .where('toEmail', isEqualTo: from)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty || existingReverse.docs.isNotEmpty) {
      throw Exception('Ya existe una solicitud o amistad con este usuario.');
    }

    // Verificar que el usuario destino existe
    final userDoc = await getUserProfileByEmail(to);
    if (userDoc == null) {
      throw Exception('No se encontro ningun usuario con ese correo.');
    }

    await _firestore.collection('friend_requests').add({
      'fromEmail': from,
      'toEmail': to,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Acepta o rechaza una solicitud de amistad.
  Future<void> respondFriendRequest({
    required String requestId,
    required bool accept,
  }) async {
    await _firestore.collection('friend_requests').doc(requestId).update({
      'status': accept ? 'accepted' : 'rejected',
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Elimina una relación de amistad entre dos usuarios.
  Future<void> removeFriend({
    required String userEmail,
    required String friendEmail,
  }) async {
    final emailA = userEmail.trim().toLowerCase();
    final emailB = friendEmail.trim().toLowerCase();

    final query1 = await _firestore
        .collection('friend_requests')
        .where('fromEmail', isEqualTo: emailA)
        .where('toEmail', isEqualTo: emailB)
        .get();

    final query2 = await _firestore
        .collection('friend_requests')
        .where('fromEmail', isEqualTo: emailB)
        .where('toEmail', isEqualTo: emailA)
        .get();

    final batch = _firestore.batch();
    for (var doc in query1.docs) {
      batch.delete(doc.reference);
    }
    for (var doc in query2.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// Stream de amigos aceptados del usuario (en ambas direcciones).
  Stream<List<FriendRequest>> friendsStream(String userEmail) {
    final email = userEmail.trim().toLowerCase();
    final rawEmail = userEmail.trim();

    final sentStream1 = _firestore
        .collection('friend_requests')
        .where('fromEmail', isEqualTo: email)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .map(
          (s) =>
              s.docs.map((d) => FriendRequest.fromMap(d.id, d.data())).toList(),
        );

    final sentStream2 = rawEmail != email
        ? _firestore
            .collection('friend_requests')
            .where('fromEmail', isEqualTo: rawEmail)
            .where('status', isEqualTo: 'accepted')
            .snapshots()
            .map(
              (s) =>
                  s.docs.map((d) => FriendRequest.fromMap(d.id, d.data())).toList(),
            )
        : Stream<List<FriendRequest>>.value([]);

    final receivedStream1 = _firestore
        .collection('friend_requests')
        .where('toEmail', isEqualTo: email)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .map(
          (s) =>
              s.docs.map((d) => FriendRequest.fromMap(d.id, d.data())).toList(),
        );

    final receivedStream2 = rawEmail != email
        ? _firestore
            .collection('friend_requests')
            .where('toEmail', isEqualTo: rawEmail)
            .where('status', isEqualTo: 'accepted')
            .snapshots()
            .map(
              (s) =>
                  s.docs.map((d) => FriendRequest.fromMap(d.id, d.data())).toList(),
            )
        : Stream<List<FriendRequest>>.value([]);

    final controller = StreamController<List<FriendRequest>>.broadcast();
    List<FriendRequest> lastSent1 = [];
    List<FriendRequest> lastSent2 = [];
    List<FriendRequest> lastReceived1 = [];
    List<FriendRequest> lastReceived2 = [];
    StreamSubscription? subSent1;
    StreamSubscription? subSent2;
    StreamSubscription? subReceived1;
    StreamSubscription? subReceived2;
    List<FriendRequest>? lastEmitted;
    bool hasEmitted = false;

    void emit() {
      if (controller.isClosed) return;
      final map = <String, FriendRequest>{};
      for (final r in [...lastSent1, ...lastSent2, ...lastReceived1, ...lastReceived2]) {
        map[r.id] = r;
      }
      final result = map.values.toList();
      lastEmitted = result;
      hasEmitted = true;
      controller.add(result);
    }

    controller.onListen = () {
      subSent1 = sentStream1.listen((list) {
        lastSent1 = list;
        emit();
      }, onError: controller.addError);

      if (rawEmail != email) {
        subSent2 = sentStream2.listen((list) {
          lastSent2 = list;
          emit();
        }, onError: controller.addError);
      }

      subReceived1 = receivedStream1.listen((list) {
        lastReceived1 = list;
        emit();
      }, onError: controller.addError);

      if (rawEmail != email) {
        subReceived2 = receivedStream2.listen((list) {
          lastReceived2 = list;
          emit();
        }, onError: controller.addError);
      }
    };

    controller.onCancel = () {
      subSent1?.cancel();
      subSent2?.cancel();
      subReceived1?.cancel();
      subReceived2?.cancel();
    };

    return Stream<List<FriendRequest>>.multi((multiController) {
      if (hasEmitted && lastEmitted != null) {
        multiController.add(lastEmitted!);
      }
      final sub = controller.stream.listen(
        multiController.add,
        onError: multiController.addError,
        onDone: multiController.close,
      );
      multiController.onCancel = () => sub.cancel();
    });
  }

  /// Stream de solicitudes de amistad pendientes recibidas por el usuario.
  Stream<List<FriendRequest>> pendingFriendRequestsStream(String userEmail) {
    final email = userEmail.trim().toLowerCase();
    final rawEmail = userEmail.trim();

    final stream1 = _firestore
        .collection('friend_requests')
        .where('toEmail', isEqualTo: email)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) => s.docs.map((d) => FriendRequest.fromMap(d.id, d.data())).toList());

    final stream2 = rawEmail != email
        ? _firestore
            .collection('friend_requests')
            .where('toEmail', isEqualTo: rawEmail)
            .where('status', isEqualTo: 'pending')
            .snapshots()
            .map((s) => s.docs.map((d) => FriendRequest.fromMap(d.id, d.data())).toList())
        : Stream<List<FriendRequest>>.value([]);

    final controller = StreamController<List<FriendRequest>>.broadcast();
    List<FriendRequest> list1 = [];
    List<FriendRequest> list2 = [];
    StreamSubscription? sub1;
    StreamSubscription? sub2;
    List<FriendRequest>? lastEmitted;
    bool hasEmitted = false;

    void emit() {
      if (controller.isClosed) return;
      final map = <String, FriendRequest>{};
      for (final r in [...list1, ...list2]) {
        map[r.id] = r;
      }
      final sorted = map.values.toList();
      sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      lastEmitted = sorted;
      hasEmitted = true;
      controller.add(sorted);
    }

    controller.onListen = () {
      sub1 = stream1.listen((list) {
        list1 = list;
        emit();
      }, onError: controller.addError);

      if (rawEmail != email) {
        sub2 = stream2.listen((list) {
          list2 = list;
          emit();
        }, onError: controller.addError);
      }
    };

    controller.onCancel = () {
      sub1?.cancel();
      sub2?.cancel();
    };

    return Stream<List<FriendRequest>>.multi((multiController) {
      if (hasEmitted && lastEmitted != null) {
        multiController.add(lastEmitted!);
      }
      final sub = controller.stream.listen(
        multiController.add,
        onError: multiController.addError,
        onDone: multiController.close,
      );
      multiController.onCancel = () => sub.cancel();
    });
  }

  /// Obtiene la lista de solicitudes de amistad aceptadas de forma síncrona/única (one-shot).
  Future<List<FriendRequest>> getFriends(String userEmail) async {
    final email = userEmail.trim().toLowerCase();
    final rawEmail = userEmail.trim();

    // Query 1: sent requests (lowercase)
    final q1 = await _firestore
        .collection('friend_requests')
        .where('fromEmail', isEqualTo: email)
        .where('status', isEqualTo: 'accepted')
        .get();

    // Query 2: sent requests (raw)
    final q2 = rawEmail != email
        ? await _firestore
            .collection('friend_requests')
            .where('fromEmail', isEqualTo: rawEmail)
            .where('status', isEqualTo: 'accepted')
            .get()
        : null;

    // Query 3: received requests (lowercase)
    final q3 = await _firestore
        .collection('friend_requests')
        .where('toEmail', isEqualTo: email)
        .where('status', isEqualTo: 'accepted')
        .get();

    // Query 4: received requests (raw)
    final q4 = rawEmail != email
        ? await _firestore
            .collection('friend_requests')
            .where('toEmail', isEqualTo: rawEmail)
            .where('status', isEqualTo: 'accepted')
            .get()
        : null;

    final map = <String, FriendRequest>{};
    for (final doc in q1.docs) {
      map[doc.id] = FriendRequest.fromMap(doc.id, doc.data());
    }
    if (q2 != null) {
      for (final doc in q2.docs) {
        map[doc.id] = FriendRequest.fromMap(doc.id, doc.data());
      }
    }
    for (final doc in q3.docs) {
      map[doc.id] = FriendRequest.fromMap(doc.id, doc.data());
    }
    if (q4 != null) {
      for (final doc in q4.docs) {
        map[doc.id] = FriendRequest.fromMap(doc.id, doc.data());
      }
    }
    return map.values.toList();
  }

  /// Obtiene el perfil de usuario por correo electronico.
  Future<Map<String, dynamic>?> getUserDataByEmail(String email) async {
    final doc = await getUserProfileByEmail(email.trim().toLowerCase());
    if (doc == null) return null;
    return doc.data() as Map<String, dynamic>?;
  }
}
