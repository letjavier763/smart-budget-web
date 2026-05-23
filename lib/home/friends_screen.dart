import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/friend_request.dart';
import '../models/expense.dart';
import '../models/group.dart';
import '../services/firestore_service.dart';
import '../theme/translations.dart';
import 'package:flutter/services.dart';


class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _service = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  bool _useCode = false; // toggle between email and code input
  String? _myFriendCode; // holds the user's own friend code
  late final TabController _tabController;
  late final Stream<List<FriendRequest>> _pendingRequestsStream;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _pendingRequestsStream = _service.pendingFriendRequestsStream(_currentEmail);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  String get _currentEmail =>
      FirebaseAuth.instance.currentUser?.email?.toLowerCase() ?? '';

  // -------------------------------------------------------------------------
  // Dialogo: agregar amigo
  // -------------------------------------------------------------------------
  Future<void> _showAddFriendDialog() async {
    _searchController.clear();
    // Load current user's friend code if needed
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final code = await _service.getFriendCodeByUid(uid);
      if (!mounted) return;
      setState(() => _myFriendCode = code);
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        bool loading = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(tr('Agregar amigo', 'Add friend')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Toggle between email and code mode
                  SwitchListTile(
                    title: Text(_useCode ? tr('Usar código', 'Use Code') : tr('Usar correo', 'Use Email')),
                    value: _useCode,
                    onChanged: (val) {
                      setDialogState(() {
                        _useCode = val;
                        _searchController.clear();
                      });
                    },
                  ),
                  if (_useCode) ...[
                    // Show own friend code with copy & regenerate
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: TextEditingController(text: _myFriendCode ?? ''),
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: tr('Tu código de amigo', 'Your friend code'),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.copy),
                                onPressed: () {
                                  if (_myFriendCode != null) {
                                    Clipboard.setData(ClipboardData(text: _myFriendCode!));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(tr('Código copiado', 'Code copied'))),
                                    );
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: tr('Regenerar código', 'Regenerate code'),
                          onPressed: loading
                              ? null
                              : () async {
                                  if (uid == null) return;
                                  setDialogState(() => loading = true);
                                  final newCode = await _service.regenerateFriendCode(uid);
                                  setState(() => _myFriendCode = newCode);
                                  setDialogState(() => loading = false);
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Input friend code to add
                    TextField(
                      controller: _searchController,
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                        labelText: tr('Código del amigo', 'Friend code'),
                        hintText: tr('AB12CD34', 'AB12CD34'),
                        prefixIcon: const Icon(Icons.vpn_key),
                      ),
                    ),
                  ] else ...[
                    // Email input mode (original)
                    TextField(
                      controller: _searchController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: tr('Correo del usuario', 'User email'),
                        hintText: tr('ejemplo@correo.com', 'example@email.com'),
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
                  ],
                  if (loading) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ]
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('Cancelar', 'Cancel')),
                ),
                ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          setDialogState(() => loading = true);
                          final messenger = ScaffoldMessenger.of(ctx);
                          try {
                            if (_useCode) {
                              final code = _searchController.text.trim();
                              if (code.isEmpty) throw Exception(tr('Introduce un código', 'Enter a code'));
                              final uidFromCode = await _service.getUidByFriendCode(code);
                              if (uidFromCode == null) throw Exception(tr('Código no encontrado', 'Code not found'));
                              final email = await _service.getEmailByUid(uidFromCode);
                              if (email == null) throw Exception(tr('Correo no encontrado', 'Email not found'));
                              await _service.sendFriendRequest(fromEmail: _currentEmail, toEmail: email);
                            } else {
                              final email = _searchController.text.trim();
                              if (email.isEmpty) throw Exception(tr('Introduce un correo', 'Enter an email'));
                              await _service.sendFriendRequest(fromEmail: _currentEmail, toEmail: email);
                            }
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            messenger.showSnackBar(
                              SnackBar(content: Text(tr('Solicitud enviada correctamente.', 'Request sent successfully.'))),
                            );
                          } catch (e) {
                            setDialogState(() => loading = false);
                            messenger.showSnackBar(
                              SnackBar(content: Text(e.toString())),
                            );
                          }
                        },
                  child: Text(tr('Agregar', 'Add')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // Dialogo: perfil de amigo con grupos en comun
  // -------------------------------------------------------------------------
  void _showFriendProfile(BuildContext context, String friendEmail) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: _FriendProfileSheet(
          friendEmail: friendEmail,
          currentEmail: _currentEmail,
          service: _service,
          scrollController: ScrollController(),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Amigos', 'Friends'), style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: tr('Mis amigos', 'My friends')),
            Tab(
              child: StreamBuilder<List<FriendRequest>>(
                stream: _pendingRequestsStream,
                builder: (context, snap) {
                  final count = snap.data?.length ?? 0;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tr('Solicitudes', 'Requests')),
                      if (count > 0) ...[
                        const SizedBox(width: 6),
                        Badge(
                          label: Text('$count'),
                        ),
                      ]
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ---- Tab 1: Lista de amigos ----
          _FriendsListTab(
            currentEmail: _currentEmail,
            service: _service,
            onTapFriend: _showFriendProfile,
          ),

          // ---- Tab 2: Solicitudes pendientes ----
          _PendingRequestsTab(
            currentEmail: _currentEmail,
            service: _service,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_friends',
        onPressed: _showAddFriendDialog,
        icon: const Icon(Icons.person_add_outlined),
        label: Text(tr('Agregar amigo', 'Add friend')),
      ),
    );
  }
}



// =============================================================================
// Widget: tile de solicitud pendiente (aceptar / rechazar)
// =============================================================================
class _PendingRequestTile extends StatelessWidget {
  final FriendRequest request;
  final FirestoreService service;
  final BuildContext context;

  const _PendingRequestTile({
    required this.request,
    required this.service,
    required this.context,
  });

  @override
  Widget build(BuildContext buildCtx) {
    final theme = Theme.of(buildCtx);
    final colorScheme = theme.colorScheme;
    final email = request.fromEmail;

    return FutureBuilder<Map<String, dynamic>?>(
      future: service.getUserDataByEmail(email),
      builder: (buildCtx, snap) {
        final data = snap.data;
        final name = data?['displayName'] as String? ?? email.split('@')[0];
        final photoUrl = data?['photoUrl'] as String?;

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: colorScheme.secondaryContainer,
                  backgroundImage: photoUrl != null
                      ? MemoryImage(base64Decode(photoUrl))
                      : null,
                  child: photoUrl == null
                      ? Text(
                          name.substring(0, 1).toUpperCase(),
                          style: TextStyle(
                            color: colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.close, color: colorScheme.error),
                      tooltip: tr('Rechazar', 'Reject'),
                      onPressed: () async {
                        await service.respondFriendRequest(
                          requestId: request.id,
                          accept: false,
                        );
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.check, color: colorScheme.primary),
                      tooltip: tr('Aceptar', 'Accept'),
                      onPressed: () async {
                        await service.respondFriendRequest(
                          requestId: request.id,
                          accept: true,
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FriendProfileData {
  final Map<String, dynamic>? userData;
  final List<GroupModel> commonGroups;
  final double netBalance;

  _FriendProfileData({
    required this.userData,
    required this.commonGroups,
    required this.netBalance,
  });
}

class _FriendProfileSheet extends StatelessWidget {
  final String friendEmail;
  final String currentEmail;
  final FirestoreService service;
  final ScrollController scrollController;

  const _FriendProfileSheet({
    required this.friendEmail,
    required this.currentEmail,
    required this.service,
    required this.scrollController,
  });

  Future<_FriendProfileData> _loadData() async {
    final userData = await service.getUserDataByEmail(friendEmail);
    final myGroups = await service.getGroupsForUser(currentEmail);
    final friendGroups = await service.getGroupsForUser(friendEmail);
    final friendGroupIds = friendGroups.map((g) => g.id).toSet();
    final commonGroups =
        myGroups.where((g) => friendGroupIds.contains(g.id)).toList();

    // Fetch all expenses in common groups to calculate net debt
    final List<List<Expense>> groupsExpenses = await Future.wait(
      commonGroups.map((g) => service.getExpensesForGroup(g.id))
    );

    double netBalance = 0.0;
    final cleanCurrentEmail = currentEmail.trim().toLowerCase();
    final cleanFriendEmail = friendEmail.trim().toLowerCase();

    for (int i = 0; i < commonGroups.length; i++) {
      final group = commonGroups[i];
      final expenses = groupsExpenses[i];

      for (final expense in expenses) {
        final cleanPaidBy = expense.paidBy.trim().toLowerCase();
        final cleanPaidTo = expense.paidTo?.trim().toLowerCase();

        if (expense.type == 'payment') {
          if (cleanPaidBy == cleanCurrentEmail && cleanPaidTo == cleanFriendEmail) {
            netBalance += expense.amount;
          } else if (cleanPaidBy == cleanFriendEmail && cleanPaidTo == cleanCurrentEmail) {
            netBalance -= expense.amount;
          }
        } else {
          final involved = expense.involvedMembers.isNotEmpty
              ? expense.involvedMembers.map((m) => m.trim().toLowerCase()).toList()
              : group.members.map((m) => m.trim().toLowerCase()).toList();

          final splitCount = involved.length;
          if (splitCount > 0) {
            final share = expense.amount / splitCount;
            if (cleanPaidBy == cleanCurrentEmail) {
              if (involved.contains(cleanFriendEmail)) {
                netBalance += share;
              }
            } else if (cleanPaidBy == cleanFriendEmail) {
              if (involved.contains(cleanCurrentEmail)) {
                netBalance -= share;
              }
            }
          }
        }
      }
    }

    return _FriendProfileData(
      userData: userData,
      commonGroups: commonGroups,
      netBalance: netBalance,
    );
  }

  Future<void> _confirmRemoveFriend(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.error,
        title: Text(
          tr('Eliminar amigo', 'Remove Friend'),
          style: TextStyle(color: Theme.of(context).colorScheme.onError),
        ),
        content: Text(tr(
          '¿Estás seguro de que deseas eliminar a esta persona de tus amigos?',
          'Are you sure you want to remove this person from your friends?',
        ),
            style: TextStyle(color: Theme.of(context).colorScheme.onError)
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancelar', 'Cancel'),
                style: TextStyle(color: Theme.of(context).colorScheme.onError)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              tr('Eliminar', 'Delete'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await service.removeFriend(
          userEmail: currentEmail,
          friendEmail: friendEmail,
        );
        if (!context.mounted) return;
        Navigator.pop(context); // close bottom sheet
        messenger.showSnackBar(
          SnackBar(
            content: Text(tr(
              'Amigo eliminado correctamente.',
              'Friend removed successfully.',
            )),
          ),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(tr('Error al eliminar amigo: $e', 'Error removing friend: $e'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FutureBuilder<_FriendProfileData>(
      future: _loadData(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snap.data;
        final userData = data?.userData;
        final commonGroups = data?.commonGroups ?? [];
        final name = userData?['displayName'] as String? ??
            friendEmail.split('@')[0];
        final photoUrl = userData?['photoUrl'] as String?;

        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Avatar y nombre
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        icon: Icon(Icons.close, color: colorScheme.onSurfaceVariant),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
            Center(
              child: CircleAvatar(
                radius: 40,
                backgroundColor: colorScheme.primaryContainer,
                backgroundImage: photoUrl != null
                    ? MemoryImage(base64Decode(photoUrl))
                    : null,
                child: photoUrl == null
                    ? Text(
                        name.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                name,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                friendEmail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Balance card
            Builder(
              builder: (context) {
                final balance = data?.netBalance ?? 0.0;
                Color cardColor;
                Color textColor;
                String balanceText;
                IconData balanceIcon;

                if (balance > 0.01) {
                  cardColor = colorScheme.primaryContainer.withValues(alpha: 0.15);
                  textColor = colorScheme.primary;
                  balanceText = tr(
                    'Te debe Q${balance.toStringAsFixed(2)}',
                    'Owes you Q${balance.toStringAsFixed(2)}',
                  );
                  balanceIcon = Icons.arrow_upward;
                } else if (balance < -0.01) {
                  cardColor = colorScheme.errorContainer.withValues(alpha: 0.15);
                  textColor = colorScheme.error;
                  balanceText = tr(
                    'Le debes Q${(-balance).toStringAsFixed(2)}',
                    'You owe them Q${(-balance).toStringAsFixed(2)}',
                  );
                  balanceIcon = Icons.arrow_downward;
                } else {
                  cardColor = colorScheme.outlineVariant.withValues(alpha: 0.15);
                  textColor = colorScheme.onSurfaceVariant;
                  balanceText = tr(
                    'Están a mano',
                    'You are all settled up',
                  );
                  balanceIcon = Icons.check_circle_outline;
                }

                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: textColor.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: textColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(balanceIcon, color: textColor, size: 20),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('Balance de deudas', 'Debt balance'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              balanceText,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // Grupos en comun
            Text(
              tr('Grupos en comun', 'Common groups'),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            if (commonGroups.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.group_off_outlined,
                        color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tr('No tienen grupos en comun todavia.', 'No common groups yet.'),
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...commonGroups.map(
                (group) => Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.group,
                          color: colorScheme.onSecondaryContainer, size: 20),
                    ),
                    title: Text(group.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(tr('${group.members.length} miembros', '${group.members.length} members')),
                  ),
                ),
              ),

            const SizedBox(height: 32),

            // Botón eliminar amigo
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
                side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.person_remove_outlined),
              label: Text(tr('Eliminar amigo', 'Remove friend')),
              onPressed: () => _confirmRemoveFriend(context),
            ),
          ],
        );
      },
    );
  }
}

// =============================================================================
// Widget: Pestaña de Lista de Amigos
// =============================================================================
class _FriendProfileCache {
  final String email;
  final String name;
  final String? photoUrl;
  _FriendProfileCache({required this.email, required this.name, this.photoUrl});
}

class _FriendsListTab extends StatefulWidget {
  final String currentEmail;
  final FirestoreService service;
  final void Function(BuildContext, String) onTapFriend;

  const _FriendsListTab({
    required this.currentEmail,
    required this.service,
    required this.onTapFriend,
  });

  @override
  State<_FriendsListTab> createState() => _FriendsListTabState();
}

class _FriendsListTabState extends State<_FriendsListTab> {
  late final Stream<List<FriendRequest>> _friendsStream;
  String _searchQuery = '';
  final TextEditingController _searchTabController = TextEditingController();
  List<FriendRequest>? _lastFriendsList;
  Future<List<_FriendProfileCache>>? _resolvedFriendsFuture;

  @override
  void initState() {
    super.initState();
    _friendsStream = widget.service.friendsStream(widget.currentEmail);
  }

  @override
  void dispose() {
    _searchTabController.dispose();
    super.dispose();
  }

  bool _areFriendListsEqual(List<FriendRequest> a, List<FriendRequest> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].status != b[i].status) return false;
    }
    return true;
  }

  Future<List<_FriendProfileCache>> _resolveFriendProfiles(List<FriendRequest> friends) async {
    final List<Future<_FriendProfileCache>> futures = friends.map((req) async {
      final cleanFrom = req.fromEmail.trim().toLowerCase();
      final cleanTo = req.toEmail.trim().toLowerCase();
      final cleanCurrent = widget.currentEmail.trim().toLowerCase();
      final friendEmail = cleanFrom == cleanCurrent ? cleanTo : cleanFrom;
      final userData = await widget.service.getUserDataByEmail(friendEmail);
      final name = userData?['displayName'] as String? ?? friendEmail.split('@')[0];
      final photoUrl = userData?['photoUrl'] as String?;
      return _FriendProfileCache(email: friendEmail, name: name, photoUrl: photoUrl);
    }).toList();
    return Future.wait(futures);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return StreamBuilder<List<FriendRequest>>(
      stream: _friendsStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text(tr('Error al cargar: ${snap.error}', 'Error loading: ${snap.error}')),
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final friends = snap.data ?? [];
        if (friends.isEmpty) {
          _lastFriendsList = null;
          _resolvedFriendsFuture = null;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 64,
                    color: colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    tr('No tienes amigos agregados aun.', 'You haven\'t added any friends yet.'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('Usa el boton de abajo para agregar a alguien por su correo.', 'Use the button below to add someone by their email.'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        if (_lastFriendsList == null || !_areFriendListsEqual(_lastFriendsList!, friends)) {
          _lastFriendsList = friends;
          _resolvedFriendsFuture = _resolveFriendProfiles(friends);
        }

        return FutureBuilder<List<_FriendProfileCache>>(
          future: _resolvedFriendsFuture,
          builder: (context, profileSnap) {
            if (profileSnap.connectionState == ConnectionState.waiting && !profileSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final resolved = profileSnap.data ?? [];
            final filtered = resolved.where((friend) {
              final query = _searchQuery.toLowerCase();
              return friend.name.toLowerCase().contains(query) ||
                     friend.email.toLowerCase().contains(query);
            }).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    controller: _searchTabController,
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: tr('Buscar amigo por nombre o correo...', 'Search friend by name or email...'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchTabController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
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
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            tr('No se encontraron amigos.', 'No friends found.'),
                            style: TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final friend = filtered[index];
                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: CircleAvatar(
                                  radius: 24,
                                  backgroundColor: colorScheme.primaryContainer,
                                  backgroundImage: friend.photoUrl != null
                                      ? MemoryImage(base64Decode(friend.photoUrl!))
                                      : null,
                                  child: friend.photoUrl == null
                                      ? Text(
                                          friend.name.substring(0, 1).toUpperCase(),
                                          style: TextStyle(
                                            color: colorScheme.onPrimaryContainer,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null,
                                ),
                                title: Text(friend.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  friend.email,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                trailing: Icon(Icons.chevron_right, color: colorScheme.outlineVariant),
                                onTap: () => widget.onTapFriend(context, friend.email),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// =============================================================================
// Widget: Pestaña de Solicitudes Pendientes
// =============================================================================
class _PendingRequestsTab extends StatefulWidget {
  final String currentEmail;
  final FirestoreService service;

  const _PendingRequestsTab({
    required this.currentEmail,
    required this.service,
  });

  @override
  State<_PendingRequestsTab> createState() => _PendingRequestsTabState();
}

class _PendingRequestsTabState extends State<_PendingRequestsTab> {
  late final Stream<List<FriendRequest>> _pendingRequestsStream;

  @override
  void initState() {
    super.initState();
    _pendingRequestsStream = widget.service.pendingFriendRequestsStream(widget.currentEmail);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return StreamBuilder<List<FriendRequest>>(
      stream: _pendingRequestsStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text(tr('Error al cargar: ${snap.error}', 'Error loading: ${snap.error}')),
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final requests = snap.data ?? [];
        if (requests.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.mark_email_read_outlined,
                    size: 64,
                    color: colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    tr('No tienes solicitudes pendientes.', 'You have no pending requests.'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          itemCount: requests.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final req = requests[index];
            return _PendingRequestTile(
              request: req,
              service: widget.service,
              context: context,
            );
          },
        );
      },
    );
  }
}
