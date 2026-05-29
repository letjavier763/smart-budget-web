import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:proyecto_app/models/friend_request.dart';
import 'package:proyecto_app/models/group.dart';
import 'package:proyecto_app/models/group_invitation.dart';
import 'package:proyecto_app/services/firestore_service.dart';
import 'package:proyecto_app/home/group_detail_screen.dart';
import 'package:proyecto_app/theme/translations.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:proyecto_app/widgets/group_avatar.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final _nameController = TextEditingController();
  final _joinCodeController = TextEditingController();
  final TextEditingController otherEmailController = TextEditingController();
  final _maxMembersController = TextEditingController();
  late final Stream<List<GroupModel>> _groupsStream;

  @override
  void initState() {
    super.initState();
    _groupsStream = _firestoreService.groupsForUser(_currentEmail);
    _checkPendingJoinCode();
  }

  Future<void> _checkPendingJoinCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('pending_join_code');
    if (code != null && code.isNotEmpty) {
      await prefs.remove('pending_join_code');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showAutoJoinDialog(code);
      });
    }
  }

  Future<void> _showAutoJoinDialog(String code) async {
    final infoFuture = (() async {
      // 1. Obtener detalles del grupo
      final group = await _firestoreService.getGroupByCode(code);
      if (group == null) {
        throw Exception(tr('No se encontró un grupo con ese código.', 'No group found with that code.'));
      }
      
      // 2. Obtener gastos del grupo
      final expenses = await _firestoreService.getExpensesForGroup(group.id);
      final expenseCount = expenses.length;
      final totalExpenses = expenses.fold<double>(0.0, (sum, e) => sum + e.amount);
      
      // 3. Verificar si existe una invitación personal pendiente para el usuario actual
      final invitationsSnap = await FirebaseFirestore.instance
          .collection('group_invitations')
          .where('groupId', isEqualTo: group.id)
          .where('toEmail', isEqualTo: _currentEmail)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();
      
      final bool hasPendingInvitation = invitationsSnap.docs.isNotEmpty;
      final String? invitationId = hasPendingInvitation ? invitationsSnap.docs.first.id : null;
      
      return {
        'group': group,
        'expenseCount': expenseCount,
        'totalExpenses': totalExpenses,
        'hasPendingInvitation': hasPendingInvitation,
        'invitationId': invitationId,
      };
    })();

    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return FutureBuilder<Map<String, dynamic>>(
          future: infoFuture,
          builder: (ctx2, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return AlertDialog(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(tr('Cargando detalles del grupo...', 'Loading group details...')),
                  ],
                ),
              );
            }

            if (snapshot.hasError) {
              return AlertDialog(
                title: Text(tr('Error', 'Error')),
                content: Text(snapshot.error.toString().replaceAll('Exception: ', '')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx2),
                    child: Text(tr('Entendido', 'Got it')),
                  ),
                ],
              );
            }

            final data = snapshot.data!;
            final GroupModel group = data['group'];
            final int expenseCount = data['expenseCount'];
            final double totalExpenses = data['totalExpenses'];
            final bool hasPendingInvitation = data['hasPendingInvitation'];
            final String? invitationId = data['invitationId'];

            final colorScheme = Theme.of(context).colorScheme;

            return AlertDialog(
              title: Column(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Icon(Icons.group, size: 28, color: colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    group.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${tr('Código', 'Code')}: ${group.code}',
                    style: TextStyle(fontSize: 12, color: colorScheme.outline, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    const SizedBox(height: 8),
                    // Mensaje de invitación
                    Text(
                      hasPendingInvitation
                          ? tr('¡Has recibido una invitación para unirte a este grupo!', 'You have received an invitation to join this group!')
                          : tr('¿Deseas enviar una solicitud para unirte a este grupo?', 'Do you want to send a request to join this group?'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: hasPendingInvitation ? Colors.purple : colorScheme.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    // Detalles de estado del grupo
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(tr('Miembros:', 'Members:'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              Text('${group.members.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(tr('Presupuesto:', 'Budget:'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              Text(
                                group.initialBudget != null
                                    ? 'Q${group.initialBudget!.toStringAsFixed(2)}'
                                    : tr('No definido', 'Not defined'),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(tr('Gastos totales:', 'Total expenses:'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              Text(
                                'Q${totalExpenses.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(tr('Total transacciones:', 'Total transactions:'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              Text('$expenseCount', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr('Lista de miembros:', 'Members list:'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 60),
                      child: SingleChildScrollView(
                        child: Text(
                          group.members.join(', '),
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (hasPendingInvitation) ...[
                  // Botón para Rechazar la Invitación
                  TextButton(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: ctx2,
                        builder: (confirmCtx) => AlertDialog(
                          title: Text(tr('Rechazar invitación', 'Reject invitation')),
                          content: Text(tr(
                            '¿Estás seguro de que deseas rechazar la invitación para unirte al grupo?',
                            'Are you sure you want to reject the invitation to join the group?',
                          )),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(confirmCtx, false),
                              child: Text(tr('No, cancelar', 'No, cancel')),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(confirmCtx, true),
                              child: Text(tr('Sí, rechazar', 'Yes, reject')),
                            ),
                          ],
                        ),
                      );

                      if (confirmed != true) return;

                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(ctx2);
                      try {
                        await _firestoreService.respondGroupInvitation(
                          invitationId: invitationId!,
                          accept: false,
                          groupId: group.id,
                          targetEmail: _currentEmail,
                        );
                        navigator.pop();
                        messenger.showSnackBar(
                          SnackBar(content: Text(tr('Invitación rechazada.', 'Invitation rejected.'))),
                        );
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('Error: $e')),
                        );
                      }
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: Text(tr('Rechazar', 'Reject')),
                  ),
                  // Botón para Aceptar la Invitación (se une de inmediato)
                  ElevatedButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(ctx2);
                      try {
                        await _firestoreService.respondGroupInvitation(
                          invitationId: invitationId!,
                          accept: true,
                          groupId: group.id,
                          targetEmail: _currentEmail,
                        );
                        navigator.pop();
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(tr('¡Te has unido al grupo exitosamente!', 'You have joined the group successfully!')),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('Error: $e')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(tr('Aceptar', 'Accept')),
                  ),
                ] else ...[
                  // Botón Cancelar (para código público)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx2),
                    child: Text(tr('Cancelar', 'Cancel')),
                  ),
                  // Botón para unirse (petición de unión)
                  ElevatedButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(ctx2);
                      try {
                        await _firestoreService.joinGroupByCode(
                          groupCode: code,
                          userEmail: _currentEmail,
                        );
                        navigator.pop();
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(tr('Solicitud enviada al administrador del grupo.', 'Request sent to the group administrator.')),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } catch (e) {
                        navigator.pop();
                        messenger.showSnackBar(
                          SnackBar(content: Text(tr('Error al unirse: $e', 'Error joining: $e'))),
                        );
                      }
                    },
                    child: Text(tr('Solicitar Unirse', 'Request to Join')),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _joinCodeController.dispose();
    otherEmailController.dispose();
    _maxMembersController.dispose();
    super.dispose();
  }

  String get _currentEmail =>
      FirebaseAuth.instance.currentUser?.email?.toLowerCase() ?? '';

  // -------------------------------------------------------------------------
  // Dialogo: crear grupo con selector de amigos
  // -------------------------------------------------------------------------
  Future<void> _showCreateGroupDialog() async {
    _nameController.clear();
    _maxMembersController.clear();
    final List<String> selectedEmails = [];
    String dialogSearchQuery = '';
    final TextEditingController dialogSearchController = TextEditingController();
    final TextEditingController budgetController = TextEditingController();
    DateTime? selectedActiveUntil;
    // New state for toggling view of other user's friends
    bool showOtherFriends = false;
    String otherUserEmail = '';
    final TextEditingController otherEmailController = TextEditingController();

    // Iniciar la carga de amigos y sus perfiles de forma paralela y asíncrona
    
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final colorScheme = Theme.of(ctx).colorScheme;

            return AlertDialog(
                title: Text(tr('Crear nuevo grupo', 'Create new group')),

              content: SizedBox(
                width: double.maxFinite,
                child: FutureBuilder<List<_FriendProfileCache>>(
                  // Compute friends dynamically based on current dialog state
                  future: (() async {
                    List<_FriendProfileCache> combinedCaches = [];
                    Future<List<_FriendProfileCache>> buildCaches(List<FriendRequest> list) async {
                      final List<Future<_FriendProfileCache>> futures = list.map((req) async {
                        final cleanFrom = req.fromEmail.trim().toLowerCase();
                        final cleanTo = req.toEmail.trim().toLowerCase();
                        final cleanCurrent = _currentEmail.trim().toLowerCase();
                        final friendEmail = cleanFrom == cleanCurrent ? cleanTo : cleanFrom;
                        final userData = await _firestoreService.getUserDataByEmail(friendEmail);
                        final name = userData?['displayName'] as String? ?? friendEmail.split('@')[0];
                        final photoUrl = userData?['photoUrl'] as String?;
                        return _FriendProfileCache(email: friendEmail, name: name, photoUrl: photoUrl);
                      }).toList();
                      return Future.wait(futures);
                    }

                    // Current user's friends
                    try {
                      final myFriends = await _firestoreService.getFriends(_currentEmail);
                      combinedCaches.addAll(await buildCaches(myFriends));
                    } catch (_) {}

                    // Other user's friends if toggled and email provided
                    if (showOtherFriends && otherUserEmail.trim().isNotEmpty) {
                      try {
                        final otherFriends = await _firestoreService.getFriends(otherUserEmail);
                        final otherCaches = await buildCaches(otherFriends);
                        for (var cache in otherCaches) {
                          if (!combinedCaches.any((c) => c.email == cache.email)) {
                            combinedCaches.add(cache);
                          }
                        }
                      } catch (_) {}
                    }
                    return combinedCaches;
                  })(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (snapshot.hasError) {
                      return SizedBox(
                        height: 100,
                        child: Center(
                          child: Text('${tr('Error al cargar amigos', 'Error loading friends')}: ${snapshot.error}'),
                        ),
                      );
                    }

                    final friends = snapshot.data ?? [];
                    final filteredFriends = friends.where((friend) {
                      final query = dialogSearchQuery.trim().toLowerCase();
                      return friend.name.toLowerCase().contains(query) ||
                             friend.email.toLowerCase().contains(query);
                    }).toList();

                    return SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: tr('Nombre del grupo', 'Group name'),
                              prefixIcon: const Icon(Icons.group_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _maxMembersController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: tr('Capacidad máxima de miembros (opcional)', 'Max member capacity (optional)'),
                              prefixIcon: const Icon(Icons.person_add_alt_1_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: budgetController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: tr('Presupuesto inicial (opcional)', 'Initial budget (optional)'),
                              prefixIcon: const Icon(Icons.monetization_on_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.timer_outlined),
                            title: Text(
                              selectedActiveUntil == null
                                  ? tr('Tiempo de actividad (opcional)', 'Activity duration (optional)')
                                  : '${tr('Activo hasta', 'Active until')}: ${selectedActiveUntil!.day}/${selectedActiveUntil!.month}/${selectedActiveUntil!.year}',
                            ),
                            trailing: TextButton(
                              onPressed: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now().add(const Duration(days: 7)),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                                );
                                if (date != null) {
                                  setDialogState(() {
                                    selectedActiveUntil = date;
                                  });
                                }
                              },
                              child: Text(tr('Seleccionar', 'Select')),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                          tr('Agregar amigos al grupo', 'Add friends to the group'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Toggle between my friends and another user's friends
                        Row(
                          children: [
                            ChoiceChip(
                              label: Text(tr('Mis amigos', 'My friends')),
                              selected: !showOtherFriends,
                              onSelected: (val) {
                                setDialogState(() {
                                  showOtherFriends = !val;
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: Text(tr('Amigos de otro', 'Other user\'s friends')),
                              selected: showOtherFriends,
                              onSelected: (val) {
                                setDialogState(() {
                                  showOtherFriends = val;
                                });
                              },
                            ),
                          ],
                        ),
                        if (showOtherFriends) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: otherEmailController,
                            decoration: InputDecoration(
                              hintText: tr('Correo del otro usuario', 'Other user email'),
                              prefixIcon: const Icon(Icons.person),
                            ),
                            onChanged: (val) {
                              setDialogState(() {
                                otherUserEmail = val;
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                          const SizedBox(height: 8),

                          if (friends.isNotEmpty) ...[
                            TextField(
                              controller: dialogSearchController,
                              onChanged: (val) {
                                setDialogState(() {
                                  dialogSearchQuery = val;
                                });
                              },
                              decoration: InputDecoration(
                                hintText: tr('Buscar amigo por nombre o correo...', 'Search friend by name or email...'),
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: dialogSearchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          dialogSearchController.clear();
                                          setDialogState(() {
                                            dialogSearchQuery = '';
                                          });
                                        },
                                      )
                                    : null,
                                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],

                          // Lista de amigos con checkbox
                          if (friends.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 18,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      tr('No tienes amigos agregados. Ve a la pestaña Amigos para agregar.', 'You have no friends added. Go to the Friends tab to add some.'),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (filteredFriends.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text(
                                  tr('No se encontraron amigos.', 'No friends found.'),
                                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                                ),
                              ),
                            )
                          else
                            ...filteredFriends.map((friend) {
                              final isSelected = selectedEmails.contains(friend.email);
                              return _FriendCheckboxTile(
                                friend: friend,
                                isSelected: isSelected,
                                onChanged: (value) {
                                  setDialogState(() {
                                    if (value == true) {
                                      selectedEmails.add(friend.email);
                                    } else {
                                      selectedEmails.remove(friend.email);
                                    }
                                  });
                                },
                              );
                            }),
                        ],
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    dialogSearchController.dispose();
                    budgetController.dispose();
                    Navigator.pop(ctx);
                  },
                  child: Text(tr('Cancelar', 'Cancel')),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(ctx);

                    if (_nameController.text.trim().isEmpty) {
                      messenger.showSnackBar(
                        SnackBar(
                            content: Text(tr('Ingresa un nombre para el grupo.', 'Enter a group name.'))),
                      );
                      return;
                    }

                    final maxMembersText = _maxMembersController.text.trim();
                    final maxMembers = maxMembersText.isNotEmpty ? int.tryParse(maxMembersText) : null;
                    if (maxMembers != null && maxMembers <= 0) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            tr(
                              'La capacidad máxima debe ser un número mayor a 0.',
                              'Max capacity must be a number greater than 0.',
                            ),
                          ),
                        ),
                      );
                      return;
                    }

                    final budgetText = budgetController.text.trim();
                    final budget = budgetText.isNotEmpty
                        ? double.tryParse(budgetText.replaceAll(',', '.'))
                        : null;

                    await _firestoreService.createSharedGroup(
                      name: _nameController.text.trim(),
                      members: selectedEmails,
                      createdBy: _currentEmail,
                      maxMembers: maxMembers,
                      initialBudget: budget,
                      activeUntil: selectedActiveUntil,
                    );

                    dialogSearchController.dispose();
                    budgetController.dispose();
                    if (!mounted) return;
                    navigator.pop();
                  },
                  child: Text(tr('Crear', 'Create')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // Dialogo: unirse a un grupo
  // -------------------------------------------------------------------------
  Future<void> _showJoinGroupDialog() async {
    _joinCodeController.clear();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(tr('Unirse a un grupo', 'Join a group')),
          content: TextField(
            controller: _joinCodeController,
            decoration: InputDecoration(
              labelText: tr('Código del grupo', 'Group code'),
              hintText: '${tr('Ej', 'e.g.')}. ABCD1234',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Cancelar', 'Cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                final code = _joinCodeController.text.trim();
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                if (code.isEmpty) {
                  messenger.showSnackBar(
                    SnackBar(
                        content: Text(tr('Ingresa el código del grupo.', 'Enter the group code.'))),
                  );
                  return;
                }

                try {
                  await _firestoreService.joinGroupByCode(
                    groupCode: code,
                    userEmail: _currentEmail,
                  );
                  if (!mounted) return;
                  navigator.pop();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(tr('Solicitud enviada al administrador del grupo.', 'Request sent to the group administrator.')),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(content: Text(tr('Error al unirse: $e', 'Error joining: $e'))),
                  );
                }
              },
              child: Text(tr('Unirse', 'Join')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteGroup(BuildContext context, GroupModel group) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Eliminar Grupo', 'Delete Group')),
        content: Text(tr(
          '¿Estás seguro de que deseas eliminar este grupo? Esta acción borrará todos los gastos y solicitudes.',
          'Are you sure you want to delete this group? This action will delete all expenses and requests.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancelar', 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Eliminar', 'Delete'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _firestoreService.deleteGroup(groupId: group.id);
        messenger.showSnackBar(
          SnackBar(content: Text(tr('Grupo eliminado exitosamente.', 'Group deleted successfully.'))),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('${tr('Error al eliminar', 'Error deleting')}: $e')),
        );
      }
    }
  }

  Future<void> _confirmLeaveGroup(BuildContext context, GroupModel group) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Salir del Grupo', 'Leave Group')),
        content: Text(tr(
          '¿Estás seguro de que deseas salir de este grupo?',
          'Are you sure you want to leave this group?',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancelar', 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Salir', 'Leave'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _firestoreService.removeMemberFromGroup(
          groupId: group.id,
          memberEmail: _currentEmail,
        );
        messenger.showSnackBar(
          SnackBar(content: Text(tr('Saliste del grupo.', 'Left the group.'))),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('${tr('Error al salir', 'Error leaving')}: $e')),
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = _currentEmail;

    if (email.isEmpty) {
      return Center(child: Text(tr('Usuario no autenticado', 'User not authenticated')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Mis Grupos', 'My Groups'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showJoinGroupDialog,
            tooltip: tr('Unirse a un grupo', 'Join a group'),
          )
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _PendingInvitationsList(service: _firestoreService, email: email),
            Expanded(
              child: StreamBuilder<List<GroupModel>>(
                stream: _groupsStream,
                builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                  child:
                      Text('${tr('Error al cargar grupos', 'Error loading groups')}: ${snapshot.error}'));
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final groups = snapshot.data ?? [];
            if (groups.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.group_off_outlined,
                          size: 64,
                          color: theme.colorScheme.outlineVariant),
                      const SizedBox(height: 16),
                      Text(
                        tr('No tienes grupos todavía.', 'You have no groups yet.'),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr('Úsalos para dividir gastos y ver tus saldos con amigos.', 'Use them to split expenses and see your balances with friends.'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              itemCount: groups.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final group = groups[index];
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GroupDetailScreen(group: group),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          GroupAvatar(group: group, size: 48),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        group.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (group.createdBy == _currentEmail) ...[
                                      const SizedBox(width: 8),
                                      StreamBuilder<List<GroupInvitation>>(
                                        stream: _firestoreService.pendingJoinRequestsStream(group.id),
                                        builder: (context, invSnap) {
                                          final count = invSnap.data?.length ?? 0;
                                          if (count == 0) return const SizedBox.shrink();
                                          return Container(
                                            alignment: Alignment.center,
                                            padding: const EdgeInsets.all(5),
                                            decoration: const BoxDecoration(
                                              color: Colors.orange,
                                              shape: BoxShape.circle,
                                            ),
                                            constraints: const BoxConstraints(
                                              minWidth: 20,
                                              minHeight: 20,
                                            ),
                                            child: Text(
                                              '$count',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  group.maxMembers != null
                                      ? tr(
                                          '${group.members.length} / ${group.maxMembers} miembros',
                                          '${group.members.length} / ${group.maxMembers} members',
                                        )
                                      : tr(
                                          '${group.members.length} miembros',
                                          '${group.members.length} members',
                                        ),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color:
                                        theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert,
                                color: theme.colorScheme.onSurface),
                            onSelected: (value) {
                              if (value == 'details') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => GroupDetailScreen(group: group),
                                  ),
                                );
                              } else if (value == 'copy') {
                                Clipboard.setData(ClipboardData(text: group.code));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(tr('Código copiado.', 'Code copied.'))),
                                );
                              } else if (value == 'leave') {
                                _confirmLeaveGroup(context, group);
                              } else if (value == 'delete') {
                                _confirmDeleteGroup(context, group);
                              }
                            },
                            itemBuilder: (ctx) {
                              final isCreator = group.createdBy == _currentEmail;
                              return [
                                PopupMenuItem(
                                  value: 'details',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.info_outline),
                                      const SizedBox(width: 12),
                                      Text(tr('Ver detalles', 'View details')),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'copy',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.copy),
                                      const SizedBox(width: 12),
                                      Text(tr('Copiar código', 'Copy code')),
                                    ],
                                  ),
                                ),
                                if (!isCreator)
                                  PopupMenuItem(
                                    value: 'leave',
                                    child: Row(
                                      children: [
                                        Icon(Icons.exit_to_app, color: theme.colorScheme.error),
                                        const SizedBox(width: 12),
                                        Text(
                                          tr('Salir del grupo', 'Leave group'),
                                          style: TextStyle(color: theme.colorScheme.error),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (isCreator)
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
                                        const SizedBox(width: 12),
                                        Text(
                                          tr('Eliminar grupo', 'Delete group'),
                                          style: TextStyle(color: theme.colorScheme.error),
                                        ),
                                      ],
                                    ),
                                  ),
                              ];
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_groups',
        onPressed: _showCreateGroupDialog,
        icon: const Icon(Icons.add),
        label: Text(tr('Nuevo Grupo', 'New Group')),
      ),
    );
  }
}

// =============================================================================
// Widget: checkbox tile para seleccionar amigo al crear grupo
// =============================================================================
class _FriendProfileCache {
  final String email;
  final String name;
  final String? photoUrl;

  _FriendProfileCache({
    required this.email,
    required this.name,
    this.photoUrl,
  });
}

class _FriendCheckboxTile extends StatelessWidget {
  final _FriendProfileCache friend;
  final bool isSelected;
  final ValueChanged<bool?> onChanged;

  const _FriendCheckboxTile({
    required this.friend,
    required this.isSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: isSelected,
      onChanged: onChanged,
      controlAffinity: ListTileControlAffinity.leading,
      secondary: CircleAvatar(
        radius: 18,
        backgroundColor: colorScheme.primaryContainer,
        backgroundImage: friend.photoUrl != null
            ? MemoryImage(base64Decode(friend.photoUrl!))
            : null,
        child: friend.photoUrl == null
            ? Text(
                friend.name.isNotEmpty ? friend.name.substring(0, 1).toUpperCase() : '?',
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      ),
      title: Text(friend.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(friend.email,
          style: TextStyle(
              fontSize: 11, color: colorScheme.onSurfaceVariant)),
    );
  }
}

// =============================================================================
// Widget: Lista de invitaciones pendientes
// =============================================================================
class _PendingInvitationsList extends StatelessWidget {
  final FirestoreService service;
  final String email;

  const _PendingInvitationsList({required this.service, required this.email});

  @override
  Widget build(BuildContext context) {
    if (email.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<List<GroupInvitation>>(
      stream: service.pendingGroupInvitationsStream(email),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final invitations = snap.data!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                tr('Invitaciones de Grupo (${invitations.length})', 'Group Invitations (${invitations.length})'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: invitations.length,
              itemBuilder: (context, index) {
                final inv = invitations[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.group_add)),
                    title: Text(inv.groupName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(tr('Invitado por ${inv.fromEmail.split('@')[0]}', 'Invited by ${inv.fromEmail.split('@')[0]}')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (confirmCtx) => AlertDialog(
                                title: Text(tr('Rechazar invitación', 'Reject invitation')),
                                content: Text('${tr('¿Estás seguro de que deseas rechazar la invitación al grupo', 'Are you sure you want to reject the invitation to the group')} "${inv.groupName}"?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(confirmCtx, false),
                                    child: Text(tr('No, cancelar', 'No, cancel')),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () => Navigator.pop(confirmCtx, true),
                                    child: Text(tr('Sí, rechazar', 'Yes, reject')),
                                  ),
                                ],
                              ),
                            );

                            if (confirmed == true) {
                              try {
                                await service.respondGroupInvitation(
                                  invitationId: inv.id,
                                  accept: false,
                                  groupId: inv.groupId,
                                  targetEmail: email,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(tr('Invitación rechazada.', 'Invitation rejected.'))),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
                                  );
                                }
                              }
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: () => service.respondGroupInvitation(
                            invitationId: inv.id,
                            accept: true,
                            groupId: inv.groupId,
                            targetEmail: email,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
