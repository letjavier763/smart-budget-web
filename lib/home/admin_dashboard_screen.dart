import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:proyecto_app/models/group.dart';
import 'package:proyecto_app/services/firestore_service.dart';
import 'package:proyecto_app/theme/translations.dart';
import 'package:proyecto_app/widgets/group_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proyecto_app/main.dart';
import 'package:proyecto_app/utils/print_utility.dart';

class AdminDashboardScreen extends StatefulWidget {
  final VoidCallback onExitAdminMode;

  const AdminDashboardScreen({super.key, required this.onExitAdminMode});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with TickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  final String _currentEmail =
      FirebaseAuth.instance.currentUser?.email?.toLowerCase() ?? '';

  late final TabController _tabController;
  late final Stream<List<Map<String, dynamic>>> _usersStream;
  late final Stream<List<GroupModel>> _groupsStream;

  // Cache latest stream data so the AppBar export button can use it.
  // Updated via callbacks from child tab widgets.
  List<GroupModel> _latestGroups = [];
  List<Map<String, dynamic>> _latestUsers = [];

  @override
  void initState() {
    super.initState();
    _usersStream = _firestoreService.getAllUsersStream();
    _groupsStream = _firestoreService.getAllGroupsStream();
    // No addListener with setState here — that causes setState during
    // mouse-event processing → mouse_tracker assertion crash on Flutter web.
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─── PDF EXPORT ────────────────────────────────────────────────────────────
  void _exportCurrentTabPdf() {
    // Read index directly at call time — no setState tracking needed.
    switch (_tabController.index) {
      case 0:
        _exportStatisticsPdf(_latestGroups);
        break;
      case 1:
        _exportUsersPdf(_latestUsers);
        break;
      case 2:
        _exportGroupsPdf(_latestGroups);
        break;
    }
  }

  void _exportUsersPdf(List<Map<String, dynamic>> users) {
    final List<List<String>> data = [
      [tr('Nombre', 'Name'), tr('Correo Electrónico', 'Email'), tr('Rol', 'Role')],
    ];
    for (var u in users) {
      final email = u['email'] as String? ?? '';
      final name = u['displayName'] as String? ?? email.split('@')[0];
      final role = u['role'] as String? ?? 'user';
      data.add([name, email, role.toUpperCase()]);
    }
    printTabPdf(
      title: tr('Reporte de Usuarios del Sistema', 'System Users Report'),
      headersAndData: data,
    );
  }

  void _exportGroupsPdf(List<GroupModel> groups) {
    final List<List<String>> data = [
      [
        tr('Nombre de Grupo', 'Group Name'),
        tr('Código', 'Code'),
        tr('Miembros', 'Members'),
        tr('Creado por', 'Created By'),
      ],
    ];
    for (var g in groups) {
      data.add([g.name, g.code, '${g.members.length}', g.createdBy.split('@')[0]]);
    }
    printTabPdf(
      title: tr('Reporte de Grupos del Sistema', 'System Groups Report'),
      headersAndData: data,
    );
  }

  void _exportStatisticsPdf(List<GroupModel> groups) {
    final int totalMembers = groups.fold<int>(0, (sum, g) => sum + g.members.length);
    final double avgMembers = groups.isNotEmpty ? totalMembers / groups.length : 0.0;
    int smallCount = 0, mediumCount = 0, largeCount = 0;
    for (var g in groups) {
      if (g.members.length <= 2) {
        smallCount++;
      } else if (g.members.length <= 5) {
        mediumCount++;
      } else {
        largeCount++;
      }
    }
    final List<List<String>> data = [
      [tr('Métrica', 'Metric'), tr('Valor', 'Value')],
      [tr('Total de Grupos', 'Total Groups'), '${groups.length}'],
      [tr('Total de Miembros', 'Total Members'), '$totalMembers'],
      [tr('Promedio Miembros / Grupo', 'Avg Members / Group'), avgMembers.toStringAsFixed(1)],
      [tr('Grupos Pequeños (1-2)', 'Small Groups (1-2)'), '$smallCount'],
      [tr('Grupos Medianos (3-5)', 'Medium Groups (3-5)'), '$mediumCount'],
      [tr('Grupos Grandes (6+)', 'Large Groups (6+)'), '$largeCount'],
    ];
    printTabPdf(
      title: tr('Reporte de Estadísticas Generales', 'General Statistics Report'),
      headersAndData: data,
    );
  }

  // ─── DIALOGS ───────────────────────────────────────────────────────────────
  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Cerrar Sesión', 'Log Out')),
        content: Text(tr(
          '¿Estás seguro de que deseas cerrar tu sesión?',
          'Are you sure you want to log out?',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancelar', 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Salir', 'Exit'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('demo_admin_mode', false);
      adminDemoNotifier.value = false;
      await FirebaseAuth.instance.signOut();
    }
  }

  Future<void> _confirmDeleteUser(String uid, String email) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Eliminar Usuario', 'Delete User')),
        content: Text(tr(
          '¿Estás seguro de que deseas eliminar al usuario $email? Esta acción no se puede deshacer.',
          'Are you sure you want to delete user $email? This action cannot be undone.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancelar', 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Eliminar', 'Delete'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _firestoreService.deleteUser(uid);
        messenger.showSnackBar(SnackBar(
            content: Text(
                tr('Usuario eliminado exitosamente.', 'User deleted successfully.'))));
      } catch (e) {
        messenger.showSnackBar(SnackBar(
            content: Text('${tr('Error al eliminar', 'Error deleting')}: $e')));
      }
    }
  }

  Future<void> _confirmDeleteGroup(GroupModel group) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Eliminar Grupo', 'Delete Group')),
        content: Text(tr(
          '¿Estás seguro de que deseas eliminar el grupo "${group.name}"? Se borrarán todos los datos del grupo permanentemente.',
          'Are you sure you want to delete group "${group.name}"? All group data will be permanently deleted.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancelar', 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Eliminar', 'Delete'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _firestoreService.deleteGroup(groupId: group.id);
        messenger.showSnackBar(SnackBar(
            content: Text(
                tr('Grupo eliminado exitosamente.', 'Group deleted successfully.'))));
      } catch (e) {
        messenger.showSnackBar(SnackBar(
            content: Text('${tr('Error al eliminar', 'Error deleting')}: $e')));
      }
    }
  }

  Future<void> _toggleUserRole(String uid, String currentRole) async {
    final newRole = currentRole == 'admin' ? 'user' : 'admin';
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _firestoreService.updateUserRole(uid, newRole);
      messenger.showSnackBar(SnackBar(
          content:
              Text(tr('Rol de usuario actualizado.', 'User role updated.'))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(
              '${tr('Error al actualizar rol', 'Error updating role')}: $e')));
    }
  }

  // ─── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Panel de Administración Central', 'Central Administration Panel'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        actions: [
          // PDF export button — single button that exports the active tab
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
            tooltip: tr('Exportar PDF', 'Export PDF'),
            onPressed: _exportCurrentTabPdf,
          ),
          TextButton.icon(
            onPressed: widget.onExitAdminMode,
            icon: const Icon(Icons.swap_horiz, color: Colors.white),
            label: Text(tr('Modo Cliente', 'Client Mode'),
                style: const TextStyle(color: Colors.white)),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: tr('Cerrar sesión', 'Logout'),
            onPressed: _logout,
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
                icon: const Icon(Icons.analytics_outlined),
                text: tr('Estadísticas', 'Analytics')),
            Tab(
                icon: const Icon(Icons.people_outline),
                text: tr('Usuarios', 'Users')),
            Tab(
                icon: const Icon(Icons.group_outlined),
                text: tr('Grupos', 'Groups')),
          ],
          indicatorColor: colorScheme.onPrimary,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildAnalyticsTab(),
            _UsersTabView(
              stream: _usersStream,
              currentEmail: _currentEmail,
              onToggleRole: _toggleUserRole,
              onDeleteUser: _confirmDeleteUser,
              onUsersUpdated: (u) => _latestUsers = u,
            ),
            _GroupsTabView(
              stream: _groupsStream,
              onDeleteGroup: _confirmDeleteGroup,
              onGroupsUpdated: (g) => _latestGroups = g,
            ),
          ],
        ),
      ),
    );
  }

  // ─── TAB 1: ANALYTICS ──────────────────────────────────────────────────────
  Widget _buildAnalyticsTab() {
    return StreamBuilder<List<GroupModel>>(
      stream: _firestoreService.getAllGroupsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final groups = snapshot.data ?? [];
        // Update cache for PDF export
        _latestGroups = groups;

        if (groups.isEmpty) {
          return Center(
            child: Text(tr('No hay grupos registrados en el sistema.',
                'No groups registered in the system.')),
          );
        }

        final int totalMembers =
            groups.fold<int>(0, (sum, g) => sum + g.members.length);
        final double avgMembers =
            groups.isNotEmpty ? totalMembers / groups.length : 0.0;

        // SingleChildScrollView(vertical) → unbounded height.
        // NEVER use Expanded/Flex-vertical inside it.
        // LayoutBuilder inside it gives bounded width → Row+Expanded is safe.
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Stat Cards ──────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      title: tr('Total de Grupos', 'Total Groups'),
                      value: '${groups.length}',
                      icon: Icons.group_work_outlined,
                      gradient: const LinearGradient(
                          colors: [Color(0xFF003289), Color(0xFF0052D4)]),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      title: tr('Total de Miembros', 'Total Members'),
                      value: '$totalMembers',
                      icon: Icons.people_outline,
                      gradient: const LinearGradient(
                          colors: [Color(0xFF005C3E), Color(0xFF008A56)]),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      title:
                          tr('Miembros por Grupo (Prom.)', 'Avg Members / Group'),
                      value: avgMembers.toStringAsFixed(1),
                      icon: Icons.bar_chart_outlined,
                      gradient: const LinearGradient(
                          colors: [Color(0xFFBA1A1A), Color(0xFFE53935)]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              // ── Charts ──────────────────────────────────────────────────
              // LayoutBuilder inside SingleChildScrollView(vertical):
              //   maxWidth = bounded (viewport width) ✓
              //   maxHeight = infinite ✗  → do NOT use Expanded vertically
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 700;

                  final pieCard = _buildChartCard(
                    title: tr('Distribución de Miembros por Grupo',
                        'Group Size Distribution'),
                    child: _buildPieChart(groups),
                  );
                  final barCard = _buildChartCard(
                    title: tr('Comparación de Miembros (Top 5)',
                        'Member Count (Top 5)'),
                    child: _buildBarChart(groups),
                  );

                  if (isWide) {
                    // Row + Expanded: safe because width is bounded
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: pieCard),
                        const SizedBox(width: 20),
                        Expanded(child: barCard),
                      ],
                    );
                  }
                  // Narrow: Column without Expanded — vertical axis unbounded
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [pieCard, const SizedBox(height: 20), barCard],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChartCard({required String title, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 24),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Gradient gradient,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(20),
      height: 120,
      child: Stack(
        children: [
          Positioned(
            right: 0,
            bottom: 0,
            child: Icon(icon, size: 64, color: Colors.white10),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPieChart(List<GroupModel> groups) {
    int smallCount = 0, mediumCount = 0, largeCount = 0;
    for (var g in groups) {
      if (g.members.length <= 2) {
        smallCount++;
      } else if (g.members.length <= 5) {
        mediumCount++;
      } else {
        largeCount++;
      }
    }
    final total = groups.length;
    final smallPct = total > 0 ? (smallCount / total) : 0.0;
    final mediumPct = total > 0 ? (mediumCount / total) : 0.0;
    final largePct = total > 0 ? (largeCount / total) : 0.0;

    return Row(
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: CustomPaint(
            painter: _PieChartPainter(
              slices: [smallPct, mediumPct, largePct],
              colors: const [
                Color(0xFF003289),
                Color(0xFF008A56),
                Color(0xFFBA1A1A),
              ],
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLegendItem(
                  tr('Pequeños (1-2)', 'Small (1-2)'),
                  '${(smallPct * 100).toStringAsFixed(1)}%',
                  const Color(0xFF003289)),
              const SizedBox(height: 8),
              _buildLegendItem(
                  tr('Medianos (3-5)', 'Medium (3-5)'),
                  '${(mediumPct * 100).toStringAsFixed(1)}%',
                  const Color(0xFF008A56)),
              const SizedBox(height: 8),
              _buildLegendItem(
                  tr('Grandes (6+)', 'Large (6+)'),
                  '${(largePct * 100).toStringAsFixed(1)}%',
                  const Color(0xFFBA1A1A)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, String value, Color color) {
    return Row(
      children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        const SizedBox(width: 8),
        Text(value,
            style:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildBarChart(List<GroupModel> groups) {
    final sorted = List<GroupModel>.from(groups)
      ..sort((a, b) => b.members.length.compareTo(a.members.length));
    final top = sorted.take(5).toList();
    int maxM = top.isNotEmpty ? top.first.members.length : 1;
    if (maxM < 1) maxM = 1;

    return SizedBox(
      height: 140,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: top.map((g) {
          final hFactor = g.members.length / maxM;
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('${g.members.length}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 11)),
                const SizedBox(height: 4),
                Container(
                  height: (hFactor * 90).clamp(5.0, 90.0),
                  margin: const EdgeInsets.symmetric(horizontal: 8.0),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF003289), Color(0xFF6A1B9A)],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  g.name.length > 8 ? '${g.name.substring(0, 7)}…' : g.name,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _UsersTabView extends StatefulWidget {
  final Stream<List<Map<String, dynamic>>> stream;
  final String currentEmail;
  final Function(String uid, String role) onToggleRole;
  final Function(String uid, String email) onDeleteUser;
  final ValueChanged<List<Map<String, dynamic>>> onUsersUpdated;

  const _UsersTabView({
    required this.stream,
    required this.currentEmail,
    required this.onToggleRole,
    required this.onDeleteUser,
    required this.onUsersUpdated,
  });

  @override
  State<_UsersTabView> createState() => _UsersTabViewState();
}

class _UsersTabViewState extends State<_UsersTabView> {
  final TextEditingController _usersSearchController = TextEditingController();
  String _usersQuery = '';

  @override
  void initState() {
    super.initState();
    _usersSearchController.addListener(() {
      setState(() {
        _usersQuery = _usersSearchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _usersSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: widget.stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final users = snapshot.data ?? [];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onUsersUpdated(users);
        });

        // Apply search filter
        final filtered = _usersQuery.isEmpty
            ? users
            : users.where((u) {
                final email = (u['email'] as String? ?? '').toLowerCase();
                final name = (u['displayName'] as String? ?? '').toLowerCase();
                final role = (u['role'] as String? ?? '').toLowerCase();
                return email.contains(_usersQuery) ||
                    name.contains(_usersQuery) ||
                    role.contains(_usersQuery);
              }).toList();

        return Column(
          children: [
            // ── Search bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _usersSearchController,
                decoration: InputDecoration(
                  hintText: tr('Buscar usuarios…', 'Search users…'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _usersQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: tr('Limpiar', 'Clear'),
                          onPressed: () => _usersSearchController.clear(),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                ),
              ),
            ),
            // ── Result count hint ──────────────────────────────────────────
            if (_usersQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr(
                      '${filtered.length} resultado(s) de ${users.length}',
                      '${filtered.length} result(s) of ${users.length}',
                    ),
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            // ── List ────────────────────────────────────────────────────────
            if (filtered.isEmpty && users.isNotEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    tr('Sin resultados para "$_usersQuery".',
                        'No results for "$_usersQuery".'),
                  ),
                ),
              )
            else if (users.isEmpty)
              Expanded(
                child: Center(
                  child: Text(tr('No hay usuarios registrados.',
                      'No registered users.'))),
                )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final user = filtered[index];
                    final email = user['email'] as String? ?? '';
                    final name =
                        user['displayName'] as String? ?? email.split('@')[0];
                    final photoUrl = user['photoUrl'] as String?;
                    final role = user['role'] as String? ?? 'user';
                    final uid = user['uid'] as String;
                    final isSelf = email == widget.currentEmail;

                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: colorScheme.primaryContainer,
                          backgroundImage: _getUserAvatarImage(photoUrl),
                          child: _getUserAvatarImage(photoUrl) == null
                              ? Text(
                                  name.isNotEmpty
                                      ? name.substring(0, 1).toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                      color: colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.bold))
                              : null,
                        ),
                        title: Row(
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: role == 'admin'
                                    ? colorScheme.primaryContainer
                                    : colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                role.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: role == 'admin'
                                      ? colorScheme.onPrimaryContainer
                                      : colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(email,
                            style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 13)),
                        trailing: isSelf
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                        role == 'admin'
                                            ? Icons.verified_user
                                            : Icons.security,
                                        color: Colors.blue),
                                    tooltip: role == 'admin'
                                        ? tr('Quitar Admin', 'Revoke Admin')
                                        : tr('Hacer Admin', 'Make Admin'),
                                    onPressed: () =>
                                        widget.onToggleRole(uid, role),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    tooltip: tr('Eliminar', 'Delete'),
                                    onPressed: () =>
                                        widget.onDeleteUser(uid, email),
                                  ),
                                ],
                              ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  ImageProvider? _getUserAvatarImage(String? photoUrl) {
    if (photoUrl == null || photoUrl.isEmpty) return null;
    if (photoUrl.startsWith('http://') || photoUrl.startsWith('https://')) {
      return NetworkImage(photoUrl);
    }
    try {
      return MemoryImage(base64Decode(photoUrl));
    } catch (e) {
      debugPrint('Error decoding user base64 photo: $e');
      return null;
    }
  }
}

class _GroupsTabView extends StatefulWidget {
  final Stream<List<GroupModel>> stream;
  final Function(GroupModel group) onDeleteGroup;
  final ValueChanged<List<GroupModel>> onGroupsUpdated;

  const _GroupsTabView({
    required this.stream,
    required this.onDeleteGroup,
    required this.onGroupsUpdated,
  });

  @override
  State<_GroupsTabView> createState() => _GroupsTabViewState();
}

class _GroupsTabViewState extends State<_GroupsTabView> {
  final TextEditingController _groupsSearchController = TextEditingController();
  String _groupsQuery = '';

  @override
  void initState() {
    super.initState();
    _groupsSearchController.addListener(() {
      setState(() {
        _groupsQuery = _groupsSearchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _groupsSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<List<GroupModel>>(
      stream: widget.stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final groups = snapshot.data ?? [];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onGroupsUpdated(groups);
        });

        // Apply search filter
        final filtered = _groupsQuery.isEmpty
            ? groups
            : groups.where((g) {
                final name = g.name.toLowerCase();
                final code = g.code.toLowerCase();
                final creator = g.createdBy.toLowerCase();
                return name.contains(_groupsQuery) ||
                    code.contains(_groupsQuery) ||
                    creator.contains(_groupsQuery);
              }).toList();

        return Column(
          children: [
            // ── Search bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _groupsSearchController,
                decoration: InputDecoration(
                  hintText: tr('Buscar grupos…', 'Search groups…'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _groupsQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: tr('Limpiar', 'Clear'),
                          onPressed: () => _groupsSearchController.clear(),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                ),
              ),
            ),
            // ── Result count hint ──────────────────────────────────────────
            if (_groupsQuery.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr(
                      '${filtered.length} resultado(s) de ${groups.length}',
                      '${filtered.length} result(s) of ${groups.length}',
                    ),
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            // ── List ────────────────────────────────────────────────────────
            if (filtered.isEmpty && groups.isNotEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    tr('Sin resultados para "$_groupsQuery".',
                        'No results for "$_groupsQuery".'),
                  ),
                ),
              )
            else if (groups.isEmpty)
              Expanded(
                child: Center(
                  child: Text(tr('No hay grupos activos en el sistema.',
                      'No active groups in the system.')),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final group = filtered[index];
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: GroupAvatar(group: group, size: 40),
                        title: Text(group.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          tr(
                            '${group.members.length} miembros • Creado por ${group.createdBy.split('@')[0]}',
                            '${group.members.length} members • Created by ${group.createdBy.split('@')[0]}',
                          ),
                          style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 13),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                group.code,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_forever_outlined,
                                  color: Colors.red),
                              tooltip: tr('Eliminar Grupo', 'Delete Group'),
                              onPressed: () => widget.onDeleteGroup(group),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─── PIE CHART PAINTER ───────────────────────────────────────────────────────
class _PieChartPainter extends CustomPainter {
  final List<double> slices;
  final List<Color> colors;

  const _PieChartPainter({required this.slices, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final double total = slices.fold(0, (sum, val) => sum + val);
    if (total == 0) return;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    double startAngle = -3.14159 / 2;

    for (var i = 0; i < slices.length; i++) {
      if (slices[i] <= 0) continue;
      final sweepAngle = (slices[i] / total) * 2 * 3.14159265;
      paint.color = colors[i];
      canvas.drawArc(rect, startAngle, sweepAngle, true, paint);
      startAngle += sweepAngle;
    }

    final centerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(
        Offset(size.width / 2, size.height / 2), size.width * 0.25, centerPaint);
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) =>
      oldDelegate.slices != slices || oldDelegate.colors != colors;
}
